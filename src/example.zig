const lambda = @import("lambda");
const std = @import("std");

const CustomHandler = struct {
    fn handle(self: *anyopaque, event: *const lambda.Event) lambda.Result {
        _ = self;
        std.debug.print("handler: received event from runtime: {s}\n", .{event.payload});
        return .{ .success = "here do be my response" };
    }

    fn handler(self: *CustomHandler) lambda.Handler {
        return .{
            .ptr = self,
            .handlerFn = handle,
        };
    }
};

pub fn main() !void {
    var custom_handler = CustomHandler{};
    lambda.init_runtime(custom_handler.handler());
}
