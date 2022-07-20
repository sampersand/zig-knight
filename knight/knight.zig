const std = @import("std");
const Parser = @import("Parser.zig");
const Value = @import("value.zig").Value;
const Error = @import("error.zig").Error;
const Environment = @import("Environment.zig");

pub fn play(source: []const u8, env: *Environment) Error!Value {
    var parser = Parser{ .source = source };

    var program = try parser.next(env);
    defer program.decrement(env.allocator);

    return program.run(env);
}

test "assign a variable after fetching" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    var program = try play("abc", &env);
    (try env.fetch(.Borrowed, "abc")).assign(env.allocator, @import("value.zig").Value.one);
    defer program.decrement(env.allocator);
}
