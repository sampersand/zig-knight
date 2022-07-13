const std = @import("std");
const Error = @import("error.zig").Error;
const String = @import("string.zig");
const env = @import("env.zig");
const Allocator = std.mem.Allocator;
const funcs = @import("funcs.zig");
const assert = std.debug.assert;

pub const Integer = i64;

pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: Integer,
    variable: *env.Variable,
    string: *String,
    block: *funcs.Block,

    pub fn clone(value: Value) Value {
        switch (value) {
            .string => |string| string.increment(),
            // .block => |block| block.increment(),
            else => {},
        }

        return value;
    }

    pub fn free(value: Value, alloc: Allocator) void {
        _ = alloc;
        switch (value) {
            .string => |string| string.decrement(),
            // .block => |block| block.decrement(),
            else => {},
        }
    }

    pub fn eql(self: Value, rhs: Value) bool {
        _ = self;
        _ = rhs;
    }
};

test "make a string value" {
    // const test_allocator = std.testing.allocator;

    // const value = Value(test_allocator).a;

    // _ = value;
}
