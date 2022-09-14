//! The string type in Knight.
//!
//! Since strings are so commonly used in Knight, optimizing them is key for ensuring fast programs.
//! Currently, a few optimizations for its representation are in place:
//!
//! 1. Small string optimizations. For strings smaller than `max_embed_length`, a separate buffer
//!    is not needed: The data can be directly embedded within the struct itself.
//! 2. "Nofree" strings: For strings with contents known beforehand, "nofree" strings don't allocate
//!    an additional buffer for the contents, as well as doesn't free the string itself when the
//!    refcount reaches zero.
//! 3. Substrings: Since subslicing strings is such a common operation in Knight, substrings strings
//!    reuse the buffer of the parent string. (This is valid because strings are immutable.)
//!
//! Additionally, Strings are usually interned (via `Interner`). This allows for efficient lookups.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const String = @This();
const Integer = @import("value.zig").Integer;

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
    owned: []u8,

    /// A borrowed string references a subslice of another `String`'s data.
    substring: struct { data: []const u8, owner: *String },
},

/// An empty string.
pub var empty = String.noFree("");

/// Create a new `String` which will never be freed.
pub fn noFree(str: []const u8) String {
    return .{
        .refcount = undefined,
        .kind = .{ .nofree = str },
    };
}

/// Initializes a pre-allocated noFree `String` with `str`.
pub fn initNoFree(string: *String, str: []const u8) void {
    string.* = noFree(str);
}

/// Creates a new owned `String`.
pub fn owned(str: []u8) String {
    return .{
        .kind = .{ .owned = str },
    };
}

/// Initializes `string` with the owned `str`.
pub fn initOwned(string: *String, str: []u8) void {
    string.* = owned(str);
}

/// An issue that can occur whilst initializing.
pub const InitError = Allocator.Error;

/// Initializes a string, and copies the `str` over to it.
pub fn initBorrowed(string: *String, alloc: Allocator, str: []const u8) InitError!void {
    try string.init(alloc, str.len);
    std.mem.copy(u8, string.asMutableSlice(), str);
}

/// Initializes `string` as a String with enough space to store `capacity` bytes.
pub fn init(string: *String, alloc: Allocator, capacity: usize) InitError!void {
    string.refcount = 1;

    if (capacity <= max_embed_length) {
        string.kind = .{
            .embed = .{
                .len = @intCast(@TypeOf(string.kind.embed.len), capacity),
                .data = undefined,
            },
        };
    } else {
        string.kind = .{
            .owned = try alloc.alloc(u8, capacity),
        };
    }
}

/// The issue that could possibly occur when initializing a substring.
pub const InitSubstrError = error{OutOfBounds};

/// Initialize a borrowed substring.
pub fn initSubstr(string: *String, owner: *String, start: usize, length: usize) void {
    std.debug.print("len={}, start={}, length={}\n", .{ owner.len(), start, length });
    assert(start + length <= owner.len());

    owner.increment();

    string.kind = .{
        .substring = .{
            .data = owner.slice()[start .. start + length],
            .owner = owner,
        },
    };
}

/// Deinitializes `string`.
///
/// If `string` is a nofree string, then `alloc` is ignored, and nothing happens. Otherwise, the
/// refcount must be zero, owned strings are freed (and must have been allocated via `alloc`), and
/// substrings `.decrement()` the refcount of the owner. Lastly, all non-nofree strings are set to
/// `undefined`.
pub fn deinit(string: *String, alloc: Allocator) void {
    // For nofree strings, nothing is done.
    if (string.kind == .nofree) {
        return;
    }

    // For all non-nofree types, the refcount must be zero.
    assert(string.refcount == 0);

    switch (string.kind) {
        .nofree => unreachable, // Already checked before.
        .embed => {}, // Do nothing for embedded.
        .owned => |o| alloc.free(o), // Free the owned allocation.
        .substring => |b| b.owner.decrement(), // Decrement the owner's refcount, but don't deinit.
    }

    // Set the contents to undefined, so use-after-free bugs can be caught.
    string.* = undefined;
}

