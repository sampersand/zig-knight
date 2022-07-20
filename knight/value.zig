const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const meta = std.meta;

const Error = @import("error.zig").Error;
const String = @import("String.zig");
const Environment = @import("Environment.zig");
const Variable = Environment.Variable;
const Block = @import("funcs.zig").Block;

/// An Integer within Knight. This is specially sized to make use of point tagging.
pub const Integer = meta.Int(.signed, @bitSizeOf(Value) - @bitSizeOf(Tag));

/// A Struct that indicates a null value within Knight.
pub const Null = struct {};

/// The alignment of pointers within Knight. This is used to ensure that all tagged pointers
/// are correctly aligned.
pub const ptr_align = 8;

/// The tag of a `Value`. Used to indicate the type of a value.
const Tag = enum {
    const tag_size = std.math.log2(ptr_align);
    const shift = tag_size;

    // The tags themselves
    constant,
    integer,
    variable,
    string,
    block,

    fn create(comptime tag: Tag, bits: meta.Tag(Value)) Value {
        assert(@truncate(meta.Tag(Tag), bits) == 0);

        return @intToEnum(Value, bits | @enumToInt(tag));
    }

    fn of(comptime T: type) Tag {
        return switch (T) {
            Integer => .integer,
            *String => .string,
            *Variable => .variable,
            *Block => .block,
            bool, Null => undefined, // These are always special-cased elsewhere.
            else => @compileError("non-Value type given: " ++ @typeName(T)),
        };
    }
};

