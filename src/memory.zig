pub const Memory = extern struct {
    bank_00: [16384]u8,
    bank_nn: [16384]u8,
    vram: [8192]u8,
    ext_ram: [8192]u8,
    work_ram: [8192]u8,
    _echo_ram: [7680]u8,
    oam: [160]u8,
    _nu: [96]u8,
    io: [128]u8,
    high_ram: [127]u8,
    interrupt_enable: u8,

    const Self = @This();

    pub fn new() Self {
        return Memory{
            .bank_00 = [_]u8{0} ** 16384,
            .bank_nn = [_]u8{0} ** 16384,
            .vram = [_]u8{0} ** 8192,
            .ext_ram = [_]u8{0} ** 8192,
            .work_ram = [_]u8{0} ** 8192,
            ._echo_ram = [_]u8{0} ** 7680,
            .oam = [_]u8{0} ** 160,
            ._nu = [_]u8{0} ** 96,
            .io = [_]u8{0} ** 128,
            .high_ram = [_]u8{0} ** 127,
            .interrupt_enable = 0,
        };
    }

    pub fn memoryArray(self: *Self) *[65536]u8 {
        return @ptrCast(self);
    }

    pub fn read(self: *Self, addr: u16) u8 {
        return self.memoryArray().*[addr];
    }

    pub fn write(self: *Self, addr: u16, val: u8) void {
        self.memoryArray().*[addr] = val;
    }
};