// Increments the refcount for non-`nofree` strings.
pub fn increment(string: *String) void {
    switch (string.kind) {
        // The refcount is irrelevant for nofree strings. This is important because we don't care
        // about wrapping.
        .nofree => string.refcount +%= 1,

        // Every other string is allocated, so we should have the debug assertion.
        else => string.refcount += 1,
    }
}

/// Decrement the refcount. Note that this won't free the string---that should be done via `deinit`.
pub fn decrement(string: *String) void {
    switch (string.kind) {
        // The refcount is irrelevant for nofree strings. This is important because we don't care
        // about wrapping.
        .nofree => string.refcount -%= 1,

        // Every other string is allocated, so we should have the debug assertion.
        else => string.refcount -= 1,
    }
}

/// Gets the length of the string, in bytes.
pub fn len(string: *const String) usize {
    return string.slice().len;
}

/// Returns `string` as a mutable slice.
///
/// This should only be called on owned and embedded strings, and only to perform the initial
/// initialization of the string. Using this on nofree or substrings is UB.
pub fn asMutableSlice(string: *String) []u8 {
    assert(string.refcount == 1);

    return switch (string.kind) {
        .embed => |*e| e.data[0..e.len],
        .owned => |o| o,
        .nofree, .substring => unreachable,
    };
}

/// Gets an immutable slice of the underlying data.
pub fn slice(string: *const String) []const u8 {
    return switch (string.kind) {
        .embed => |*e| e.data[0..e.len],
        .nofree => |n| n,
        .owned => |o| o,
        .substring => |b| b.data,
    };
}

