const std = @import("std");
const Allocator = std.mem.Allocator;
const String = @import("String.zig");

const value = @import("value.zig");
const Value = value.Value;

const Environment = @import("Environment.zig");
const Parser = @This();

/// Errors that can occur whilst parsing `Value`s.
pub const Error = error{
    /// The end of the stream was reached when parsing.
    EndOfStream,

    /// A string was not terminated.
    StringDoesntEnd,

    /// An unknown character was encountered.
    UnknownTokenStart,

    /// An integer literal overflowed.
    IntegerLiteralOverflow,

    /// Memory error happened
    OutOfMemory,
};

/// The source code for the parser.
source: []const u8,
/// The current index into `source`.
index: usize = 0,

/// Returns whether the parser is at the end.
pub fn isEof(parser: *const Parser) bool {
    return parser.index == parser.source.len;
}

/// Fetch the next character, if it exists, without consuming it.
fn peek(parser: *const Parser) ?u8 {
    return if (parser.isEof()) null else parser.source[parser.index];
}

/// Consumes the current character, advancing the stream. `Panics` when called at `Eof`.
fn advance(parser: *Parser) void {
    if (parser.isEof()) {
        @panic("`advance` called when at eof?");
    }

    parser.index += 1;
}

/// Returns the next character, if it exists, and advances the stream.
fn peekAdvance(parser: *Parser) ?u8 {
    const chr = parser.peek() orelse return null;
    parser.advance();
    return chr;
}

/// Removes all leading whitespace and comments.
fn stripWhitespaceAndComments(parser: *Parser) void {
    while (parser.peek()) |chr| {
        switch (chr) {
            ' ', '\n', '\r', '\t', '(', ')', '[', ']', '{', '}', ':' => parser.advance(),
            '#' => while ('\n' != parser.peekAdvance() orelse return) {},
            else => return,
        }
    }
}

/// Fetches the next integer from the parser.
fn nextInteger(parser: *Parser) Error!value.Integer {
    var x: value.Integer = 0;

    while (parser.peek()) |c| {
        const digit = std.fmt.charToDigit(c, 10) catch break;
        parser.advance();

        if (@mulWithOverflow(@TypeOf(x), x, 10, &x)) {
            return Error.IntegerLiteralOverflow;
        }

        if (@addWithOverflow(@TypeOf(x), x, digit, &x)) {
            return Error.IntegerLiteralOverflow;
        }
    }

    return x;
}

/// Fetches the next identifier from the parser, looking it up in the `Environment`.
fn nextIdentifier(parser: *Parser, env: *Environment) !*Environment.Variable {
    const start = parser.index;

    while (parser.peek()) |c| {
        if (!std.ascii.isLower(c) and c != '_' and !std.ascii.isDigit(c)) {
            break;
        }

        parser.advance();
    }

    return env.fetch(.Borrowed, parser.source[start..parser.index]);
}

fn nextString(parser: *Parser, alloc: Allocator, interner: *String.Interner) !*String {
    const quote = parser.peekAdvance();
    const start = parser.index;

    while (parser.peekAdvance()) |c| {
        if (c == quote) {
            return try interner.fetch(alloc, parser.source[start..parser.index]);
        }
    }

    return Error.StringDoesntEnd;
}

pub fn next(parser: *Parser, env: *Environment) Error!Value {
    parser.stripWhitespaceAndComments();

    const chr = parser.peek() orelse return Error.EndOfStream;

    if (std.ascii.isUpper(chr)) {
        while (parser.peek()) |c| {
            if (!std.ascii.isUpper(c) and c != '_') {
                break;
            }

            parser.advance();
        }
    }

    return switch (chr) {
        '0'...'9' => Value.init(value.Integer, try parser.nextInteger()),
        'a'...'z', '_' => Value.init(*Environment.Variable, try parser.nextIdentifier(env)),
        '\'', '\"' => Value.init(*String, try parser.nextString(env.allocator, &env.interner)),
        'T', 'F' => Value.init(bool, chr == 'T'),
        'N' => Value.@"null",
        else => blk: {
            // todo: parse functions
            break :blk Error.UnknownTokenStart;
        },
    };
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "strips leading whitespace and comments" {
    var parser = Parser{ .source = "  #123\n  #1  \nT" };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try expectEqual(Value.@"true", try parser.next(&env));
}

test "parses integers" {
    var parser = Parser{ .source = "1234T" };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try expectEqual(Value.init(value.Integer, 1234), try parser.next(&env));
    try expectEqual(Value.@"true", try parser.next(&env));
}

test "parses booleans and null" {
    var parser = Parser{ .source = "TRUE FLS12N" };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try expectEqual(Value.@"true", try parser.next(&env));
    try expectEqual(Value.@"false", try parser.next(&env));
    try expectEqual(Value.init(value.Integer, 12), try parser.next(&env));
    try expectEqual(Value.@"null", try parser.next(&env));
}

test "parses strings" {
    var parser = Parser{ .source = "'a\"''b'\"'c\\\"123" };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    var @"a\"" = try parser.next(&env);
    defer @"a\"".decrement(env.allocator);
    try expectEqualStrings("a\"", (try @"a\"".cast(*String)).slice());

    var b = try parser.next(&env);
    defer b.decrement(env.allocator);
    try expectEqualStrings("b", (try b.cast(*String)).slice());

    var @"'c\\" = try parser.next(&env);
    defer @"'c\\".decrement(env.allocator);
    try expectEqualStrings("'c\\", (try @"'c\\".cast(*String)).slice());

    try expectEqual(Value.init(value.Integer, 123), try parser.next(&env));
}

test "parses variables" {
    var parser = Parser{ .source = "abc _def123_ 123abc" };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const abc = try parser.next(&env);
    try expectEqual(try env.fetch(.Borrowed, "abc"), try abc.cast(*Environment.Variable));
    try expectEqual(
        try env.fetch(.Borrowed, "_def123_"),
        try (try parser.next(&env)).cast(*Environment.Variable),
    );

    try expectEqual(Value.init(value.Integer, 123), try parser.next(&env));
    try expectEqual(abc, try parser.next(&env));
}
