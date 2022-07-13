const constant: i32 = 5; // signed 32-bit constant
var variable: u32 = 5000; // unsigned 32-bit variable

// @as performs an explicit type coercion
const inferred_constant = @as(i32, 5);
var inferred_variable = @as(u32, 5000);

const std = @import("std");
const a: [5]u8 = [5]u8{ 'h', 'e', 'l', 'l', 'o' };
const b = [_]u8{ 'w', 'o', 'r', 'l', 'd' };

pub fn main() void {
    std.debug.print("Hello, {s}!\n", .{"World"});
    std.debug.print("a is, {s}!\n", .{a});
}
