const std = @import("std");
const cpu = @import("cpu.zig");
const Memory = @import("memory.zig").Memory;
const Opcode = @import("opcodes.zig").Opcode;
const LCD = @import("ppu.zig").LCD;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const print = std.debug.print;

const LOGO = [_]u8{
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) @panic("MEMORY LEAKED!");
    }
    const alloc = gpa.allocator();

    const boot_rom = try std.fs.cwd().readFileAlloc(alloc, "gb-bootroms/bin/mgb.bin", 256);
    defer alloc.free(boot_rom);

    var memory = try Memory.new(alloc);
    defer memory.deinit();
    var cp = cpu.new(&memory);

    std.mem.copyForwards(u8, &memory.bank_00, boot_rom);
    std.mem.copyForwards(u8, memory.bank_00[0x0104..], &LOGO);

    var ev: c.SDL_Event = undefined;
    while (true) {
        if (cp.pc == 0x100) {
            break;
        }

        const duration = try cp.executeOp();
        memory.io.timer.tick(duration);
        memory.ppu.tick(duration);

        while (c.SDL_PollEvent(&ev) == 1) {
            switch (ev.type) {
                c.SDL_QUIT => {
                    return 0;
                },
                else => {},
            }
        }
    }

    return 0;
}

fn test_rom(memory: *Memory) !void {
    try memory.write(0, @intFromEnum(Opcode.JP_a16));
    try memory.write(0x9800, 1);

    try memory.write(0x9000, 0b00011011);
    try memory.write(0x9001, 0b00011011);
}
