const std = @import("std");
const Parser = @import("Parser.zig");
const Value = @import("value.zig").Value;
const Environment = @import("Environment.zig");

pub const Error = error{
    UndefinedVariable,
    InvalidConversion,
    NotAnAsciiInteger,
    InvalidType,
    EmptyString,
    DomainError,
} || Parser.Error || std.os.WriteError || error{
    // todo: make all these unions with builtin type somehow
    OutOfMemory,
    DivisionByZero,
    Overflow,
    NegativeDenominator,
    Underflow,
    StreamTooLong,
} || std.os.Error || std.os.ConnectError || std.os.ReadError || std.os.WriteError;

pub fn play(source: []const u8, env: *Environment) Error!Value {
    var program = try (Parser{ .source = source }).next(env);
    defer program.decrement(env.allocator);

    return program.run(env);
}

// test "assign a variable after fetching" {
//     var env = Environment.init(std.testing.allocator);
//     defer env.deinit();

//     (try env.fetch(.Borrowed, "abc")).assign(env.allocator, Value.one);
//     var program = try play("abc", &env);
//     defer program.decrement(env.allocator);
// }
