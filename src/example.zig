/// Example of how to use the runtime to write your own zig lambda functions:
const lambda = @import("lambda");
const std = @import("std");

// Every function must implement the `lambda.Handler` interface. This instance
// of the handler struct will live for the lifetime of the function runtime, so
// you can use it to store any "global" values you want, such as http clients,
// that you want to live over multiple invocations of the function.
const CustomHandler = struct {
    fn handle(self: *anyopaque, event: *const lambda.Event) lambda.Result {
        _ = self;
        std.debug.print("handler: received event from runtime: {s}\n", .{event.payload});

        // note that you are required to return either a success or an error type -- if you want
        // to use `try` syntax, do that in a separate function, and parse the return type here
        // to return the appropriate response to the runtime.
        return .{ .success = "here do be my response" };
    }

    fn handler(self: *CustomHandler) lambda.Handler {
        return .{
            .ptr = self,
            .handlerFn = handle,
        };
    }
};

pub fn main() void {
    var custom_handler = CustomHandler{};
    lambda.init_runtime(custom_handler.handler());
}
