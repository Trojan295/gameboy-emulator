const std = @import("std");
const cpu = @import("cpu.zig");

const print = std.debug.print;

pub fn main() !void {
    var c = cpu.new();
    const flags = c.getFlags();

    flags.carry = true;
}
