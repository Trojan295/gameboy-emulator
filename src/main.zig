const std = @import("std");
const cpu = @import("cpu.zig");
const mbc = @import("mbc.zig");
const Memory = @import("memory.zig").Memory;
const Opcode = @import("opcodes.zig").Opcode;
const LCD = @import("ppu.zig").LCD;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const print = std.debug.print;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) @panic("MEMORY LEAKED!");
    }
    const alloc = gpa.allocator();

    var args = std.process.args();
    _ = args.skip();
    const rom = args.next().?;

    std.debug.assert(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) == 0);
    defer c.SDL_Quit();

    const boot_rom = try std.fs.cwd().readFileAlloc(alloc, "roms/bootix_dmg.bin", 256);
    defer alloc.free(boot_rom);

    const cartridge_data = try std.fs.cwd().readFileAlloc(alloc, rom, 1024 * 1024);
    defer alloc.free(cartridge_data);

    var cartridge = try mbc.Cartridge.init(alloc, cartridge_data);
    defer cartridge.deinit();

    var memory = try Memory.new(alloc, boot_rom, cartridge);
    defer memory.deinit();

    const joypad = memory.joypad;

    var cp = cpu.new(&memory);

    memory.ppu.lcd.cpu = &cp;

    var ev: c.SDL_Event = undefined;
    var debug = false;
    var cycles: usize = 0;

    while (true) {
        const start = try std.time.Instant.now();

        while (true) {
            if (debug) {
                const opcode: Opcode = @enumFromInt(memory.read(cp.pc));
                std.debug.print("pc: {x}, op: {any}\n", .{ cp.pc, opcode });
            }

            if (memory.booting and cp.pc == 0x100) {
                memory.endBoot();
            }

            const duration = try cp.executeOp();
            memory.io.timer.tick(duration);
            try memory.ppu.tick(duration);
            memory.audio.tick(duration);

            cycles += duration;

            if (cycles > 16777) {
                cycles -= 16777;
                break;
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

        const end = try std.time.Instant.now();
        const elapsed = end.since(start);
        const wait_time, const overflow = @subWithOverflow(4 * std.time.ns_per_ms, elapsed);
        if (overflow == 0) {
            const wait_ms: u32 = @intCast(wait_time / @as(u64, 1E6));
            c.SDL_Delay(wait_ms);
        }
    }

    return 0;
}