/// Converts `string` to an Integer, as per the Knight spec.
///
/// In essence, convert capture group 1 to an int from regex `/^\s*([-+]?\d+)/`
pub fn parseInt(string: *const String) Integer {
    var str = string.slice();

    // Strip leading whitespace
    while (str.len != 0 and std.ascii.isSpace(str[0])) {
        str = str[1..];
    }

    // If it was only whitespace, we're done.
    if (str.len == 0) return 0;

    // Find the first non-digit character, sans leading `-` or `+`.
    var end = @as(usize, 0);
    if (str[0] == '-' or str[0] == '+') end = 1;
    while (end < str.len and std.ascii.isDigit(str[end])) : (end += 1) {}

    // Strip off the rest of non-ascii characters
    str.len = end;

    // Parse the string, or if there's an error, it's zero
    return std.fmt.parseInt(Integer, str, 10) catch 0;
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const testing_allocator = std.testing.allocator;

test "nofree strings" {
    // Ensure `.noFree` and decrement/deinit work
    var string = String.noFree("hello, world");
    defer {
        string.decrement();
        string.deinit(undefined);
    }
    try expectEqualStrings("hello, world", string.slice());

    // Ensure `initNoFree` and just a `deinit` works.
    var string2: String = undefined;
    string2.initNoFree("nofree string");
    defer string2.deinit(undefined);
    try expectEqualStrings("nofree string", string2.slice());

    // Ensrue that an empty string, and no `deinit` works.
    try expectEqualStrings("", String.noFree("").slice()); // ensure no deinit is needed.
}

test "owned strings" {
    // Test straight-up `owned`.
    var string = String.owned(try testing_allocator.dupe(u8, "owned string"));
    defer {
        string.decrement();
        string.deinit(testing_allocator);
    }
    try expectEqualStrings("owned string", string.slice());

    // Test `.initOwned`
    var string2: String = undefined;
    string2.initOwned(try testing_allocator.dupe(u8, "salutations, friend!"));
    defer {
        string2.decrement();
        string2.deinit(testing_allocator);
    }
    try expectEqualStrings("salutations, friend!", string2.slice());
    // TODO: mtuable slice
}

test "borrowed strings" {
    // Test `.initBorrowed`
    var string: String = undefined;
    try string.initBorrowed(testing_allocator, "greetings");
    defer {
        string.decrement();
        string.deinit(testing_allocator);
    }
    try expectEqualStrings("greetings", string.slice());

    // Test `.initBorrowed` with large strings
    var string2: String = undefined;
    try string2.initBorrowed(testing_allocator, "greetings" ** max_embed_length); // vastly larger
    defer {
        string2.decrement();
        string2.deinit(testing_allocator);
    }
    try expectEqualStrings("greetings" ** max_embed_length, string2.slice());
}

test "toInt conforms to spec" {
    try expectEqual(@as(Integer, 123), String.noFree("123").parseInt());
    try expectEqual(@as(Integer, 123), String.noFree("   \t\n\r123").parseInt());
    try expectEqual(@as(Integer, -123), String.noFree("   \t\n-123").parseInt());
    try expectEqual(@as(Integer, -123), String.noFree("-123").parseInt());
    try expectEqual(@as(Integer, 0), String.noFree("0").parseInt());
    try expectEqual(@as(Integer, 19), String.noFree("019").parseInt());

    try expectEqual(@as(Integer, 1), String.noFree("+1").parseInt());
    try expectEqual(@as(Integer, 0), String.noFree("+ 1").parseInt());
    try expectEqual(@as(Integer, 0), String.noFree("+").parseInt());
    try expectEqual(@as(Integer, 0), String.noFree("-").parseInt());
    try expectEqual(@as(Integer, 0), String.noFree("").parseInt());
    try expectEqual(@as(Integer, 0), String.noFree("+a").parseInt());
    try expectEqual(@as(Integer, 0), String.noFree("abc").parseInt());

    try expectEqual(@as(Integer, 123), String.noFree("123abc").parseInt());
    try expectEqual(@as(Integer, -123), String.noFree("\r\n\t \r-123abc").parseInt());
}

pub const Interner = struct {
    strings: std.StringHashMapUnmanaged(*String) = .{},

    // note that `s` should always be borrowed.
    pub fn fetch(interner: *Interner, alloc: Allocator, str: []const u8) Allocator.Error!*String {
        _ = interner; // TODO, check to see if it already exists.

        var string = try alloc.create(String);
        errdefer string.deinit(alloc);

        try string.initBorrowed(alloc, str);
        errdefer string.decrement();

        return string;
    }

    pub fn concat(
        interner: *Interner,
        alloc: Allocator,
        lhs: []const u8,
        rhs: []const u8,
    ) Allocator.Error!*String {
        _ = interner; // TODO, check to see if it already exists.

        var string = try alloc.create(String);
        errdefer string.deinit(alloc);

        try string.init(alloc, lhs.len + rhs.len);
        errdefer string.decrement();

        std.mem.copy(u8, string.asMutableSlice(), lhs);
        std.mem.copy(u8, string.asMutableSlice()[lhs.len..], rhs);

        return string;
    }

    pub fn repeat(
        interner: *Interner,
        alloc: Allocator,
        source: []const u8,
        amount: usize,
    ) Allocator.Error!*String {
        _ = interner; // TODO, check to see if it already exists.

        var string = try alloc.create(String);
        errdefer string.deinit(alloc);

        try string.init(alloc, source.len * amount);
        errdefer string.decrement();

        var i: usize = 0;
        while (i < amount) : (i += 1) {
            std.mem.copy(u8, string.asMutableSlice()[i * source.len ..], source);
        }

        return string;
    }

    pub fn register(interner: *Interner, alloc: Allocator, string: *String) bool {
        _ = interner;
        _ = alloc;
        _ = string;
        return false;
    }
};

pub const MaybeIntegerString = union(enum) {
    string: *String,
    integer: std.BoundedArray(u8, std.fmt.count("{d}", .{std.math.minInt(Integer)})),

    pub fn decrement(string: *const MaybeIntegerString) void {
        switch (string.*) {
            .string => |s| s.decrement(),
            else => {},
        }
    }

    pub fn toString(
        string: *const MaybeIntegerString,
        alloc: Allocator,
        interner: *Interner,
    ) !*String {
        return switch (string.*) {
            .string => |s| {
                s.increment();
                return s;
            },
            .integer => |b| interner.fetch(alloc, b.slice()),
        };
    }

    pub fn slice(string: *const MaybeIntegerString) []const u8 {
        return switch (string.*) {
            .string => |s| s.slice(),
            .integer => |*b| b.slice(),
        };
    }

    pub fn integerSlice(integer: Integer) MaybeIntegerString {
        var string = MaybeIntegerString{ .integer = .{} };
        string.integer.writer().print("{d}", .{integer}) catch unreachable;
        return string;
    }
};