/// The value type in Knight.
///
/// This is an `enum` because under Zig's current compiler (at the time of this project), structs
/// and unions are occasionally passed by-reference because the optimizer isn't smart enough yet.
/// However, `enum`s are always by-value, which is what we want.
///
/// The following are valid `Value` types; attempting to use others will yield a compiler error:
/// - `bool`
/// - `Null`
/// - `Integer`
/// - `*String`
/// - `*Variable`
/// - `*Block`
pub const Value = enum(u64) {
    /// Our only variant; indicates that `Value` can have variants other than those specified,
    /// which is required when tagging things.
    _,

    /// The false value within Knight.
    ///
    /// This isn't a variant of `Value` because `Tag` requires the size of `Value`, which would
    /// create a circular dependency. Instead, it's an associated constant.
    pub const @"false" = Tag.constant.create(0 << Tag.shift);

    /// The true value within Knight.
    ///
    /// This isn't a variant of `Value` because `Tag` requires the size of `Value`, which would
    /// create a circular dependency. Instead, it's an associated constant.
    pub const @"null" = Tag.constant.create(1 << Tag.shift);

    /// The null value within Knight.
    ///
    /// This isn't a variant of `Value` because `Tag` requires the size of `Value`, which would
    /// create a circular dependency. Instead, it's an associated constant.
    pub const @"true" = Tag.constant.create(2 << Tag.shift);

    /// Indicates the absence of a value in Knight.
    ///
    /// Instead of using `?Value`, instead you should use `Value.@"undefined"`, as it doesn't
    /// take up any extra space.
    ///
    /// This isn't a variant of `Value` because `Tag` requires the size of `Value`, which would
    /// create a circular dependency. Instead, it's an associated constant.
    pub const @"undefined" = Tag.constant.create(3 << Tag.shift);

    /// The number zero within Knight.
    ///
    /// This isn't a variant of `Value` because `Tag` requires the size of `Value`, which would
    /// create a circular dependency. Instead, it's an associated constant.
    pub const zero = Tag.integer.create(0 << Tag.shift);

    /// The number one within Knight.
    ///
    /// This isn't a variant of `Value` because `Tag` requires the size of `Value`, which would
    /// create a circular dependency. Instead, it's an associated constant.
    pub const one = Tag.integer.create(1 << Tag.shift);

    // pub const Category = union(enum) {
    //     @"null",
    //     boolean: bool,
    //     integer: Integer,
    //     string: *String,
    //     variable: *Variable,
    //     block: *Block,
    // }

    // pub fn categorize(value: Value) Category {
    //     return switch (value.tag()) {
    //         .constant => switch (value) {
    //             Value.@"true" => Category{.boolean = true},
    //             Value.@"false" => String.MaybeIntegerString{ .string = &strings.false_string },
    //             Value.@"null" => String.MaybeIntegerString{ .string = &strings.null_string },
    //             else => unreachable,
    //         },
    //         .integer => switch (value) {
    //             Value.zero => String.MaybeIntegerString{ .string = &strings.zero_string },
    //             Value.one => String.MaybeIntegerString{ .string = &strings.one_string },
    //             else => String.MaybeIntegerString.integerSlice(value.castUnchecked(Integer)),
    //         },
    //         .string => blk: {
    //             var string = value.castUnchecked(*String);
    //             string.increment();
    //             break :blk .{ .string = string };
    //         },
    //         else => Error.InvalidConversion,
    //     };
    // }

    fn bits(value: Value) meta.Tag(Value) {
        return @enumToInt(value);
    }

    fn untag(value: Value) meta.Tag(Value) {
        return value.bits() & ~@as(meta.Tag(Value), (1 << Tag.shift) - 1);
    }

    fn tag(value: Value) Tag {
        return @intToEnum(Tag, @truncate(meta.Tag(Tag), value.bits()));
    }

    pub fn isUndefined(value: Value) bool {
        return value == Value.@"undefined";
    }

    /// Creates a new `Value` of type `T`. (For a list of types, cf `Value` docs).
    pub fn init(comptime T: type, value: T) Value {
        const val_tag = comptime Tag.of(T);

        return switch (T) {
            bool => if (value) Value.@"true" else Value.@"false",
            Null => Value.@"null",
            Integer => val_tag.create(@as(
                meta.Tag(Value),
                @bitCast(meta.Int(.unsigned, @bitSizeOf(Value) - @bitSizeOf(Tag)), value),
            ) << Tag.shift),
            *String, *Variable, *Block => val_tag.create(@ptrToInt(value)),
            else => @compileError("non-Value type given: " ++ @typeName(T)),
        };
    }

    /// Checks to see whether `value` is a `T`.
    pub fn is(value: Value, comptime T: type) bool {
        return switch (T) {
            bool => value == Value.@"true" or value == Value.@"false",
            Null => value == Value.@"null",
            else => value.tag() == Tag.of(T),
        };
    }

    /// Unwraps a `value` of type `T`; if `value` isn't a `T`, an `InvalidCast` is returned.
    pub fn cast(value: Value, comptime T: type) error{InvalidCast}!T {
        return if (value.is(T)) value.castUnchecked(T) else error.InvalidCast;
    }

    /// Casts `value` to `T`, without validating that `value` is a `T`.
    pub fn castUnchecked(value: Value, comptime T: type) T {
        assert(value.is(T));

        return switch (T) {
            Integer => @intCast(
                Integer,
                @bitCast(meta.Int(.signed, @bitSizeOf(Value)), value.bits()) >> Tag.tag_size,
            ),
            bool => value == Value.@"true",
            Null => .{},
            *String, *Variable, *Block => @intToPtr(T, value.untag()),
            else => @compileError("non-Value type given: " ++ @typeName(T)),
        };
    }

    /// Increments the refcount of a `Value`. Only needed for `*String` and `*Block`s.
    pub fn increment(value: Value) void {
        assert(!value.isUndefined());

        switch (value.tag()) {
            .string => value.castUnchecked(*String).increment(),
            .block => value.castUnchecked(*Block).increment(),
            else => {},
        }
    }

    /// Decrements the refcount of a `Value`. Only needed for `*String` and `*Block`s.
    pub fn decrement(value: Value, alloc: Allocator) void {
        assert(!value.isUndefined());

        switch (value.tag()) {
            .string => value.castUnchecked(*String).decrement(),
            .block => value.castUnchecked(*Block).decrement(alloc),
            else => {},
        }
    }

    pub fn run(value: Value, env: *Environment) Error!Value {
        return switch (value.tag()) {
            .constant, .integer => value,
            .string => blk: {
                value.castUnchecked(*String).increment();
                break :blk value;
            },
            .variable => value.castUnchecked(*Variable).fetch(),
            .block => value.castUnchecked(*Block).run(env),
        };
    }

    /// Converts `value` to an `Integer`, as per the Knight spec. For types without a conversion
    /// defined, `InvalidConversion` is returned.
    pub fn toInt(value: Value) Error!Integer {
        assert(!value.isUndefined());

        return switch (value.tag()) {
            .constant => @boolToInt(value == Value.@"true"),
            .integer => value.castUnchecked(Integer),
            .string => value.castUnchecked(*String).parseInt(),
            else => Error.InvalidConversion,
        };
    }

    /// Converts `value` to an `bool`, as per the Knight spec. For types without a conversion
    /// defined, `InvalidConversion` is returned.
    pub fn toBool(value: Value) Error!bool {
        assert(!value.isUndefined());

        // OPTIMIZATION: You could just check to see if the value is `<= Value.zero.bits()`, or
        // if it's the empty string.
        return switch (value.tag()) {
            .constant => value == Value.@"true",
            .integer => value.castUnchecked(Integer) != 0,
            .string => value.castUnchecked(*String).len() != 0,
            else => Error.InvalidConversion,
        };
    }

    /// Converts `value` to an `*String`, as per the Knight spec. For types without a conversion
    /// defined, `InvalidConversion` is returned.
    pub fn toStr(value: Value) Error!String.MaybeIntegerString {
        assert(!value.isUndefined());

        const strings = struct {
            var true_string = String.noFree("true");
            var false_string = String.noFree("false");
            var null_string = String.noFree("null");
            var zero_string = String.noFree("0");
            var one_string = String.noFree("1");
        };

        return switch (value.tag()) {
            .constant => switch (value) {
                Value.@"true" => String.MaybeIntegerString{ .string = &strings.true_string },
                Value.@"false" => String.MaybeIntegerString{ .string = &strings.false_string },
                Value.@"null" => String.MaybeIntegerString{ .string = &strings.null_string },
                else => unreachable,
            },
            .integer => switch (value) {
                Value.zero => String.MaybeIntegerString{ .string = &strings.zero_string },
                Value.one => String.MaybeIntegerString{ .string = &strings.one_string },
                else => String.MaybeIntegerString.integerSlice(value.castUnchecked(Integer)),
            },
            .string => blk: {
                var string = value.castUnchecked(*String);
                string.increment();
                break :blk .{ .string = string };
            },
            else => Error.InvalidConversion,
        };
    }

    pub fn dump(value: Value, writer: anytype) !void {
        switch (value.tag()) {
            .constant => switch (value) {
                Value.@"true" => try writer.print("Boolean(true)", .{}),
                Value.@"false" => try writer.print("Boolean(false)", .{}),
                Value.@"null" => try writer.print("Null()", .{}),
                else => unreachable,
            },
            .integer => try writer.print("Integer({d})", .{value.castUnchecked(Integer)}),
            .string => try writer.print("String({s})", .{value.castUnchecked(*String).slice()}),
            .variable => try writer.print("Variable({s})", .{value.castUnchecked(*Variable).name}),
            .block => try writer.print("Block({c})", .{value.castUnchecked(*Block).func.name}),
        }
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;
const testing_allocator = std.testing.allocator;

test "bitmasking integer values" {
    const zero = Value.zero;
    try expect(zero.is(Integer));
    try expectEqual(@as(Integer, 0), try zero.cast(Integer));

    const thirty_four = Value.init(Integer, 34);
    try expect(thirty_four.is(Integer));
    try expectEqual(@as(Integer, 34), try thirty_four.cast(Integer));

    const negative_four_million_and_change = Value.init(Integer, -4_531_681);
    try expect(negative_four_million_and_change.is(Integer));
    try expectEqual(@as(Integer, -4_531_681), try negative_four_million_and_change.cast(Integer));

    try expect(!zero.is(bool));
    try expect(!zero.is(Null));
    try expect(!zero.is(*String));
    try expect(!zero.is(*Variable));
}

test "bitmasking boolean values" {
    const truth = Value.init(bool, true);
    try expect(truth.is(bool));
    try expectEqual(true, try truth.cast(bool));

    const falsehood = Value.init(bool, false);
    try expect(falsehood.is(bool));
    try expectEqual(false, try falsehood.cast(bool));

    try expect(!truth.is(Integer));
    try expect(!truth.is(Null));
    try expect(!truth.is(*String));
    try expect(!truth.is(*Variable));
}

test "bitmasking nul values" {
    const n = Value.init(Null, .{});
    try expect(n.is(Null));
    try expectEqual(Null{}, try n.cast(Null));

    try expect(!n.is(Integer));
    try expect(!n.is(bool));
    try expect(!n.is(*String));
    try expect(!n.is(*Variable));
}

test "bitmasking string values" {
    const greeting = "Hello, world!";
    const string = Value.init(*String, &String.noFree(greeting));
    try expect(string.is(*String));
    try std.testing.expectEqualStrings(greeting, (try string.cast(*String)).slice());

    try expect(!string.is(Integer));
    try expect(!string.is(bool));
    try expect(!string.is(Null));
    try expect(!string.is(*Variable));
}

test "increment/decrement strings" {
    var s = String.owned(try testing_allocator.dupe(u8, "Hello, world!"));
    const string = Value.init(*String, &s);

    try expectEqual(@as(usize, 1), s.refcount);
    string.increment();
    try expectEqual(@as(usize, 2), s.refcount);
    string.decrement(undefined);
    try expectEqual(@as(usize, 1), s.refcount);
    string.decrement(undefined);

    s.deinit(testing_allocator);
}

test "increment/decrement blocks" {
    var b = Block{ .func = undefined, .args = undefined };
    const block = Value.init(*Block, &b);

    try expectEqual(@as(usize, 1), b.refcount);
    block.increment();
    try expectEqual(@as(usize, 2), b.refcount);
    block.decrement(undefined);
    try expectEqual(@as(usize, 1), b.refcount);
}

test "to int conversions" {
    try expectEqual(@as(Integer, 0), try Value.zero.toInt());
    try expectEqual(@as(Integer, 1), try Value.one.toInt());
    try expectEqual(@as(Integer, 34), try Value.init(Integer, 34).toInt());
    try expectEqual(@as(Integer, -4_531_681), try Value.init(Integer, -4_531_681).toInt());

    try expectEqual(@as(Integer, 1), try Value.@"true".toInt());
    try expectEqual(@as(Integer, 0), try Value.@"false".toInt());
    try expectEqual(@as(Integer, 0), try Value.@"null".toInt());

    // TODO: test strings

    var env = Environment.init(testing_allocator);
    defer env.deinit();
    try expectError(
        Error.InvalidConversion,
        Value.init(*Variable, try env.fetch(.Borrowed, "foo")).toInt(),
    );
    var blk = Block{ .func = undefined, .args = undefined };
    try expectError(Error.InvalidConversion, Value.init(*Block, &blk).toInt());
}

test "to bool conversions" {
    try expectEqual(false, try Value.zero.toBool());
    try expectEqual(true, try Value.one.toBool());
    try expectEqual(true, try Value.init(Integer, 34).toBool());
    try expectEqual(true, try Value.init(Integer, -4_531_681).toBool());

    try expectEqual(true, try Value.@"true".toBool());
    try expectEqual(false, try Value.@"false".toBool());
    try expectEqual(false, try Value.@"null".toBool());

    try expectEqual(false, try Value.init(*String, &String.noFree("")).toBool());
    try expectEqual(true, try Value.init(*String, &String.noFree("0")).toBool());
    try expectEqual(true, try Value.init(*String, &String.noFree("false")).toBool());
    try expectEqual(true, try Value.init(*String, &String.noFree(" ")).toBool());
    try expectEqual(true, try Value.init(*String, &String.noFree("foo bar")).toBool());

    var env = Environment.init(testing_allocator);
    defer env.deinit();
    try expectError(
        Error.InvalidConversion,
        Value.init(*Variable, try env.fetch(.Borrowed, "foo")).toBool(),
    );

    var blk = Block{ .func = undefined, .args = undefined };
    try expectError(Error.InvalidConversion, Value.init(*Block, &blk).toBool());
}

test "to string conversions" {
    const min_int = std.math.minInt(Integer);
    const max_int = std.math.maxInt(Integer);
    try expectEqualStrings("0", (try Value.zero.toStr()).slice());
    try expectEqualStrings("1", (try Value.one.toStr()).slice());
    try expectEqualStrings("34", (try Value.init(Integer, 34).toStr()).slice());
    try expectEqualStrings("-4531681", (try Value.init(Integer, -4_531_681).toStr()).slice());
    try expectEqualStrings(
        std.fmt.comptimePrint("{d}", .{min_int}),
        (try Value.init(Integer, min_int).toStr()).slice(),
    );
    try expectEqualStrings(
        std.fmt.comptimePrint("{d}", .{max_int}),
        (try Value.init(Integer, max_int).toStr()).slice(),
    );

    try expectEqualStrings("true", (try Value.@"true".toStr()).slice());
    try expectEqualStrings("false", (try Value.@"false".toStr()).slice());
    try expectEqualStrings("null", (try Value.@"null".toStr()).slice());

    try expectEqualStrings("", (try Value.init(*String, &String.noFree("")).toStr()).slice());
    try expectEqualStrings("0", (try Value.init(*String, &String.noFree("0")).toStr()).slice());
    try expectEqualStrings("false", (try Value.init(*String, &String.noFree("false")).toStr()).slice());
    try expectEqualStrings(" ", (try Value.init(*String, &String.noFree(" ")).toStr()).slice());
    try expectEqualStrings("foo bar", (try Value.init(*String, &String.noFree("foo bar")).toStr()).slice());

    var env = Environment.init(testing_allocator);
    defer env.deinit();
    try expectError(
        Error.InvalidConversion,
        Value.init(*Variable, try env.fetch(.Borrowed, "foo")).toStr(),
    );
    var blk = Block{ .func = undefined, .args = undefined };
    try expectError(Error.InvalidConversion, Value.init(*Block, &blk).toStr());

    // make sure it increases the refcount
    var s = String.owned(try testing_allocator.dupe(u8, "Hello, world!"));
    try expectEqual(@as(usize, 1), s.refcount);
    try expectEqualStrings("Hello, world!", (try Value.init(*String, &s).toStr()).slice());
    try expectEqual(@as(usize, 2), s.refcount);

    s.decrement();
    s.decrement();
    s.deinit(testing_allocator);
}
