const std = @import("std");
const PPU = @import("ppu.zig").PPU;

const MemoryError = error{
    WriteNotAllowed,
};

pub const Memory = struct {
    bank_00: [16384]u8,
    bank_nn: [16384]u8,
    ext_ram: [8192]u8,
    work_ram: [8192]u8,
    _nu: [96]u8,
    io: *IORegisters,
    high_ram: [127]u8,
    interrupt_enable: u8,

    ppu: *PPU,
    joypad: *Joypad,

    alloc: std.mem.Allocator,

    const Self = @This();

    pub fn new(alloc: std.mem.Allocator) !Self {
        const timer: *Timer = try alloc.create(Timer);
        const interrupts: *Interrupts = try alloc.create(Interrupts);
        const io: *IORegisters = try alloc.create(IORegisters);
        const ppu: *PPU = try PPU.new(alloc, &interrupts.vblank);
        const joypad: *Joypad = try alloc.create(Joypad);
        joypad.* = Joypad.new();

        interrupts.* = Interrupts.new();
        timer.* = Timer.new(&interrupts.timer);

        io.* = IORegisters{
            .timer = timer,
            .interrupts = interrupts,
        };

        const mem = Memory{
            .alloc = alloc,

            .bank_00 = [_]u8{0} ** 16384,
            .bank_nn = [_]u8{0} ** 16384,
            .ext_ram = [_]u8{0} ** 8192,
            .work_ram = [_]u8{0} ** 8192,
            ._nu = [_]u8{0} ** 96,
            .io = io,
            .high_ram = [_]u8{0} ** 127,
            .interrupt_enable = 0,

            .ppu = ppu,
            .joypad = joypad,
        };

        return mem;
    }

    pub fn deinit(self: *Self) void {
        self.ppu.deinit();
        self.alloc.destroy(self.io.timer);
        self.alloc.destroy(self.io.interrupts);
        self.alloc.destroy(self.io);
        self.alloc.destroy(self.joypad);
    }

    pub fn read(self: *Self, addr: u16) u8 {
        return switch (addr) {
            0x0000...0x3fff => self.bank_00[addr],
            0x4000...0x7fff => self.bank_nn[addr - 0x4000],
            0x8000...0x9fff => self.ppu.read(addr),
            0xa000...0xbfff => self.ext_ram[addr - 0xa000],
            0xc000...0xdfff => self.work_ram[addr - 0xc000],
            0xe000...0xfdff => self.work_ram[addr - 0xe000], // Echo RAM of Work RAM
            0xfe00...0xfe9f => self.ppu.read(addr),
            0xfea0...0xfeff => 0,
            0xff00 => self.joypad.read(),
            0xff01...0xff03 => 0x0f, // TODO: implement
            0xff04...0xff07 => self.io.timer.read(addr),
            0xff08...0xff0e => 0, // TODO: implement
            0xff0f => self.io.interrupts.read(),
            0xff10...0xff3f => 0, // TODO: implement
            0xff40...0xff4b => self.ppu.read(addr),
            0xff4c...0xff7f => 0, // TODO: implement
            0xff80...0xfffe => self.high_ram[addr - 0xff80],
            0xffff => self.interrupt_enable,
        };
    }

    pub fn write(self: *Self, addr: u16, val: u8) !void {
        try switch (addr) {
            0x0000...0x3fff => self.bank_00[addr] = val,
            0x4000...0x7fff => self.bank_nn[addr - 0x4000] = val,
            0x8000...0x9fff => self.ppu.write(addr, val),
            0xa000...0xbfff => self.ext_ram[addr - 0xa000] = val,
            0xc000...0xdfff => self.work_ram[addr - 0xc000] = val,
            0xe000...0xfdff => self.work_ram[addr - 0xe000] = val, // Echo RAM of Work RAM
            0xfe00...0xfe9f => try self.ppu.write(addr, val),
            0xfea0...0xfeff => {},
            0xff00 => self.joypad.write(val),
            0xff01...0xff03 => {}, // TODO: implement
            0xff04...0xff07 => try self.io.timer.write(addr, val),
            0xff08...0xff0e => {}, // TODO: implement
            0xff0f => self.io.interrupts.write(val),
            0xff10...0xff3f => {}, // TODO: implement
            0xff40...0xff45 => try self.ppu.write(addr, val),
            0xff46 => try self.dma_oam_transfer(val),
            0xff47...0xff4b => try self.ppu.write(addr, val),
            0xff4c...0xff7f => {}, // TODO: implement
            0xff80...0xfffe => self.high_ram[addr - 0xff80] = val,
            0xffff => self.interrupt_enable = val,
        };
    }

    pub fn dma_oam_transfer(self: *Self, val: u8) MemoryError!void {
        const start_addr = @as(u16, val) * 0x100;
        for (start_addr.., 0xfe00..0xfe9f) |src, dst| {
            try self.write(@intCast(dst), self.read(@intCast(src)));
        }
    }
};

const IORegisters = struct {
    timer: *Timer,
    interrupts: *Interrupts,
};

