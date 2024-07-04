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

    alloc: std.mem.Allocator,

    const Self = @This();

    pub fn new(alloc: std.mem.Allocator) !Self {
        const timer: *Timer = try alloc.create(Timer);
        const interrupts: *Interrupts = try alloc.create(Interrupts);
        const io: *IORegisters = try alloc.create(IORegisters);
        const ppu: *PPU = try PPU.new(alloc);

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
        };

        return mem;
    }

    pub fn deinit(self: *Self) void {
        self.ppu.deinit();
        self.alloc.destroy(self.io.timer);
        self.alloc.destroy(self.io.interrupts);
        self.alloc.destroy(self.io);
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
            0xff00...0xff03 => 0, // TODO: implement
            0xff04...0xff07 => 0, //self.io.timer.read(addr),
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
        switch (addr) {
            0x0000...0x3fff => self.bank_00[addr] = val,
            0x4000...0x7fff => self.bank_nn[addr - 0x4000] = val,
            0x8000...0x9fff => try self.ppu.write(addr, val),
            0xa000...0xbfff => self.ext_ram[addr - 0xa000] = val,
            0xc000...0xdfff => self.work_ram[addr - 0xc000] = val,
            0xe000...0xfdff => self.work_ram[addr - 0xe000] = val, // Echo RAM of Work RAM
            0xfe00...0xfe9f => try self.ppu.write(addr, val),
            0xfea0...0xfeff => {},
            0xff00...0xff03 => {}, // TODO: implement
            0xff04...0xff07 => try self.io.timer.write(addr, val),
            0xff08...0xff0e => {}, // TODO: implement
            0xff0f => self.io.interrupts.write(val),
            0xff10...0xff3f => {}, // TODO: implement
            0xff40...0xff4b => try self.ppu.write(addr, val),
            0xff4c...0xff7f => {}, // TODO: implement
            0xff80...0xfffe => self.high_ram[addr - 0xff80] = val,
            0xffff => self.interrupt_enable = val,
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

const Joypad = extern struct { input: u8 };

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
