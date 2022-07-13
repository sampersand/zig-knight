const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

/// The string type in Knight.
///
/// Since strings are so commonly used in Knight, optimizing them is key for ensuring fast programs.
/// Currently, a few optimizations for its representation are in place:
///
/// 1. Small string optimizations. For strings smaller than `max_embed_length`, a separate buffer
///    is not needed: The data can be directly embedded within the struct itself.
/// 2. "Nofree" strings: For strings with contents known beforehand, "nofree" strings don't allocate
///    an additional buffer for the contents, as well as doesn't free the string itself when the
///    refcount reaches zero.
/// 3. Substrings: Since subslicing strings is such a common operation in Knight, substrings strings
///    reuse the buffer of the parent string. (This is valid because strings are immutable.)
///
/// Additionally, Strings are usually interned (via `Interner`). This allows for efficient lookups.
pub const String = @This();

/// The maximum length of an embedded string. It's calculated by using the longest variant
/// of `kind`'s size, and subtracting the `embed.len` field's length..
pub const max_embed_length = @sizeOf([]const u8) + @sizeOf(*String) - @sizeOf(u5);

/// How many references to the string exist. When it hits zero, the string is deallocated
refcount: usize = 1,
/// The kind of string. Doing it this way improves performance for smaller strings and substring
/// extraction.
kind: union(enum) {
    /// Small strings (ie of size `<= max_embed_length`).
    embed: struct { len: u5, data: [max_embed_length]u8 },

    /// Strings that come from an allocation that we shouldn't free, e.g. string literals. This will
    /// also not free the `String` itself when refcount reaches zero.
    nofree: []const u8,

    /// An owned buffer. Its length should be larger than `max_embed_length`; smaller strings
    /// should be embedded.
    owned: []const u8,

    /// A borrowed string references a subslice of another `String`'s data.
    substring: struct { data: []const u8, owner: *String },
},

/// An empty string.
const empty = (String{}).nofree("");

pub fn initNoFree(str: *String, slice: []const u8) void {
    str.* = .{ .kind = .{ .nofree = slice } };
}

/// Creates a new owned string.
pub fn initOwned(str: *String, slice: []const u8) void {
    str.* = .{ .kind = .{ .owned = slice } };
}

pub fn initBorrowed(str: *String, alloc: Allocator, slice: []const u8) void {
    str.init(alloc, slice.len);
    std.mem.copy(u8, str.asMutableSlice(), slice);
}

pub fn init(str: *String, alloc: Allocator, capacity: usize) !void {
    str.refcount = 1;

    if (capacity <= max_embed_length) {
        str.kind = .{ .embed = undefined };
    } else {
        str.kind = .{ .owned = try alloc.alloc(u8, capacity) };
    }
}

pub fn deinit(str: *String, alloc: Allocator) void {
    assert(str.refcount == 0);

    switch (str.kind) {
        // We don't do anything with embedded and nofree strings.
        .embed, .nofree => {},

        // We have to free the allocation for owned strings.
        .owned => |o| alloc.free(o),

        // For substrings strings, we decrement the refcount for the owner.
        // TODO: should this also call `.deinit` on `b.owner`?
        .substring => |b| b.owner.decrement(),
    }

    str.* = undefined;
}

pub fn increment(str: *String) void {
    switch (str.kind) {
        // The refcount is irrelevant about nofree strings, so we just don't care about wrapping.
        .nofree => str.refcount +%= 1,

        // Every other string is allocated, so we should have the debug assertion.
        else => str.refcount += 1,
    }
}

/// Decrement the refcount. Note that this won't free the string---that should be done via `deinit`.
pub fn decrement(str: *String) void {
    switch (str.kind) {
        // The refcount is irrelevant about nofree strings, so we just don't care about wrapping.
        .nofree => str.refcount -%= 1,

        // Every other string is allocated, so we should have the debug assertion.
        else => str.refcount -= 1,
    }
}

pub fn len(str: *const String) usize {
    return str.asSlice().len;
}

pub fn asMutableSlice(str: *String) []u8 {
    assert(str.refcount == 1);

    return switch (str.kind) {
        .embed => |e| e.data[0..e.len],
        .owned => |o| o,
        .nofree, .substring => unreachable,
    };
}

pub fn asSlice(str: *const String) []const u8 {
    return switch (str.kind) {
        .embed => |e| e.data[0..e.len],
        .nofree => |n| n,
        .owned => |o| o,
        .substring => |b| b.data,
    };
}

// // Get a reference to the original owner. Either `b.owner` for substring strings, else `str`.
// fn ownerString(s: *String) *String {
//     return switch (s) {
//         .substring => |b| b.owner,
//         else => s,
//     };
// }

// /// Creates a new "borrowed" string from `str` from the specified range.
// /// This will return `null` if the last byte is out of bounds.
// pub fn substr(str: *String, i: Interner, start: usize, amnt: usize) ?*String {
//     // TODO: this function doesnt actually work, and needs some refrence to the interner.
//     if (amnt == 0 or str.len() == 0 or str.len() == start) {
//         return empty; // If we have an empty string, dont allocate a whole new string.
//     }

//     if (str.len <= start + amnt) {
//         return null;
//     }

//     str.increment();

//     return String{ .kind = .{
//         .borrowed = .{
//             .slice = str.asSlice()[start .. start + amnt],
//             .owner = str,
//         },
//     } };
// }

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "lengths transfers over" {
    //     try expect(String.initPtr(.Static, "foo").len() == 3);
    //     try expect(String.initPtr(.Static, "").len() == 0);
    // }

    // test "isEqual" {
    //     const str = String.initPtr(.Static, "Hello, world!");
    //     try expectEqualStrings(str.asSlice(), "Hello, world!");
}

// // Pass an owned `str` into this function.
// fn doStuff(str: *String, alloc: Allocator) *String {
//     var subs = test_allocator.create(String);
//     subs.* = str.substr(0, 50); // get the first 50 characters.

//     // We were passed an owned `str`, but we no longer need ownership of it.
//     // However, `str.substr` incremenets the refcount, and `subs` has a reference, so this wont
//     // deallocate `str`.
//     str.decrement(alloc);

//     // Contrived example, but let's say if the first character is an `'x'`, we return an empty
//     // string instead.
//     if (subs.asSlice()[0] == 'x') {
//         subs.decrement(alloc);
//         return String.empty;
//     } else {
//         return subs;
//     }
// }

test "doit" {
    // const alloc = std.testing.allocator;

    // // const slice: [100]const u8 = [];// allocate and initialize a slice.

    // var str = alloc.create(String);
    // str.* = String.ownedSlice(slice); // pass ownership of `slice` to `str`.

    // const substrOrEmpty = doStuff(str, alloc);
    // // ...do stuff with `substrOrEmpty`...

    // We have no way of knowing if, when this function returns, we need to free `str` or not.
    // If the first character was `x`, then we should, but if it wasnt, we should not. But the
    // kind system doesnt specify that.
}
