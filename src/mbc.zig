const std = @import("std");

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

    fn banksCount(self: *Self) u8 {
        const div = self.data.len / (16 * 1024);
        return @truncate(if (self.data.len % (16 * 1024) > 0) div + 1 else div);
    }
};

test "mbc1" {
    var cartridge = [_]u8{0} ** (32 * 1024);
    var mbc1 = MBC1.new(cartridge[0 .. 16 * 1024]);
    try std.testing.expectEqual(1, mbc1.banksCount());
    var mbc2 = MBC1.new(cartridge[0 .. 16 * 1024 + 1]);
    try std.testing.expectEqual(2, mbc2.banksCount());
}
