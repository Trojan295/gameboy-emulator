const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const assert = std.debug.assert;

const MemoryError = @import("errors.zig").MemoryError;
const DisplayError = @import("errors.zig").DisplayError;

const STATRegister = packed struct {
    mode: u2,
    lyc_eq_ly: bool,
    mode0_int: bool,
    mode1_int: bool,
    mode2_int: bool,
    lyc_int: bool,
    _n: u1,
};

const LCDCRegister = packed struct {
    bg_enable: bool,
    obj_enable: bool,
    obj_size: bool,
    bg_window_tile_map: bool,
    bg_window_tile_data: bool,
    window_enable: bool,
    window_tile_map: bool,
    lcd_enable: bool,
};

pub const PPU = struct {
    alloc: std.mem.Allocator,

    lcdc: LCDCRegister,
    stat: STATRegister,
    ly: u8,
    lyc: u8,
    scx: u8,
    scy: u8,
    wy: u8,
    wx: u8,
    bgp: u8,
    obp0: u8,
    obp1: u8,

    oam: [160]u8,
    vram: [8192]u8,

    cycles: usize,
    scanline_cycles: usize,

    lx: u8,
    window_line_counter: u8,

    lcd: *LCD,

    const Self = @This();

    pub fn new(alloc: std.mem.Allocator) !*PPU {
        const ptr = try alloc.create(PPU);
        ptr.* = PPU{
            .alloc = alloc,
            .lcd = try LCD.new(alloc),
            .oam = undefined,
            .vram = undefined,
            .stat = STATRegister{
                .mode = 3,
                ._n = 0,
                .lyc_int = false,
                .lyc_eq_ly = false,
                .mode0_int = false,
                .mode1_int = false,
                .mode2_int = false,
            },
            .lcdc = LCDCRegister{
                .window_tile_map = false,
                .bg_window_tile_map = false,
                .window_enable = false,
                .obj_enable = false,
                .obj_size = false,
                .bg_enable = false,
                .lcd_enable = false,
                .bg_window_tile_data = false,
            },
            .ly = 0,
            .lyc = 0,
            .scx = 0,
            .scy = 0,
            .wy = 0,
            .wx = 0,
            .bgp = 0,
            .obp0 = 0,
            .obp1 = 0,
            .cycles = 0,
            .scanline_cycles = 0,
            .lx = 0,
            .window_line_counter = 0,
        };
        return ptr;
    }

    pub fn deinit(self: *Self) void {
        self.lcd.deinit();
        self.alloc.destroy(self);
    }

    pub fn write(self: *Self, addr: u16, val: u8) !void {
        switch (addr) {
            0x8000...0x9FFF => self.vram[addr - 0x8000] = val,
            0xFE00...0xFE9F => self.oam[addr - 0xFE00] = val,
            0xFF40 => self.lcdc = @bitCast(val),
            0xFF41 => self.stat = @bitCast(val & 0x78),
            0xFF42 => self.scy = val,
            0xFF43 => self.scx = val,
            0xFF47 => self.bgp = val,
            0xFF48 => self.obp0 = val,
            0xFF49 => self.obp1 = val,
            0xFF4A => self.wy = val,
            0xFF4B => self.wx = val,
            else => return MemoryError.WriteNotAllowed,
        }
    }

    pub fn read(self: *Self, addr: u16) u8 {
        return switch (addr) {
            0x8000...0x9FFF => self.vram[addr - 0x8000],
            0xFE00...0xFE9F => self.oam[addr - 0xFE00],
            0xFF40 => @bitCast(self.lcdc),
            0xFF41 => @bitCast(self.stat),
            0xFF42 => self.scy,
            0xFF43 => self.scx,
            0xFF44 => self.ly,
            0xFF45 => self.lyc,
            0xFF4A => self.wy,
            0xFF4B => self.wx,
            else => 0,
        };
    }

    pub fn tick(self: *Self, ticks: usize) void {
        self.scanline_cycles += ticks;

        switch (self.stat.mode) {
            2 => {
                self.cycles += ticks;
                if (self.cycles >= 80) {
                    self.cycles -= 80;
                    self.scanline_cycles -= 80;
                    self.stat.mode = 3;
                }
            },
            3 => {
                self.cycles += ticks;
                while (self.cycles >= 2) {
                    self.cycles -= 2;
                    self.scanline_cycles -= 2;

                    const is_window = self.lcdc.window_enable and self.wy == self.ly and self.lx > self.wx - 7;

                    var tile_addr: u16 = if ((self.lcdc.bg_window_tile_map and !is_window) or (self.lcdc.window_tile_map and is_window)) 0x9c00 else 0x9800;
                    var offset: u16 = 0;

                    if (!is_window) {
                        offset += ((self.scx + self.lx) / 8) & 0x1F;
                        offset += 32 * (((@as(u16, self.ly) + @as(u16, self.scy)) & 0xFF) / 8);
                    } else {
                        offset += 32 * self.window_line_counter;
                        self.window_line_counter += 1;
                    }

                    tile_addr += offset;

                    const tile_number = self.read(tile_addr);

                    var tile_data_addr: u16 = 0;
                    if (self.lcdc.bg_window_tile_data) {
                        tile_data_addr = 0x8000 + 16 * @as(u16, tile_number);
                    } else {
                        tile_data_addr = 0x9000;
                        tile_data_addr += 16 * ((tile_number ^ 0x80) - 128);
                    }

                    tile_data_addr += 2 * ((@as(u16, self.ly) + @as(u16, self.scy)) % 8);

                    const low = self.read(tile_data_addr);
                    const high = self.read(tile_data_addr + 1);

                    for (0..8) |i| {
                        const exp: u3 = @truncate(i);
                        const mask = std.math.pow(u8, 2, 7 - exp);
                        var val: u2 = 0;
                        if (high & mask == mask) {
                            val += 2;
                        }
                        if (low & mask == mask) {
                            val += 1;
                        }

                        self.lcd.push_pixel(val);
                    }

                    self.lx += 8;
                    if (self.lx == 160) {
                        self.cycles = 0;
                        self.lx = 0;
                        self.stat.mode = 0;
                    }
                }
            },
            0 => {
                if (self.scanline_cycles > 456) {
                    self.scanline_cycles -= 456;

                    self.ly += 1;
                    if (self.ly < 144) {
                        self.stat.mode = 2;
                    } else {
                        self.lcd.render();
                        self.stat.mode = 1;
                    }
                }
            },
            1 => {
                if (self.scanline_cycles > 456) {
                    self.scanline_cycles -= 456;
                    self.ly += 1;
                    if (self.ly > 153) {
                        self.ly = 0;
                        self.stat.mode = 2;
                    }
                }
            },
        }
        self.stat.lyc_eq_ly = self.ly == self.lyc;
    }
};

