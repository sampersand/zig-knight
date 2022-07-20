const std = @import("std");
const Value = @import("value.zig").Value;
const Error = @import("error.zig").Error;

pub const max_arity: usize = 4;

pub const Function = struct {
    func: fn ([*]Value) Error!Value,
    arity: u2, // Max arity is four
    name: u8,
};

pub const Block = struct {
    refcount: usize = 1,
    func: *const Function,
    args: [max_arity]Value,

    pub fn increment(block: *Block) void {
        block.refcount += 1;
    }

    pub fn decrement(block: *Block, alloc: std.mem.Allocator) void {
        block.refcount -= 1;
        _ = alloc;
    }
};

test "value can create a block" {
    // const b = Block{ .func = undefined, .args = undefined };
    // const v = Value{ .block = b };

    // switch (v) {
    //     .block => {},
    //     else => failure(),
    // }
}
