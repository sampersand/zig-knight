const std = @import("std");
const value = @import("value.zig");
const knight = @import("knight.zig");

const Error = knight.Error;
const Value = value.Value;
const Integer = value.Integer;
const Environment = @import("Environment.zig");
const String = @import("String.zig");

const Function = @This();
pub const max_arity: usize = 4;
comptime {
    std.debug.assert(max_arity == function_S.arity);
}

name: u8,
arity: std.math.IntFittingRange(0, max_arity),
function: fn ([*]const Value, *Environment) knight.Error!Value,

const function_P = Function{
    .name = 'P',
    .arity = 0,
    .function = struct {
        fn fun(_: [*]const Value, env: *Environment) !Value {
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
        fn fun(_: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const str = try args[0].runToStr(env);
            defer str.decrement();

            return knight.play(str.slice(), env);
        }
    }.fun,
};

const function_B = Function{
    .name = 'B',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, _: *Environment) !Value {
            args[0].increment();

            return args[0];
        }
    }.fun,
};

const function_C = Function{
    .name = 'C',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const first_run = try args[0].run(env);
            defer first_run.decrement(env.allocator);

            return first_run.run(env);
        }
    }.fun,
};

pub fn execute(command: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var arguments: [][]const u8 = try allocator.alloc([]const u8, std.mem.count(u8, command, " ") + 1);
    defer allocator.free(arguments);

    var arg_iter = std.mem.tokenize(u8, command, " ");
    var arg_index: usize = 0;

    while (arg_iter.next()) |arg| {
        arguments[arg_index] = arg;
        arg_index += 1;
    }

    var exec_result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = arguments,
    });
    allocator.free(exec_result.stderr);
    return exec_result.stdout;
}

const @"function_`" = Function{
    .name = '`',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const cmd = try args[0].runToStr(env);
            defer cmd.decrement();

            const child = std.ChildProcesss.init(cmd.slice(), env.allocator);

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
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const status = try args[0].runToInt(env);

            std.os.exit(std.math.cast(u8, status) orelse return error.DomainError);
        }
    }.fun,
};

const @"function_!" = Function{
    .name = '!',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
            return Value.init(bool, !try args[0].runToBool(env));
        }
    }.fun,
};

const function_L = Function{
    .name = 'L',
    .arity = 1,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const lhs = try args[0].run(env);

            if (lhs.cast(Integer)) |integer| {
                return Value.init(Integer, integer * try args[1].runToInt(env));
            }

            defer lhs.decrement(env.allocator);

            if (lhs.cast(*String)) |string| {
                const uncast_amount = try args[1].runToInt(env);
                const amount = std.math.cast(usize, uncast_amount) orelse return error.DomainError;

                if (amount == 0) return Value.init(*String, &String.empty);
                if (amount == 1) {
                    string.increment();
                    return lhs;
                }

                const repetition = try env.interner.repeat(env.allocator, string.slice(), amount);
                return Value.init(*String, repetition);
            }

            return error.InvalidType;
        }
    }.fun,
};

const @"function_/" = Function{
    .name = '/',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const lhs = try args[0].run(env);
            defer lhs.decrement(env.allocator);

            const rhs = try args[1].run(env);
            defer lhs.decrement(env.allocator);

            return Value.init(bool, lhs.eql(rhs));
        }
    }.fun,
};

const @"function_&" = Function{
    .name = '&',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const lhs = try args[0].run(env);
            defer lhs.decrement(env.allocator);

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
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const lhs = try args[0].run(env);
            defer lhs.decrement(env.allocator);

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
        fn fun(args: [*]const Value, env: *Environment) !Value {
            (try args[0].run(env)).decrement(env.allocator);

            return args[1].run(env);
        }
    }.fun,
};

const function_W = Function{
    .name = 'W',
    .arity = 2,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
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
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const cast = std.math.cast;

            const string = try args[0].runToStr(env);
            defer string.decrement();

            const start = cast(usize, try args[1].runToInt(env)) orelse return error.DomainError;
            const length = cast(usize, try args[2].runToInt(env)) orelse return error.DomainError;

            if (string.slice().len < start + length) {
                return error.OutOfBounds;
            }

            var substr = try env.allocator.create(String);
            switch (string) {
                .string => |s| substr.initSubstr(s, start, length),
                .integer => |i| try substr.initBorrowed(env.allocator, i.slice()),
            }

            // If there's an error with the allocator, we don't care, we just dont cache.
            _ = env.interner.register(env.allocator, substr);

            return Value.init(*String, substr);
        }
    }.fun,
};

const function_S = Function{
    .name = 'S',
    .arity = 4,
    .function = struct {
        fn fun(args: [*]const Value, env: *Environment) !Value {
            const cast = std.math.cast;

            const string = try args[0].runToStr(env);
            defer string.decrement();

            const start = cast(usize, try args[1].runToInt(env)) orelse return error.DomainError;
            const length = cast(usize, try args[2].runToInt(env)) orelse return error.DomainError;

            const replacement = try args[0].runToStr(env);
            defer replacement.decrement();

            if (string.slice().len < start + length) {
                return error.OutOfBounds;
            }

            var substr = try env.allocator.create(String);
            switch (string) {
                .string => |s| substr.initSubstr(s, start, length),
                .integer => |i| try substr.initBorrowed(env.allocator, i.slice()),
            }

            // If there's an error with the allocator, we don't care, we just dont cache.
            _ = env.interner.register(env.allocator, substr);

            return Value.init(*String, substr);
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

    pub fn run(block: *const Block, env: *Environment) knight.Error!Value {
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
