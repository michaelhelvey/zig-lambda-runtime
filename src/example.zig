const lambda = @import("lambda");
const std = @import("std");

pub fn main() !void {
    std.debug.print("example lambda function\n", .{});
    const result = lambda.add(2, 2);
    std.debug.print("calling into library, 2 + 2 = {d}\n", .{result});
}
