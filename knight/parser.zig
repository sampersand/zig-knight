const std = @import("std");
const Allocator = std.mem.Allocator;
const value = @import("value");

pub const Token = union(enum) {
    identifier: []const u8,
    integer: i64,
    nil,
    boolean: bool,
    string: []const u8,
    function: u8,
};

pub const Error = error{
    EndOfStream,
    StringDoesntEnd,
    UnknownTokenStart,
    IntegerLiteralOverflow,
};

fn charToDigit(c: u8) ?u8 {
    return if ('0' <= c and c <= '9') c - '0' else null;
}

pub fn Parser(alloc: Allocator) type {
    return struct {
        source: []const u8,
        env: *Env,

        fn isEof(self: *const Parser) bool {
            return self.source.len == 0;
        }

        fn peek(self: *const Parser) ?u8 {
            return if (self.isEof()) null else self.source[0];
        }

        fn advance(self: *Parser) void {
            if (self.isEof()) {
                @panic("`advance` called when at eof?");
            }

            self.source = self.source[1..];
        }

        fn peekAdvance(self: *Parser) ?u8 {
            if (self.peek()) |chr| {
                self.advance();
                return chr;
            } else {
                return null;
            }
        }

        fn stripWhitespaceAndComments(self: *Parser) void {
            while (true) {
                switch (self.peek() orelse return) {
                    ' ', '\n', '\r', '\t', '(', ')', '[', ']', '{', '}', ':' => self.advance(),
                    '#' => while ('\n' != self.peekAdvance() orelse continue) {},
                    else => return,
                }
            }
        }

        fn stripKeyword(self: *Parser) void {
            while (self.peek()) |chr| {
                if (!std.ascii.isUpper(chr)) {
                    return;
                }

                self.advance();
            }
        }

        fn nextInteger(self: *Parser) Error!i64 {
            var x: i64 = 0;

            while (self.peek()) |c| {
                const digit = charToDigit(c) orelse break;
                self.advance();

                if (@mulWithOverflow(@TypeOf(x), x, 10, &x)) {
                    return Error.IntegerLiteralOverflow;
                }

                if (@addWithOverflow(@TypeOf(x), x, digit, &x)) {
                    return Error.IntegerLiteralOverflow;
                }
            }

            return x;
        }

        fn nextIdentifier(self: *Parser) ![]const u8 {
            const start = self.source;

            while (self.peek()) |c| {
                if (!std.ascii.isLower(c) and c != '_' and !std.ascii.isDigit(c)) {
                    break;
                }

                self.advance();
            }

            return start[0 .. start.len - self.source.len];
        }

        fn nextString(self: *Parser) Error![]const u8 {
            const quote = self.peekAdvance();
            const start = self.source;

            while (self.peekAdvance()) |c| {
                if (c == quote) {
                    break;
                }
            } else {
                return Error.StringDoesntEnd;
            }

            return start[0 .. start.len - self.source.len];
        }

        pub fn next(self: *Parser) Error!Token {
            self.stripWhitespaceAndComments();

            const chr = self.peek() orelse return Error.EndOfStream;

            switch (chr) {
                '0'...'9' => return Value{ .integer = try self.nextInteger() },
                'a'...'z', '_' => return Token{ .identifier = try self.nextIdentifier() },
                '\'', '\"' => return Token{ .string = try self.nextString() },
                'T', 'F' => {
                    self.stripKeyword();
                    return Token{ .boolean = chr == 'T' };
                },
                'N' => {
                    self.stripKeyword();
                    return Token{ .nil = {} };
                },
                else => return Error.UnknownTokenStart,
            }
        }
    };
}

// const expect = @import("std").testing.expect;

// test "next null" {
//     var parser = Parser{ .source = "#132#\nNULL1" };

//     try expect(.nil == try parser.next());
// }

// // test "next string" {
// //     var parser = Parser{ .source = "'abc\"'123" };

// //     // try expect(Token{ .string = "abc\"" } == try parser.next());
// // }
