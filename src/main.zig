const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const mbc = @import("mbc.zig");
const Memory = @import("memory.zig").Memory;
const LCD = @import("ppu.zig").LCD;
const Opcode = @import("opcodes.zig").Opcode;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const print = std.debug.print;

const BOOT_ROM = [_]u8{
    0x31, 0xfe, 0xff, 0x21, 0xff, 0x9f, 0xaf, 0x32, 0xcb, 0x7c, 0x20, 0xfa,
    0x0e, 0x11, 0x21, 0x26, 0xff, 0x3e, 0x80, 0x32, 0xe2, 0x0c, 0x3e, 0xf3,
    0x32, 0xe2, 0x0c, 0x3e, 0x77, 0x32, 0xe2, 0x11, 0x04, 0x01, 0x21, 0x10,
    0x80, 0x1a, 0xcd, 0xb8, 0x00, 0x1a, 0xcb, 0x37, 0xcd, 0xb8, 0x00, 0x13,
    0x7b, 0xfe, 0x34, 0x20, 0xf0, 0x11, 0xcc, 0x00, 0x06, 0x08, 0x1a, 0x13,
    0x22, 0x23, 0x05, 0x20, 0xf9, 0x21, 0x04, 0x99, 0x01, 0x0c, 0x01, 0xcd,
    0xb1, 0x00, 0x3e, 0x19, 0x77, 0x21, 0x24, 0x99, 0x0e, 0x0c, 0xcd, 0xb1,
    0x00, 0x3e, 0x91, 0xe0, 0x40, 0x06, 0x10, 0x11, 0xd4, 0x00, 0x78, 0xe0,
    0x43, 0x05, 0x7b, 0xfe, 0xd8, 0x28, 0x04, 0x1a, 0xe0, 0x47, 0x13, 0x0e,
    0x1c, 0xcd, 0xa7, 0x00, 0xaf, 0x90, 0xe0, 0x43, 0x05, 0x0e, 0x1c, 0xcd,
    0xa7, 0x00, 0xaf, 0xb0, 0x20, 0xe0, 0xe0, 0x43, 0x3e, 0x83, 0xcd, 0x9f,
    0x00, 0x0e, 0x27, 0xcd, 0xa7, 0x00, 0x3e, 0xc1, 0xcd, 0x9f, 0x00, 0x11,
    0x8a, 0x01, 0xf0, 0x44, 0xfe, 0x90, 0x20, 0xfa, 0x1b, 0x7a, 0xb3, 0x20,
    0xf5, 0x18, 0x49, 0x0e, 0x13, 0xe2, 0x0c, 0x3e, 0x87, 0xe2, 0xc9, 0xf0,
    0x44, 0xfe, 0x90, 0x20, 0xfa, 0x0d, 0x20, 0xf7, 0xc9, 0x78, 0x22, 0x04,
    0x0d, 0x20, 0xfa, 0xc9, 0x47, 0x0e, 0x04, 0xaf, 0xc5, 0xcb, 0x10, 0x17,
    0xc1, 0xcb, 0x10, 0x17, 0x0d, 0x20, 0xf5, 0x22, 0x23, 0x22, 0x23, 0xc9,
    0x3c, 0x42, 0xb9, 0xa5, 0xb9, 0xa5, 0x42, 0x3c, 0x00, 0x54, 0xa8, 0xfc,
    0x42, 0x4f, 0x4f, 0x54, 0x49, 0x58, 0x2e, 0x44, 0x4d, 0x47, 0x20, 0x76,
    0x31, 0x2e, 0x32, 0x00, 0x3e, 0xff, 0xc6, 0x01, 0x0b, 0x1e, 0xd8, 0x21,
    0x4d, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x3e, 0x01, 0xe0, 0x50,
};

