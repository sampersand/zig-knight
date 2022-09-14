const std = @import("std");
const Parser = @import("Parser.zig");
const Environment = @import("Environment.zig");
const knight = @import("knight.zig");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var env = try Environment.init(arena.allocator());
    defer env.deinit();

    var program = try knight.play(
        \\; = fizzbuzz BLOCK
        \\  ; = i 0
        \\  : WHILE < i max
        \\      ; = i + i 1
        \\      ; & (= div3 ! % i 3) OUTPUT "Fizz\"
        \\      ; & (= div5 ! % i 5) OUTPUT "Buzz\"
        \\      : OUTPUT IF (| div3 div5) "" i
        \\; = max 100
        \\#; CALL fizzbuzz
        \\: DUMP G "ABC" 0 4
    , &env);
    defer program.decrement(env.allocator);

    // var program = Parser{ .source = "123" }.parse(&env) catch |e| std.debug.panic("error: {s}", .{e});
    // defer program.decrement();
}

// pub fn main() anyerror!void {
//     // Note that info level log messages are by default printed only in Debug
//     // and ReleaseSafe build modes.
//     std.log.info("All your codebase are belong to us.", .{});
// }

// test "basic test" {
//     try std.testing.expectEqual(10, 3 + 7);
// }
