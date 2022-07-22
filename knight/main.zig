const std = @import("std");
const Parser = @import("Parser.zig");
const Environment = @import("Environment.zig");
const knight = @import("knight.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var env = Environment.init(arena.allocator());
    defer env.deinit();

    var program = try knight.play("O + 1 A 'a'", &env);
    defer program.decrement(env.allocator);

    try program.dump(std.io.getStdOut().writer());

    // var program = Parser{ .source = "123" }.parse(&env) catch |e| std.debug.panic("error: {s}", .{e});
    // defer program.decrement();
}
