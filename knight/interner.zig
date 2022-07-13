const std = @import("std");
const String = @import("string.zig");
const Interner = @This();
const Allocator = std.mem.Allocator;

strings: std.StringHashMapUnmanaged(String),

pub fn init(i: *Interner) void {
    i.strings = std.StringHashMapUnmanaged(String);
}

pub fn fetch(i: *Interner, s: []const u8) *String {
    _ = s;
    _ = i;
    return 1;
}
