const std = @import("std");
const cpu = @import("cpu.zig");
const Memory = @import("memory.zig").Memory;

const print = std.debug.print;

const LOGO = [_]u8{
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) @panic("MEMORY LEAKED!");
    }
    const alloc = gpa.allocator();

    const boot_rom = try std.fs.cwd().readFileAlloc(alloc, "gb-bootroms/bin/mgb.bin", 256);
    defer alloc.free(boot_rom);

    var memory = Memory.new();
    var c = cpu.new(memory.memoryArray());

    std.mem.copyForwards(u8, memory.memoryArray(), boot_rom);
    std.mem.copyForwards(u8, memory.memoryArray()[0x0104..], &LOGO);

    // TODO: allow going instruction by instruction
    while (true) {
        const duration = try c.executeOp();
        std.debug.print("pc: {d}, op: {x}, dur: {d}\n", .{ c.pc, c.memory[c.pc], duration });
        if (c.pc == 0x100) {
            break;
        }
    }
}
