const std = @import("std");
pub const Error = error{
    UndefinedVariable,
    InvalidConversion,
    NotAnAsciiInteger,
    InvalidType,
    EmptyString,
    DomainError,
} || @import("Parser.zig").Error || std.os.WriteError || error{
    // todo: make all these unions with builtin type somehow
    OutOfMemory,
    DivisionByZero,
    Overflow,
    NegativeDenominator,
    Underflow,
};
