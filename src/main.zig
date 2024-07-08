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

    var args = std.process.args();
    _ = args.skip();
    const rom = args.next().?;

    const boot_rom = try std.fs.cwd().readFileAlloc(alloc, "gb-bootroms/bin/mgb.bin", 256);
    defer alloc.free(boot_rom);

    const cartridge = try std.fs.cwd().readFileAlloc(alloc, rom, 32 * 1024);
    defer alloc.free(cartridge);

    var memory = try Memory.new(alloc);
    defer memory.deinit();

    const joypad = memory.joypad;

    var cp = cpu.new(&memory);

    std.mem.copyForwards(u8, &memory.bank_00, boot_rom);

    for (0x100.., cartridge[0x100..]) |pos, val| {
        try memory.write(@intCast(pos), val);
    }

    var ev: c.SDL_Event = undefined;
    var debug = false;

    while (true) {
        var cycles: usize = 0;
        for (0..100) |_| {
            if (debug) {
                const opcode: Opcode = @enumFromInt(memory.read(cp.pc));
                std.debug.print("pc: {x}, op: {any}\n", .{ cp.pc, opcode });
            }

            const duration = try cp.executeOp();
            memory.io.timer.tick(duration);
            try memory.ppu.tick(duration);

            cycles += duration;

            if (cycles > 1000) {
                cycles -= 1000;
                std.time.sleep(10);
            }

            if (cp.pc == 0x100) {
                for (0..0x100) |addr| {
                    try memory.write(@intCast(addr), cartridge[addr]);
                }
            }
        }

        while (c.SDL_PollEvent(&ev) == 1) {
            switch (ev.type) {
                c.SDL_QUIT => {
                    return 0;
                },
                c.SDL_KEYDOWN => {
                    switch (ev.key.keysym.scancode) {
                        c.SDL_SCANCODE_P => debug = !debug,
                        c.SDL_SCANCODE_A => joypad.left = false,
                        c.SDL_SCANCODE_D => joypad.right = false,
                        c.SDL_SCANCODE_W => joypad.up = false,
                        c.SDL_SCANCODE_S => joypad.down = false,
                        c.SDL_SCANCODE_K => joypad.a = false,
                        c.SDL_SCANCODE_L => joypad.b = false,
                        c.SDL_SCANCODE_SPACE => joypad.start = false,
                        c.SDL_SCANCODE_RETURN => joypad.select = false,
                        else => {},
                    }
                },
                c.SDL_KEYUP => {
                    switch (ev.key.keysym.scancode) {
                        c.SDL_SCANCODE_P => debug = !debug,
                        c.SDL_SCANCODE_A => joypad.left = true,
                        c.SDL_SCANCODE_D => joypad.right = true,
                        c.SDL_SCANCODE_W => joypad.up = true,
                        c.SDL_SCANCODE_S => joypad.down = true,
                        c.SDL_SCANCODE_K => joypad.a = true,
                        c.SDL_SCANCODE_L => joypad.b = true,
                        c.SDL_SCANCODE_SPACE => joypad.start = true,
                        c.SDL_SCANCODE_RETURN => joypad.select = true,
                        else => {},
                    }
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
