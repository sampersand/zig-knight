const std = @import("std");
pub const Error = error{
    UndefinedVariable,
    InvalidConversion,
    NotAnAsciiInteger,
    InvalidType,
    EmptyString,
    DomainError,
    OutOfMemory, // todo: union with error?
} || @import("Parser.zig").Error || std.os.WriteError;
