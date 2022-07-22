const std = @import("std");
const value = @import("value.zig");
const Value = value.Value;
const Integer = value.Integer;
const Error = @import("error.zig").Error;
const Environment = @import("Environment.zig");
const String = @import("String.zig");

const Function = @This();
pub const max_arity: usize = 4;
comptime {
    std.debug.assert(max_arity == function_S.arity);
}

name: u8,
arity: std.math.IntFittingRange(0, max_arity),
function: fn ([*]const Value, *Environment) Error!Value,

// fn run(comptime arity: usize, args: [*]const Value, env: *Environment) Error![arity]Value {
//     var ran: [arity]Value = undefined;

//     var i: usize = 0;
//     inline while (i < arity) : (i += 1) {
//         ran[i] = try args[i].run(env);
//         errdefer ran[i].decrement(env.allocator);
//     }

//     return ran;
// }

// fn decrement(comptime arity: usize, ran: [*]const Value, allocator: std.memAllocator) void {
//     var i: usize = 0;

//     inline while (i < arity) : (i += 1) {
//         ran[i].decrement(allocator);
//     }
// }

const function_P = Function{
    .name = 'P',
    .arity = 0,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_R = Function{
    .name = 'R',
    .arity = 0,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_E = Function{
    .name = 'E',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_B = Function{
    .name = 'B',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, _: *Environment) Error!Value {
            args[0].increment();

            return args[0];
        }
    }.fun,
};

const function_C = Function{
    .name = 'C',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const first_run = try args[0].run(env);
            defer first_run.decrement(env.allocator);

            return first_run.run(env);
        }
    }.fun,
};

const @"function_`" = Function{
    .name = '`',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_Q = Function{
    .name = 'Q',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const code_integer = try args[0].runToInt(env);
            const code = std.math.cast(u8, code_integer) orelse return error.DomainError;
            std.os.exit(code);
        }
    }.fun,
};

const @"function_!" = Function{
    .name = '!',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            return Value.init(bool, !try args[0].runToBool(env));
        }
    }.fun,
};

const function_L = Function{
    .name = 'L',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const ran = try args[0].run(env);
            defer ran.decrement(env.allocator);

            const str = try ran.toStr();

            return Value.init(Integer, @intCast(Integer, str.slice().len));
        }
    }.fun,
};

const function_D = Function{
    .name = 'D',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const ran = try args[0].run(env);
            errdefer ran.decrement(env.allocator);

            try ran.dump(std.io.getStdOut().writer());
            return ran;
        }
    }.fun,
};

const function_O = Function{
    .name = 'O',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const ran = try args[0].run(env);
            defer ran.decrement(env.allocator);

            const str = try ran.toStr();
            const slice = str.slice();

            var stdout_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
            const stdout = stdout_buffer.writer();

            if (slice.len == 0 or slice[slice.len - 1] != '\\') {
                try stdout.writeAll(slice);
                try stdout.writeAll("\n");
            } else {
                try stdout.writeAll(slice[0 .. slice.len - 2]);
            }

            try stdout_buffer.flush();

            return Value.@"null";
        }
    }.fun,
};

const function_A = Function{
    .name = 'A',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            var ran = try args[0].run(env);

            if (ran.cast(Integer)) |int| {
                if (std.math.cast(u8, int)) |val| {
                    const str = try env.interner.fetch(env.allocator, @as(*const [1]u8, &val));
                    return Value.init(*String, str);
                }

                return error.NotAnAsciiInteger;
            }

            if (ran.cast(*String)) |string| {
                defer string.decrement();
                const str = string.slice();
                return if (str.len == 0) error.EmptyString else Value.init(Integer, str.ptr[0]);
            }

            ran.decrement(env.allocator);
            return error.InvalidType;
        }
    }.fun,
};

fn enumFieldNameFor(comptime T: type) []const u8 {
    return switch (T) {
        Integer => "integer",
        bool => "bool",
        value.Null => "null",
        *String => "string",
        else => @compileError("invalid type:" ++ @typeName(T)),
    };
}

fn Allowed(comptime allowed: anytype) type {
    const ArgsType = @TypeOf(allowed);

    if (@typeInfo(ArgsType) != .Struct) {
        @compileError("Expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    return @Type(.{ .Union = .{
        .layout = .Auto,
        .tag_type = @Type(.{ .Enum = .{
            .layout = .Auto,
            .tag_type = std.math.IntFittingRange(0, allowed.len),
            .fields = comptime blk: {
                var fields: [allowed.len]std.builtin.Type.EnumField = undefined;
                inline for (allowed) |ty, idx| {
                    fields[idx] = .{ .name = enumFieldNameFor(ty), .value = idx };
                }
                break :blk fields[0..];
            },
            .decls = &.{},
            .is_exhaustive = true,
        } }),
        .fields = comptime blk: {
            var fields: [allowed.len]std.builtin.Type.UnionField = undefined;
            inline for (allowed) |_, idx| {
                fields[idx] = .{
                    .name = enumFieldNameFor(allowed[idx]),
                    .field_type = allowed[idx],
                    .alignment = 0,
                };
            }

            break :blk fields[0..];
        },
        .decls = &.{},
    } });
}

