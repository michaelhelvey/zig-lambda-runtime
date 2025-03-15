/// Copyright (c) 2025, Michael Helvey <michael@michaelhelvey.dev>
///
/// License: MIT
///
/// A single-file library exposing a custom runtime for AWS Lambda in Zig.
/// References:
///    - Source: https://github.com/michaelhelvey/zig-lambda-runtime
///    - Documentation: https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html
const std = @import("std");
const builtin = @import("builtin");

/// Models an event retrieved from the AWS Lambda invocation's API.
pub const Event = struct {
    /// page-allocator backed arena that can be used as scratch space during
    /// the lifetime of each function invocation.  this allocator will be freed
    /// following each function invocation.
    scratch: std.mem.Allocator,
    /// the lambda payload retrieved from the runtime api
    payload: []const u8,
    /// the request id retrieved from the runtime api
    request_id: []const u8,
    /// the x-ray trace id provided to the invocation.  the _X_AMZN_TRACE_ID
    /// environment variable is automatically propagated by the runtime based on
    /// this variable
    trace_id: []const u8,
};

pub const Result = union(enum) { success: []const u8, err: HandlerError };

pub const HandlerError = struct {
    message: []const u8,
    typ: []const u8,
};

/// A vtable representing the handler interface that user functions are expected
/// to assume.
pub const Handler = struct {
    ptr: *anyopaque,
    handlerFn: *const fn (
        ctx: *anyopaque,
        event: *const Event,
    ) Result,
};

/// The runtime context that is passed to each user function, allowing them to
/// manually post success or error responses back to the runtime api.
pub const RuntimeContext = struct {
    runtime_api: []const u8,

    const Self = @This();

    pub fn init(runtime_api: []const u8) Self {
        return .{
            .runtime_api = runtime_api,
        };
    }

    /// Posts a success response with the given payload back to the runtime api.  Note that it is
    /// an error to do any further work in your function after calling this method.
    fn post_success_response(
        self: *const Self,
        allocator: std.mem.Allocator,
        request_id: []const u8,
        payload: []const u8,
    ) !void {
        try self.post_response(allocator, request_id, "response", payload);
    }

    /// Posts an error response with the given reason and payload back to the runtime api.  Note
    /// that it is an error to do any further work in your function after calling this method.
    fn post_error_response(
        self: *const Self,
        allocator: std.mem.Allocator,
        request_id: []const u8,
        reason: []const u8,
        payload: []const u8,
    ) !void {
        const body = try std.fmt.allocPrint(
            allocator,
            "{{ \"errorMessage\": \"{s}\", \"errorType\": \"{s}\", \"stackTrace\": [] }}",
            .{ payload, reason },
        );
        try self.post_response(allocator, request_id, "error", body);
    }

    fn post_response(
        self: *const Self,
        allocator: std.mem.Allocator,
        request_id: []const u8,
        endpoint: []const u8,
        payload: []const u8,
    ) !void {
        var storage = std.ArrayList(u8).init(allocator);
        const url = try std.fmt.allocPrint(
            allocator,
            "http://{s}/2018-06-01/runtime/invocation/{s}/{s}",
            .{ self.runtime_api, request_id, endpoint },
        );
        var client = std.http.Client{ .allocator = allocator };
        const response = try client.fetch(.{
            .method = .POST,
            .location = .{ .url = url },
            .response_storage = .{ .dynamic = &storage },
            .payload = payload,
        });

        if (response.status.class() != .success) {
            std.log.err("runtime: error posting invocation response: {any}: {s}", .{ response.status, storage.items });
            return error.ResponseError;
        }
    }

    fn fetch_next_invocation(self: *const Self, allocator: std.mem.Allocator) !Event {
        const url = try std.fmt.allocPrint(allocator, "http://{s}/2018-06-01/runtime/invocation/next", .{self.runtime_api});
        var storage = std.ArrayList(u8).init(allocator);
        var client = std.http.Client{ .allocator = allocator };

        var server_header_buffer: [4 * 1024]u8 = undefined;
        const response = try client.fetch(.{
            .method = .GET,
            .location = .{ .url = url },
            .response_storage = .{ .dynamic = &storage },
            .server_header_buffer = &server_header_buffer,
        });

        if (response.status.class() != .success) {
            std.log.err("runtime: error fetching next invocation: {s}", .{storage.items});
            return error.NextInvocationError;
        }

        var request_id: []u8 = undefined;
        var trace_id: []u8 = undefined;
        var iter = std.http.HeaderIterator.init(&server_header_buffer);
        while (iter.next()) |header| {
            if (std.mem.eql(u8, header.name, "Lambda-Runtime-Aws-Request-Id")) {
                request_id = try allocator.alloc(u8, header.value.len);
                @memcpy(request_id, header.value);
            }
            if (std.mem.eql(u8, header.name, "Lambda-Runtime-Trace-Id")) {
                trace_id = try allocator.alloc(u8, header.value.len);
                @memcpy(trace_id, header.value);
            }
        }

        return .{
            .payload = storage.items,
            .scratch = allocator,
            .request_id = request_id,
            .trace_id = trace_id,
        };
    }
};

pub fn init_runtime(handler: Handler) void {
    var runtime_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = runtime_allocator.allocator();
    defer runtime_allocator.deinit();

    var env_map = std.process.getEnvMap(allocator) catch |e| {
        std.log.err("runtime: unable to allocate space for environment variables: {!}", .{e});
        return;
    };

    const runtime_api = env_map.get("AWS_LAMBDA_RUNTIME_API") orelse {
        std.log.err("runtime: unable to get AWS_LAMBDA_RUNTIME_API", .{});
        return;
    };

    const runtime_context = RuntimeContext.init(runtime_api);

    while (true) {
        var function_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const scratch_alloc = function_allocator.allocator();
        defer function_allocator.deinit();

        const event = runtime_context.fetch_next_invocation(scratch_alloc) catch |e| {
            // note that we have no request id at this point, so if this fails,
            // we just have to crash.
            std.log.err("could not fetch next event from runtime api: {!}", .{e});
            std.process.exit(1);
            return;
        };
        env_map.put("_X_AMZN_TRACE_ID", event.trace_id) catch unreachable;
        std.log.debug("runtime: invoking user handler with event: {s}", .{event.payload});

        const result = handler.handlerFn(handler.ptr, &event);
        switch (result) {
            .success => |payload| {
                std.log.debug("runtime: posting success response to api: {s}", .{payload});
                runtime_context.post_success_response(event.scratch, event.request_id, payload) catch |e| {
                    std.log.err("runtime: unable to post success response to api: {!}", .{e});
                    return;
                };
            },
            .err => |err| {
                std.log.debug("runtime: posting error response to api: {s}: {s}", .{ err.typ, err.message });
                runtime_context.post_error_response(event.scratch, event.request_id, err.typ, err.message) catch |e| {
                    std.log.err("runtime: unable to post error response to api: {!}", .{e});
                    return;
                };
            },
        }

        if (builtin.mode == .Debug) {
            std.log.debug("runtime: breaking after a single event because we were built in debug mode", .{});
            return;
        }
    }
}
