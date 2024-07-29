const std = @import("std");
const CartridgeError = @import("errors.zig").CartridgeError;

pub const Cartridge = struct {
    alloc: std.mem.Allocator,
    ptr: *anyopaque,
    vtable: *const VTable,

    deinit_fn: *const fn (self: *Cartridge) void,

    const VTable = struct {
        read: *const fn (ptr: *anyopaque, addr: u16) u8,
        write: *const fn (ptr: *anyopaque, addr: u16, val: u8) void,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn init(alloc: std.mem.Allocator, data: []u8) !Cartridge {
        switch (data[0x147]) {
            0x0 => {
                std.debug.print("Selected MBC: ROMOnly\n", .{});
                const rom = try alloc.create(ROMOnly);
                rom.* = ROMOnly.new(data);
                return Cartridge.new(alloc, rom);
            },
            0x1, 0x2, 0x3 => {
                std.debug.print("Selected MBC: MBC1\n", .{});
                const rom = try alloc.create(MBC1);
                rom.* = try MBC1.new(alloc, data);
                return Cartridge.new(alloc, rom);
            },
            0x13 => {
                std.debug.print("Selected MBC: MBC3\n", .{});
                const rom = try alloc.create(MBC3);
                rom.* = try MBC3.new(alloc, data);
                return Cartridge.new(alloc, rom);
            },

            else => return CartridgeError.UnknownMBC,
        }
    }

    fn new(alloc: std.mem.Allocator, obj_ptr: anytype) Cartridge {
        const Type = @TypeOf(obj_ptr);

        return Cartridge{
            .alloc = alloc,
            .ptr = obj_ptr,
            .deinit_fn = &struct {
                fn fun(self: *Cartridge) void {
                    const ptr: Type = @ptrCast(@alignCast(self.ptr));
                    self.alloc.destroy(ptr);
                }
            }.fun,
            .vtable = &.{
                .read = &struct {
                    fn fun(obj: *anyopaque, addr: u16) u8 {
                        const self: Type = @ptrCast(@alignCast(obj));
                        return self.read(addr);
                    }
                }.fun,
                .write = &struct {
                    fn fun(obj: *anyopaque, addr: u16, val: u8) void {
                        const self: Type = @ptrCast(@alignCast(obj));
                        self.write(addr, val);
                    }
                }.fun,
                .deinit = &struct {
                    fn fun(obj: *anyopaque) void {
                        const self: Type = @ptrCast(@alignCast(obj));
                        self.deinit();
                    }
                }.fun,
            },
        };
    }

    pub fn deinit(self: *Cartridge) void {
        self.vtable.deinit(self.ptr);
        self.deinit_fn(self);
    }

    pub fn read(self: Cartridge, addr: u16) u8 {
        return self.vtable.read(self.ptr, addr);
    }

    pub fn write(self: Cartridge, addr: u16, val: u8) void {
        return self.vtable.write(self.ptr, addr, val);
    }
};

pub const ROMOnly = struct {
    data: []u8,

    const Self = @This();

    fn new(data: []u8) Self {
        return .{
            .data = data,
        };
    }

    pub fn read(self: *Self, addr: u16) u8 {
        return self.data[addr];
    }

    pub fn write(_: *Self, _: u16, _: u8) void {}

    pub fn deinit(_: *Self) void {}
};

pub const MBC1 = struct {
    alloc: std.mem.Allocator,
    data: []u8,
    ram: []u8,

    ram_enabled: bool,
    rom_bank: u8,
    ram_bank: u8,

    banking_mode: u1,

    const Self = @This();

    pub fn new(alloc: std.mem.Allocator, data: []u8) !Self {
        const ram = try alloc.alloc(u8, 32 * 1024);
        @memset(ram, 0);

        return MBC1{
            .alloc = alloc,
            .data = data,
            .ram = ram,
            .ram_enabled = false,
            .rom_bank = 1,
            .ram_bank = 0,
            .banking_mode = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.ram);
    }

    pub fn read(self: *Self, addr: u16) u8 {
        return switch (addr) {
            0x0000...0x3FFF => self.data[addr],
            0x4000...0x7FFF => self.data[0x4000 * (@as(usize, if (self.rom_bank == 0) 1 else self.rom_bank) - 1) + addr],
            0xA000...0xBFFF => if (self.ram_enabled) self.ram[self.getRAMAddr(addr)] else 0xff,
            else => 0xFF,
        };
    }

    pub fn write(self: *Self, addr: u16, val: u8) void {
        switch (addr) {
            0...0x1FFF => {
                self.ram_enabled = (val & 0xF) == 0xA;
            },
            0x2000...0x3FFF => {
                self.rom_bank = val & 0x1F;
            },
            0x4000...0x5FFF => {
                self.ram_bank = val & 0x03;
            },
            0x6000...0x7FFF => {
                self.banking_mode = @truncate(val);
            },
            0xA000...0xBFFF => {
                if (self.ram_enabled) {
                    self.ram[self.getRAMAddr(addr)] = val;
                }
            },
            else => {},
        }
    }

    fn getRAMAddr(self: *Self, addr: u16) usize {
        return (addr - 0xA000) + 0x2000 * @as(usize, self.ram_bank);
    }
};

pub const MBC3 = struct {
    alloc: std.mem.Allocator,
    data: []u8,
    ram: []u8,

    ram_enabled: bool,
    rom_bank: u8,
    ram_bank: u8,

    const Self = @This();

    pub fn new(alloc: std.mem.Allocator, data: []u8) !Self {
        const ram = try alloc.alloc(u8, 32 * 1024);
        @memset(ram, 0);

        return MBC3{
            .alloc = alloc,
            .data = data,
            .ram = ram,
            .ram_enabled = false,
            .rom_bank = 1,
            .ram_bank = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.ram);
    }

    pub fn read(self: *Self, addr: u16) u8 {
        return switch (addr) {
            0x0000...0x3FFF => self.data[addr],
            0x4000...0x7FFF => self.data[0x4000 * (@as(usize, self.rom_bank) - 1) + addr],
            0xA000...0xBFFF => if (self.ram_enabled) self.ram[self.getRAMAddr(addr)] else 0xff,
            else => 0xFF,
        };
    }

    pub fn write(self: *Self, addr: u16, val: u8) void {
        switch (addr) {
            0...0x1FFF => {
                self.ram_enabled = (val & 0xF) == 0xA;
            },
            0x2000...0x3FFF => {
                self.rom_bank = if (val == 0) 1 else val;
            },
            0x4000...0x5FFF => {
                // TODO: implement RTC register
                self.ram_bank = val & 0x03;
            },
            0x6000...0x7FFF => {
                // TOOD: latch clock data
            },
            0xA000...0xBFFF => {
                // TODO: implement RTC register
                if (self.ram_enabled) {
                    self.ram[self.getRAMAddr(addr)] = val;
                }
            },
            else => {},
        }
    }

    fn getRAMAddr(self: *Self, addr: u16) usize {
        return (addr - 0xA000) + 0x2000 * @as(usize, self.ram_bank);
    }
};
