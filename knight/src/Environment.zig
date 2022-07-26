//! The current runtime environment within Knight.
//!
//! All Knight programs must execute with a certain context---mainly what variables are defined, but
//! also things like stdin/stdout handles---which must be passed around to all functions.
//!
//! Additionally, to improve performance, all strings are interned, which can be used for improved
//! variable lookup.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;

const Environment = @This();

/// A variable within Knight; each unique identifier has a `Variable` associated with it.
///
/// These are created via `Environment.fetch`, and are valid until `Environment.deinit` is called,
/// at which time all `Variable`s derived from that environment become invalid.
pub const Variable = struct {
    /// The name of the variable. This value is merely borrowed; `Environment.variables` owns it.
    name: []const u8,

    /// The value of the `Variable`. You shouldn't directly access this; instead, use `.assign` and
    /// `.fetch`.
    value: ?Value = null,

    /// Associates `value` with `variable`, deinitializing the previous value (if any).
    pub fn assign(variable: *Variable, alloc: Allocator, value: Value) void {
        variable.deinit(alloc);
        variable.value = value;
    }

    /// Access the last `Value` that was `.assign`ed to `variable`, returning `null` if the variable
    /// hasn't been assigned yet.
    pub fn fetch(variable: *const Variable) ?Value {
        const value = variable.value orelse return null;
        value.increment();
        return value;
    }

    fn deinit(variable: *Variable, alloc: Allocator) void {
        if (variable.value) |value| {
            value.decrement(alloc);
        }
    }
};

/// The variables for the environment. Note that it's a pointer to a `Variable`, and not a
/// variable directly, as pointers to variables are needed for `Value`, and resizing `variables`
/// when new values are added may invalidate old pointers.
variables: std.StringHashMapUnmanaged(*Variable) = .{},

/// A string interner, used to keep track of the allocated `String`s for the environment.
interner: @import("String.zig").Interner = .{},

/// The allocator for the environment.
allocator: Allocator,

/// A random number generator, used for the `RANDOM` functoin.
random: std.rand.DefaultPrng,

/// The error that `.init` can return.
pub const InitError = std.os.GetRandomError;

/// Creates a new `Environment` with the given allocator.
pub fn init(allocator: Allocator) InitError!Environment {
    var bytes: [@sizeOf(u64)]u8 = undefined;
    try std.os.getrandom(&bytes);

    return Environment{
        .allocator = allocator,
        .random = std.rand.DefaultPrng.init(std.mem.readIntNative(u64, &bytes)),
    };
}

/// The error that `.lookup` can return.
pub const LookupError = Allocator.Error;

/// Fetches the variable identified by `name`; If no such variable exists, one will be created.
/// Note that `name` must be a borrowed slice.
pub fn lookup(env: *Environment, name: []const u8) LookupError!*Variable {
    var entry = try env.variables.getOrPut(env.allocator, name);

    if (!entry.found_existing) {
        entry.key_ptr.* = try env.allocator.dupe(u8, name);
        entry.value_ptr.* = try env.allocator.create(Variable);
        entry.value_ptr.*.* = .{ .name = entry.key_ptr.* };
    }

    return entry.value_ptr.*;
}

/// Deinitializes `env`, freeing all memory associated with it and invalidating all `Variables`
/// derived from it.
pub fn deinit(env: *Environment) void {
    var iter = env.variables.iterator();

    while (iter.next()) |entry| {
        // Deinitialize the variable, which will free any value assigned to it.
        entry.value_ptr.*.deinit(env.allocator);

        // We heap allocated the variable, so we must destroy it.
        env.allocator.destroy(entry.value_ptr.*);

        // We own the variable names, so we need to free those.
        env.allocator.free(entry.key_ptr.*);
    }

    // Finally, deinitialize all the variables
    env.variables.deinit(env.allocator);
}

test "variable fetching works" {
    const expect = std.testing.expect;
    const expectEqualStrings = std.testing.expectEqualStrings;
    const expectError = std.testing.expectError;
    const expectEqual = std.testing.expectEqual;

    var env = Environment.init(std.testing.allocator);

    const v1 = try env.lookup("hello");
    try expectEqualStrings(v1.name, "hello");
    try expectError(null, v1.fetch());

    const v2 = try env.lookup("world");
    try expectEqualStrings(v2.name, "world");
    try expectError(null, v2.fetch());
    try expect(v1 != v2);

    const v3 = try env.lookup("hello");
    try expectEqual(v1, v3);
    try expectEqualStrings(v1.name, "hello");
    try expectError(null, v1.fetch());

    v1.assign(env.allocator, Value.@"true");
    try expectEqualStrings(v1.name, "hello");
    try expectEqual(try v1.fetch(), Value.@"true");
    try expectError(null, v2.fetch());

    const Integer = @import("value.zig").Integer;
    (try env.lookup("world")).assign(env.allocator, Value.init(Integer, 34));
    try expectEqualStrings(v2.name, "world");
    try expectEqual(try v1.fetch(), Value.@"true");
    try expectEqual(try v2.fetch(), Value.init(Integer, 34));

    env.deinit();
}
