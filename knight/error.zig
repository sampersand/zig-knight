pub const Error = error{
    UndefinedVariable,
    InvalidConversion,
    OutOfMemory,
} || @import("Parser.zig").Error;