pub const LCD = struct {
    alloc: std.mem.Allocator,

    framebuffer: [160 * 144]u2,

    pos: usize,

    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,

    const Self = @This();

    pub fn new(alloc: std.mem.Allocator) !*LCD {
        const scale = 5;

        const lcd = try alloc.create(LCD);
        lcd.alloc = alloc;
        lcd.framebuffer = undefined;
        lcd.pos = 0;

        assert(c.SDL_Init(c.SDL_INIT_VIDEO) == 0);

        const window_opt = c.SDL_CreateWindow("GameZigBoy", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 160 * scale, 144 * scale, 0);
        if (window_opt == null) {
            return DisplayError.InitFailed;
        }

        lcd.window = window_opt.?;

        lcd.renderer = c.SDL_CreateRenderer(lcd.window, -1, c.SDL_RENDERER_ACCELERATED).?;

        if (c.SDL_RenderSetScale(lcd.renderer, scale, scale) != 0) {
            return DisplayError.InitFailed;
        }

        return lcd;
    }

    pub fn push_pixel(self: *Self, pixel: u2) void {
        self.framebuffer[self.pos] = pixel;
        self.pos = @mod(self.pos + 1, 160 * 144);
    }

    pub fn render(self: *Self) void {
        for (0..4) |color| {
            assert(switch (color) {
                0 => c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0xFF),
                1 => c.SDL_SetRenderDrawColor(self.renderer, 80, 80, 80, 0xFF),
                2 => c.SDL_SetRenderDrawColor(self.renderer, 160, 160, 150, 0xFF),
                3 => c.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 0xFF),
                else => 0,
            } == 0);

            var points: [160 * 144]c.SDL_Point = undefined;
            var point_len: usize = 0;

            for (0..144) |y| {
                for (0..160) |x| {
                    if (self.framebuffer[160 * y + x] == color) {
                        points[point_len] = c.SDL_Point{
                            .x = @intCast(x),
                            .y = @intCast(y),
                        };
                        point_len += 1;
                    }
                }
            }

            assert(c.SDL_RenderDrawPoints(self.renderer, &points, @intCast(point_len)) == 0);
        }

        c.SDL_RenderPresent(self.renderer);
    }

    pub fn deinit(self: *Self) void {
        self.alloc.destroy(self);
    }
};

test "ppu" {
    const ppu = try PPU.new(std.testing.allocator);
    defer ppu.deinit();

    ppu.tick(100);

    std.debug.print("{any}", .{ppu});
}
