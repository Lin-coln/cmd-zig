const VT = @import("../../utils/VT.zig");
const std = @import("std");
const Context = @import("../Context.zig");
const VTable = @import("init.zig").VTable;

const Self = @This();
ptr: *anyopaque,
vt: *const VTable,

pub const init = @import("init.zig").init;
pub const initWithChildren = @import("initWithChildren.zig").initWithChildren;
