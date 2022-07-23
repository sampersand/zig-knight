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

const function_P = Function{
    .name = 'P',
    .arity = 0,
    .function = struct {
        fn fun(_: [*]const Value, env: *Environment) Error!Value {
            const line = (try std.io.getStdIn().reader().readUntilDelimiterOrEofAlloc(
                env.allocator,
                '\n',
                std.math.maxInt(usize),
            )) orelse return Value.@"null";
            const string = try env.allocator.create(String);
            string.initOwned(line);
            return Value.init(*String, string);
        }
    }.fun,
};

const function_R = Function{
    .name = 'R',
    .arity = 0,
    .function = struct {
        fn fun(_: [*]const Value, env: *Environment) Error!Value {
            // rand should only return positive integers.
            const UInteger = std.meta.Int(.unsigned, @bitSizeOf(Integer) - 1);

            return Value.init(Integer, env.random.random().int(UInteger));
        }
    }.fun,
};

const function_E = Function{
    .name = 'E',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const str = try args[0].runToStr(env);
            defer str.decrement();

            return @import("knight.zig").play(str.slice(), env);
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
            std.debug.todo("this function");
        }
    }.fun,
};

const function_Q = Function{
    .name = 'Q',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const status = try args[0].runToInt(env);

            std.os.exit(std.math.cast(u8, status) orelse return error.DomainError);
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
            const str = try args[0].runToStr(env);
            defer str.decrement();

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
            errdefer ran.decrement(env.allocator); // on success, we should just return it.

            const stdout = std.io.getStdOut().writer();
            try ran.dump(stdout);
            try stdout.writeAll("\n");

            return ran;
        }
    }.fun,
};

const function_O = Function{
    .name = 'O',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const str = try args[0].runToStr(env);
            defer str.decrement();
            const slice = str.slice();

            var stdout_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
            const stdout = stdout_buffer.writer();

            if (slice.len == 0 or slice[slice.len - 1] != '\\') {
                try stdout.writeAll(slice);
                try stdout.writeAll("\n");
            } else {
                try stdout.writeAll(slice[0 .. slice.len - 1]);
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
            const arg = try args[0].run(env);

            if (arg.cast(Integer)) |integer| {
                const byte = std.math.cast(u8, integer) orelse return error.NotAnAsciiInteger;
                const string = try env.interner.fetch(env.allocator, @as(*const [1]u8, &byte));

                return Value.init(*String, string);
            }

            defer arg.decrement(env.allocator);

            if (arg.cast(*String)) |string| {
                const slice = string.slice();
                return if (slice.len == 0) error.EmptyString else Value.init(Integer, slice.ptr[0]);
            }

            return error.InvalidType;
        }
    }.fun,
};

const @"function_+" = Function{
    .name = '+',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                return Value.init(Integer, integer + try args[1].runToInt(env));
            }

            defer lhs.decrement(env.allocator);

            if (lhs.cast(*String)) |string| {
                const rstring = try args[1].runToStr(env);
                defer rstring.decrement();

                if (rstring.slice().len == 0) {
                    string.increment();
                    return lhs;
                }

                if (string.slice().len == 0) {
                    return Value.init(*String, try rstring.toString(env.allocator, &env.interner));
                }

                const cat = try env.interner.concat(env.allocator, string.slice(), rstring.slice());
                return Value.init(*String, cat);
            }

            return error.InvalidType;
        }
    }.fun,
};

const @"function_-" = Function{
    .name = '-',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                return Value.init(Integer, integer - try args[1].runToInt(env));
            }

            lhs.decrement(env.allocator);
            return error.InvalidType;
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
            std.debug.todo("this function");
        }
    }.fun,
};

const @"function_/" = Function{
    .name = '/',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                const denom = try args[1].runToInt(env);
                return Value.init(Integer, try std.math.divTrunc(Integer, integer, denom));
            }

            lhs.decrement(env.allocator);
            return error.InvalidType;
        }
    }.fun,
};

const @"function_%" = Function{
    .name = '%',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                const base = try args[1].runToInt(env);
                return Value.init(Integer, try std.math.mod(Integer, integer, base));
            }

            lhs.decrement(env.allocator);
            return error.InvalidType;
        }
    }.fun,
};

