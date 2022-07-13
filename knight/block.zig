const std = @import("std");
const functions = @import("functions");
const Error = @import("error").Error;

pub const Block = @This();


// pub const max_arity: usize = 4;

// pub const Function = struct {
//     func: fn ([*]Value) Error!Value,
//     arity: u2, // Max arity is four
//     name: u8,
// };


// pub fn Block(alloc: Allocator) type {
//     const blockType = struct {
//         func: *const functions.Function,
//         args: [functions.max_arity]Value(alloc),
//     };

//     return RefCounted(alloc, blockType, struct {
//         fn free(block: blockType) void {
//             var i = 0;

//             while (i < block.func.arity) : (i += 1) {
//                 block.args[i].free();
//             }
//         }
//     }.free);
// }