const Emulator = struct {
    memory: *Memory,
    cpu: *CPU,

    running: bool,
    debug: bool,
    cycles: usize,

    const Self = @This();

    fn new(memory: *Memory, cpu: *CPU) Emulator {
        return Self{
            .memory = memory,
            .cpu = cpu,
            .cycles = 0,
            .running = true,
            .debug = false,
        };
    }

    fn start(self: *Self) !void {
        while (true) {
            const start_time = try std.time.Instant.now();

            if (try self.handleInput() > 0) {
                return;
            }

            while (self.running) {
                if (self.debug) {
                    const opcode: Opcode = @enumFromInt(self.memory.read(self.cpu.pc));
                    std.debug.print("pc: {x}, op: {any}\n", .{ self.cpu.pc, opcode });
                }

                if (self.memory.booting and self.cpu.pc == 0x100) {
                    self.memory.endBoot();
                }

                const duration = try self.cpu.executeOp();
                self.memory.io.timer.tick(duration);
                try self.memory.ppu.tick(duration);
                self.memory.audio.tick(duration);

                self.cycles += duration;

                if (self.cycles >= 67108) {
                    self.cycles -= 67108;
                    break;
                }
            }

            //try self.memory.ppu.lcd.render();

            const end = try std.time.Instant.now();
            const elapsed = end.since(start_time);
            const wait_time, const overflow = @subWithOverflow(16 * std.time.ns_per_ms, elapsed);
            if (overflow == 0) {
                const wait_ms: u32 = @intCast(wait_time / @as(u64, 1E6));
                c.SDL_Delay(wait_ms);
            }
        }
    }

    fn handleInput(self: *Self) !u8 {
        var ev: c.SDL_Event = undefined;
        const joypad = self.memory.joypad;

        while (c.SDL_PollEvent(&ev) == 1) {
            switch (ev.type) {
                c.SDL_QUIT => {
                    return 1;
                },
                c.SDL_KEYDOWN => {
                    switch (ev.key.keysym.scancode) {
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
                        c.SDL_SCANCODE_P => self.debug = !self.debug,
                        c.SDL_SCANCODE_B => self.running = !self.running,
                        c.SDL_SCANCODE_N => {
                            var dump = [_]u8{0} ** 0x10000;
                            for (0..0x10000) |i| {
                                const addr: u16 = @truncate(i);
                                dump[addr] = self.memory.read(addr);
                            }

                            const file = try std.fs.cwd().createFile("dump.bin", .{});
                            defer file.close();

                            try file.writeAll(&dump);
                        },
                        c.SDL_SCANCODE_A => joypad.left = true,
                        c.SDL_SCANCODE_D => joypad.right = true,
                        c.SDL_SCANCODE_W => joypad.up = true,
                        c.SDL_SCANCODE_S => joypad.down = true,
                        c.SDL_SCANCODE_K => joypad.a = true,
                        c.SDL_SCANCODE_L => joypad.b = true,
                        c.SDL_SCANCODE_SPACE => joypad.start = true,
                        c.SDL_SCANCODE_RETURN => joypad.select = true,
                        c.SDL_SCANCODE_F => try self.memory.ppu.lcd.setFullscreen(),
                        else => {},
                    }
                },
                c.SDL_JOYBUTTONUP => {
                    switch (ev.jbutton.button) {
                        c.SDL_CONTROLLER_BUTTON_A => joypad.a = true,
                        c.SDL_CONTROLLER_BUTTON_B => joypad.b = true,
                        c.SDL_CONTROLLER_BUTTON_START => joypad.start = true,
                        c.SDL_CONTROLLER_BUTTON_MISC1 => joypad.select = true,
                        else => {},
                    }
                },
                c.SDL_JOYBUTTONDOWN => {
                    switch (ev.jbutton.button) {
                        c.SDL_CONTROLLER_BUTTON_A => joypad.a = false,
                        c.SDL_CONTROLLER_BUTTON_B => joypad.b = false,
                        c.SDL_CONTROLLER_BUTTON_START => joypad.start = false,
                        c.SDL_CONTROLLER_BUTTON_MISC1 => joypad.select = false,
                        else => {
                            std.debug.print("btn\n", .{});
                        },
                    }
                },
                c.SDL_JOYHATMOTION => {
                    joypad.up = ev.jhat.value & c.SDL_HAT_UP != c.SDL_HAT_UP;
                    joypad.down = ev.jhat.value & c.SDL_HAT_DOWN != c.SDL_HAT_DOWN;
                    joypad.left = ev.jhat.value & c.SDL_HAT_LEFT != c.SDL_HAT_LEFT;
                    joypad.right = ev.jhat.value & c.SDL_HAT_RIGHT != c.SDL_HAT_RIGHT;
                },
                else => {},
            }
        }

        return 0;
    }
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

    std.debug.assert(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_JOYSTICK) == 0);
    defer c.SDL_Quit();

    var joystick: ?*c.SDL_Joystick = null;
    if (c.SDL_NumJoysticks() > 0) {
        joystick = c.SDL_JoystickOpen(0).?;
    }
    defer {
        if (joystick != null) {
            c.SDL_JoystickClose(joystick.?);
        }
    }

    const cartridge_data = try std.fs.cwd().readFileAlloc(alloc, rom, 1024 * 1024);
    defer alloc.free(cartridge_data);

    var cartridge = try mbc.Cartridge.init(alloc, cartridge_data);
    defer cartridge.deinit();

    const lcd = try LCD.new(alloc);
    defer lcd.deinit();

    var memory = try Memory.new(alloc, &BOOT_ROM, cartridge, lcd);
    defer memory.deinit();

    var cpu = CPU.new(&memory);
    memory.ppu.lcd.cpu = &cpu;

    var emulator = Emulator.new(&memory, &cpu);

    emulator.start() catch |err| {
        std.debug.print("error: {any}", .{err});
        return 1;
    };

    return 0;
}