const @"function_^" = Function{
    .name = '^',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                const exponent = try args[1].runToInt(env);
                return Value.init(Integer, try std.math.powi(Integer, integer, exponent));
            }

            lhs.decrement(env.allocator);
            return error.InvalidType;
        }
    }.fun,
};

const @"function_<" = Function{
    .name = '<',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                return Value.init(bool, integer < try args[1].runToInt(env));
            }

            if (lhs.cast(bool)) |boolean| {
                return Value.init(bool, !boolean and try args[1].runToBool(env));
            }

            defer lhs.decrement(env.allocator);

            if (lhs.cast(*String)) |string| {
                const rstring = try args[1].runToStr(env);
                defer rstring.decrement();

                return Value.init(bool, .lt == std.mem.order(u8, string.slice(), rstring.slice()));
            }

            return error.InvalidType;
        }
    }.fun,
};

const @"function_>" = Function{
    .name = '>',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                return Value.init(bool, integer > try args[1].runToInt(env));
            }

            if (lhs.cast(bool)) |boolean| {
                return Value.init(bool, boolean and !try args[1].runToBool(env));
            }

            defer lhs.decrement(env.allocator);

            if (lhs.cast(*String)) |string| {
                const rstring = try args[1].runToStr(env);
                defer rstring.decrement();

                return Value.init(bool, .gt == std.mem.order(u8, string.slice(), rstring.slice()));
            }

            return error.InvalidType;
        }
    }.fun,
};

const @"function_?" = Function{
    .name = '?',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);
            defer lhs.decrement(env.allocator);

            const rhs = try args[1].run(env);
            defer lhs.decrement(env.allocator);

            // Identical values are equivalent.
            if (lhs == rhs) return Value.@"true";

            // If the tags dont match, the values aren't equivalent.
            if (lhs.tag() != rhs.tag()) return Value.@"false";

            // Only strings require a downcast.
            if (lhs.cast(*String)) |string| {
                const rstring = rhs.cast(*String).?;
                return Value.init(bool, std.mem.eql(u8, string.slice(), rstring.slice()));
            }

            return Value.@"false";
        }
    }.fun,
};

const @"function_&" = Function{
    .name = '&',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);
            defer lhs.decrement(env.allocator);

            // `eql` must be a non-error and `true`.
            if (!try lhs.toBool()) {
                lhs.increment();
                return lhs;
            }

            return args[1].run(env);
        }
    }.fun,
};

const @"function_|" = Function{
    .name = '|',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const lhs = try args[0].run(env);
            defer lhs.decrement(env.allocator);

            // `eql` must be a non-error and `true`.
            if (try lhs.toBool()) {
                lhs.increment();
                return lhs;
            }

            return args[1].run(env);
        }
    }.fun,
};

const @"function_;" = Function{
    .name = ';',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            (try args[0].run(env)).decrement(env.allocator);

            return args[1].run(env);
        }
    }.fun,
};

const function_W = Function{
    .name = 'W',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            while (try args[0].runToBool(env)) {
                (try args[1].run(env)).decrement(env.allocator);
            }

            return Value.@"null";
        }
    }.fun,
};

const @"function_=" = Function{
    .name = '=',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const variable = args[0].cast(*Environment.Variable) orelse return error.InvalidType;

            const rhs = try args[1].run(env);
            rhs.increment();
            variable.assign(env.allocator, rhs);

            return rhs;
        }
    }.fun,
};

const function_I = Function{
    .name = 'I',
    .arity = 3,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            return if (try args[0].runToBool(env))
                args[1].run(env)
            else
                args[2].run(env);
        }
    }.fun,
};

const function_G = Function{
    .name = 'G',
    .arity = 3,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) Error!Value {
            const str = try args[0].runToStr(env);
            defer str.decrement();

            const start = try args[1].runToInt(env);
            const length = try args[1].runToInt(env);

            _ = start;
            _ = length;
            std.debug.todo("G");
            // return Value.init(*String, str.substr(env.allocator, start, length));
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
            std.debug.todo("this function");
        }
    }.fun,
};

/// Fetches the function identified by `name`, returning `null` it no such function exists.
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

        if (block.refcount != 0) return;

        var i = @as(usize, 0);
        while (i < block.function.arity) : (i += 1) {
            block.args[i].decrement(alloc);
        }

        block.* = undefined;
        alloc.destroy(block);
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