fn cast(
    val: Value,
    env: *Environment,
    comptime allowed: anytype,
) !Allowed(allowed) {
    const ran = try val.run(env);

    inline for (allowed) |info| {
        if (ran.cast(info)) |_| {
            var x: Allowed(allowed) = undefined;
            @field(x, "integer") = undefined;
            return x;
        }
    }

    ran.decrement(env.allocator);
    return error.InvalidType;
}

const @"function_+" = Function{
    .name = '+',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            switch (try cast(args[0], env, .{Integer})) {
                .integer => |int| {
                    return Value.init(Integer, int + try args[1].runToInt(env));
                },
            }
            // switch (try cast(args[0], env, .{ Integer, *String })) {
            //     .integer => |int| {
            //         return Value.init(Integer, int + try args[1].runToInt(env));
            //     },
            //     .string => {
            //         std.debug.todo("todo");
            //     },
            // }
        }
    }.fun,
};

const @"function_-" = Function{
    .name = '-',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const ran = try args[0].run(env);
            _ = ran;

            // switch (try cast(.{ Integer, String }, args[0], env)) {
            //     .integer => |int| {},
            //     .string => |str| {},
            // }

            // if (ran.cast(Integer)) |int| {
            //     return Value.init(Integer, int + try args[1].runToInt(env));
            // }

            // if (ran.cast(*String)) |_| {
            //     std.debug.todo("todo");
            // }

            // ran.decrement(env.allocator);
            // return error.InvalidType;
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_*" = Function{
    .name = '*',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_/" = Function{
    .name = '/',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_%" = Function{
    .name = '%',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_^" = Function{
    .name = '^',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_<" = Function{
    .name = '<',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_>" = Function{
    .name = '>',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_?" = Function{
    .name = '?',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_&" = Function{
    .name = '&',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_|" = Function{
    .name = '|',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_;" = Function{
    .name = ';',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_W = Function{
    .name = 'W',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const @"function_=" = Function{
    .name = '=',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_I = Function{
    .name = 'I',
    .arity = 3,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_G = Function{
    .name = 'G',
    .arity = 3,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

const function_S = Function{
    .name = 'S',
    .arity = 4,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            _ = args;
            _ = env;
            std.debug.todo("todo");
        }
    }.fun,
};

pub fn fetch(name: u8) ?*const Function {
    return switch (name) {
        function_P.name => &function_P,
        function_R.name => &function_R,
        function_E.name => &function_E,
        function_B.name => &function_B,
        function_C.name => &function_C,
        @"function_`".name => &@"function_`",
        function_Q.name => &function_Q,
        @"function_!".name => &@"function_!",
        function_L.name => &function_L,
        function_D.name => &function_D,
        function_O.name => &function_O,
        function_A.name => &function_A,
        @"function_+".name => &@"function_+",
        @"function_-".name => &@"function_-",
        @"function_*".name => &@"function_*",
        @"function_/".name => &@"function_/",
        @"function_%".name => &@"function_%",
        @"function_^".name => &@"function_^",
        @"function_<".name => &@"function_<",
        @"function_>".name => &@"function_>",
        @"function_?".name => &@"function_?",
        @"function_&".name => &@"function_&",
        @"function_|".name => &@"function_|",
        @"function_;".name => &@"function_;",
        function_W.name => &function_W,
        @"function_=".name => &@"function_=",
        function_I.name => &function_I,
        function_G.name => &function_G,
        function_S.name => &function_S,
        else => null,
    };
}

pub const Block = struct {
    refcount: usize = 1,
    function: *const Function,
    args: [max_arity]Value,

    pub fn run(block: *const Block, env: *Environment) Error!Value {
        return (block.function.function)(&block.args, env);
    }

    pub fn increment(block: *Block) void {
        block.refcount += 1;
    }

    pub fn decrement(block: *Block, alloc: std.mem.Allocator) void {
        block.refcount -= 1;
        _ = alloc;
    }
};

test "value can create a block" {
    // const b = Block{ .function = undefined, .args = undefined };
    // const v = Value{ .block = b };

    // switch (v) {
    //     .block => {},
    //     else => failure(),
    // }
}
