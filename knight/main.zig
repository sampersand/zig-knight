const std = @import("std");
const Parser = @import("Parser.zig");
const Environment = @import("Environment.zig");
const knight = @import("knight.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var env = Environment.init(arena.allocator());
    defer env.deinit();

    var program = try knight.play(
        \\; = i 0
        \\; O & 9 1
        \\; = sum 0
        \\; WHILE < i 50
        \\      ; = sum + sum i
        \\      : = i + i 1
        \\: OUTPUT + "SUM(0..50)=" sum
    , &env); // => prints out `SUM(0..50)=1225`
    defer program.decrement(env.allocator);

    // var program = Parser{ .source = "123" }.parse(&env) catch |e| std.debug.panic("error: {s}", .{e});
    // defer program.decrement();
}
