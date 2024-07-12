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
    };

    pub fn init(alloc: std.mem.Allocator, data: []u8) !Cartridge {
        switch (data[0x147]) {
            0x0 => {
                const rom = try alloc.create(ROMOnly);
                rom.* = ROMOnly.new(data);
                return Cartridge.new(alloc, rom);
            },
            0x1 => {
                const rom = try alloc.create(MBC1);
                rom.* = MBC1.new(data);
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
            },
        };
    }

    pub fn deinit(self: *Cartridge) void {
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
};

pub const MBC1 = struct {
    data: []u8,

    ram_enabled: bool,
    rom_bank: u8,
    ram_bank: u8,

    banking_mode: u1,

    const Self = @This();

    pub fn new(data: []u8) MBC1 {
        return MBC1{
            .data = data,
            .ram_enabled = false,
            .rom_bank = 0,
            .ram_bank = 0,
            .banking_mode = 0,
        };
    }

    pub fn read(self: *Self, addr: u16) u8 {
        return switch (addr) {
            0x0000...0x3FFF => self.data[addr],
            0x4000...0x7FFF => self.data[0x4000 * @as(usize, self.rom_bank - 1) + addr],
            0xA000...0xBFFF => 0xFF,
            else => 0xFF,
        };
    }

    pub fn write(self: *Self, addr: u16, val: u8) void {
        switch (addr) {
            0...0x1FFF => {
                self.ram_enabled = (val & 0xF) == 0xA;
            },
            0x2000...0x3FFF => {
                self.rom_bank = if (val == 0) 1 else val & 0x1F;
            },
            0x4000...0x5FFF => {
                self.ram_bank = val & 0x03;
            },
            0x6000...0x7FFF => {
                self.banking_mode = @truncate(val & 1);
            },
            else => {},
        }
    }
};

test "mbc1" {}