const Interrupts = struct {
    joypad: bool,
    serial: bool,
    timer: bool,
    lcd: bool,
    vblank: bool,

    const Self = @This();

    fn read(self: *Self) u8 {
        var value: u8 = 0;
        value |= if (self.vblank) 0x01 else 0;
        value |= if (self.lcd) 0x02 else 0;
        value |= if (self.timer) 0x04 else 0;
        value |= if (self.serial) 0x08 else 0;
        value |= if (self.joypad) 0x10 else 0;
        return value;
    }

    fn write(self: *Self, val: u8) void {
        if (val & 0x01 == 0x01) self.vblank = true else self.vblank = false;
        if (val & 0x02 == 0x02) self.lcd = true else self.lcd = false;
        if (val & 0x04 == 0x04) self.timer = true else self.timer = false;
        if (val & 0x08 == 0x08) self.serial = true else self.serial = false;
        if (val & 0x10 == 0x10) self.joypad = true else self.joypad = false;
    }

    fn new() Interrupts {
        return .{
            .joypad = false,
            .serial = false,
            .timer = false,
            .lcd = false,
            .vblank = false,
        };
    }
};

pub const Joypad = struct {
    select_buttons: bool,
    select_dpad: bool,

    up: bool,
    down: bool,
    left: bool,
    right: bool,
    a: bool,
    b: bool,
    start: bool,
    select: bool,

    const Self = @This();

    pub fn new() Joypad {
        return Joypad{
            .select_buttons = false,
            .select_dpad = false,
            .up = true,
            .down = true,
            .left = true,
            .right = true,
            .a = true,
            .b = true,
            .start = true,
            .select = true,
        };
    }

    pub fn write(self: *Self, val: u8) void {
        self.select_buttons = (val & 0x20) == 0x20;
        self.select_dpad = (val & 0x10) == 0x10;
    }

    pub fn read(self: *Self) u8 {
        var val: u8 = 0;
        val += if (self.select_buttons) 0x20 else 0;
        val += if (self.select_dpad) 0x10 else 0;

        if (!self.select_buttons) {
            val += if (self.start) 8 else 0;
            val += if (self.select) 4 else 0;
            val += if (self.b) 2 else 0;
            val += if (self.a) 1 else 0;
        } else if (!self.select_dpad) {
            val += if (self.down) 8 else 0;
            val += if (self.up) 4 else 0;
            val += if (self.left) 2 else 0;
            val += if (self.right) 1 else 0;
        } else {
            val += 0xf;
        }

        return val;
    }
};

const Serial = extern struct {
    sb: u8,
    sc: u8,
};

const Timer = struct {
    // TODO: implement resetting and stoping DIV timer on CPU STOP
    div_counter: usize,
    tima_counter: usize,

    div: u8,
    tima: u8,
    tma: u8,
    tac: u8,

    int: ?*bool,

    const Self = @This();

    fn new(int: *bool) Timer {
        return .{
            .div_counter = 0,
            .tima_counter = 0,
            .div = 0,
            .tima = 0,
            .tma = 0,
            .tac = 0,
            .int = int,
        };
    }

    pub fn tick(self: *Self, ticks: usize) void {
        self.div_counter += ticks;
        self.div +%= @truncate(self.div_counter >> 8);
        self.div_counter &= 0xff;

        if (self.tac & 0x04 != 0x04) {
            return;
        }

        self.tima_counter += ticks;
        const tima_div: usize = switch (self.tac & 0x03) {
            0 => 1024,
            1 => 16,
            2 => 64,
            3 => 256,
            else => 0,
        };

        if (self.tima_counter >= tima_div) {
            self.tima_counter -= tima_div;
            self.tima, const of = @addWithOverflow(self.tima, 1);
            if (of == 1) {
                self.tima = self.tma;
                self.int.?.* = true;
            }
        }
    }

    fn write(self: *Self, addr: u16, val: u8) !void {
        switch (addr) {
            0xff04 => self.div = 0,
            0xff05 => self.tima = val,
            0xff06 => self.tma = val,
            0xff07 => self.tac = val,
            else => return MemoryError.WriteNotAllowed,
        }
    }

    fn read(self: *Self, addr: u16) u8 {
        std.debug.print("{x}\n", .{self.div});

        return switch (addr) {
            0xff04 => self.div,
            0xff05 => self.tima,
            0xff06 => self.tma,
            0xff07 => self.tac,
            else => 255,
        };
    }
};

const Audio = extern struct {
    _todo: [22]u8,
};

const WavePattern = extern struct {
    _todo: [16]u8,
};

const LCD = extern struct {
    _todo: [12]u8,
};

test "timers_div" {
    var memory = try Memory.new(std.testing.allocator);
    defer memory.deinit();
    var timer = memory.io.timer;

    try memory.write(0xFF04, 10);
    try std.testing.expectEqual(0, memory.read(0xFF04));

    timer.tick(128);
    try std.testing.expectEqual(0, timer.div);
    timer.tick(128);
    try std.testing.expectEqual(1, timer.div);
    timer.tick(257);
    try std.testing.expectEqual(2, timer.div);
}

test "timers_tima" {
    var memory = try Memory.new(std.testing.allocator);
    defer memory.deinit();
    var timer = memory.io.timer;

    timer.tac = 0x04;
    timer.tma = 100;

    timer.tick(1023);
    try std.testing.expectEqual(0, memory.io.timer.tima);
    timer.tick(1);
    try std.testing.expectEqual(1, memory.io.timer.tima);
    try std.testing.expectEqual(false, memory.io.interrupts.timer);
    for (0..255) |_| {
        timer.tick(1024);
    }

    try std.testing.expectEqual(100, memory.io.timer.tima);
    try std.testing.expectEqual(true, memory.io.interrupts.timer);
}
