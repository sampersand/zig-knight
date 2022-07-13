const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;
const Error = @import("error.zig").Error;

/// A variable within Knight; each unique identifier has a `Variable` associated with it.
///
/// These are created via `Environment.fetch`, and are valid until `Environment.deinit` is called,
/// at which time all `Variable`s derived from that environment become invalid.
pub const Variable = struct {
    /// The name of the variable. This value is merely borrowed; `Environment.variables` owns it.
    name: []const u8,
    /// The value of the `Variable`. You shouldn't directly access this, instead replace it with
    /// `Variable.assign` and access it with `Variable.fetch`.
    value: ?Value,

    /// Associates `value` with `variable`, deinitializing the previous value (if any).
    pub fn assign(variable: *Variable, allocator: Allocator, value: Value) void {
        variable.deinit(allocator);
        variable.value = value;
    }

    /// Access the last `Value` that was `.assign`ed to `variable`, returning an `Error` if
    /// `variable` has yet to be assigned.
    pub fn fetch(variable: *const Variable) Error!Value {
        return (variable.value orelse return Error.UndefinedVariable).clone();
    }

    fn deinit(variable: *Variable, allocator: Allocator) void {
        if (variable.value) |old| {
            old.free(allocator);
        }
    }
};

pub const Environment = @This();

// The variables for the environment. Note that it's a pointer to a `Variable`, and not a
// variable directly, as pointers to variables are needed for `Value`, and resizing `variables`
// when new values are added may invalidate old pointers.
variables: std.StringHashMapUnmanaged(*Variable),
allocator: Allocator, // NB. It's separate in case I add a string interner in the future.

/// Creates a new `Environment` with the given allocator.
pub fn init(allocator: Allocator) Environment {
    return .{ .variables = .{}, .allocator = allocator };
}

const FetchOwnership = enum { Owned, Borrowed };
/// Fetches the variable identified by `name`; If no such variable exists, one will be created.
///
/// Note that `name` can either be a borrowed slice (in which case, it will be duplicated if a new
/// variable needs to be created), or an owned slice. If it's `.Owned`, it must be allocated with
/// the `env.allocator` allocator.
pub fn fetch(
    env: *Environment,
    comptime owned: FetchOwnership,
    name: []const u8,
) Allocator.Error!*Variable {
    var entry = try env.variables.getOrPut(env.allocator, name);

    if (!entry.found_existing) {
        // If we don't own `name`, we need to duplicate it so we have an owned version.
        if (owned == .Borrowed) {
            entry.key_ptr.* = try env.allocator.dupe(u8, name);
        }
        entry.value_ptr.* = try env.allocator.create(Variable);
        entry.value_ptr.*.* = .{ .name = entry.key_ptr.*, .value = null };
    } else if (owned == .Owned) {
        // If a variable with `name` already existed, then we need to get rid of the owned name.
        env.allocator.free(name);
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

    const v1 = try env.fetch(.Borrowed, "hello");
    try expectEqualStrings(v1.name, "hello");
    try expectError(Error.UndefinedVariable, v1.fetch());

    const v2 = try env.fetch(.Borrowed, "world");
    try expectEqualStrings(v2.name, "world");
    try expectError(Error.UndefinedVariable, v2.fetch());
    try expect(v1 != v2);

    const v3 = try env.fetch(.Borrowed, "hello");
    try expectEqual(v1, v3);
    try expectEqualStrings(v1.name, "hello");
    try expectError(Error.UndefinedVariable, v1.fetch());

    v1.assign(env.allocator, .{ .boolean = true });
    try expectEqualStrings(v1.name, "hello");
    try expectEqual(try v1.fetch(), .{ .boolean = true });
    try expectError(Error.UndefinedVariable, v2.fetch());

    (try env.fetch(.Borrowed, "world")).assign(env.allocator, .{ .integer = 34 });
    try expectEqualStrings(v2.name, "world");
    try expectEqual(try v1.fetch(), .{ .boolean = true });
    try expectEqual(try v2.fetch(), .{ .integer = 34 });

    env.deinit();
}
