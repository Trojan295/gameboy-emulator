const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const CPU = @import("cpu.zig").CPU;

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

const STATInts = struct {
    mode0: bool,
    mode1: bool,
    mode2: bool,
    lyc: bool,

    const Self = @This();

    fn new() STATInts {
        return STATInts{
            .mode0 = false,
            .mode1 = false,
            .mode2 = false,
            .lyc = false,
        };
    }

    fn any(self: *const Self) bool {
        return self.mode0 or self.mode1 or self.mode2 or self.lyc;
    }
};

const LCDCRegister = packed struct {
    bg_enable: bool,
    obj_enable: bool,
    obj_size: bool,
    bg_tile_map_select: bool,
    tile_data_select: bool,
    window_enable: bool,
    window_tile_map: bool,
    lcd_enable: bool,
};

const Sprite = struct {
    position: usize,
    data: SpriteData,
};

const SpriteData = packed struct {
    y: u8,
    x: u8,
    tile_idx: u8,
    cgb_palette: u3,
    bank: u1,
    dmg_palette: u1,
    x_flip: bool,
    y_flip: bool,
    priority: bool,
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
    sprite_buffer: std.ArrayList(Sprite),
    window_line_counter: u16,

    lx: u8,

    lcd: *LCD,

    stat_int_line: bool,
    vblank_interrupt: *bool,
    stat_interrupt: *bool,

    const Self = @This();

    pub fn new(alloc: std.mem.Allocator, lcd: *LCD, vblank_interrupt: *bool, stat_interrupt: *bool) !*PPU {
        _ = c.TTF_Init();

        const ptr = try alloc.create(PPU);
        ptr.* = PPU{
            .alloc = alloc,
            .vblank_interrupt = vblank_interrupt,
            .stat_interrupt = stat_interrupt,
            .stat_int_line = false,
            .lcd = lcd,
            .oam = undefined,
            .vram = undefined,
            .sprite_buffer = std.ArrayList(Sprite).init(alloc),
            .stat = STATRegister{
                .mode = 0,
                ._n = 0,
                .lyc_int = false,
                .lyc_eq_ly = false,
                .mode0_int = false,
                .mode1_int = false,
                .mode2_int = false,
            },
            .lcdc = LCDCRegister{
                .window_tile_map = false,
                .bg_tile_map_select = false,
                .window_enable = false,
                .obj_enable = false,
                .obj_size = false,
                .bg_enable = false,
                .lcd_enable = false,
                .tile_data_select = false,
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
            .lx = 0,
            .window_line_counter = 0,
        };
        return ptr;
    }

    pub fn deinit(self: *Self) void {
        self.sprite_buffer.deinit();
        self.alloc.destroy(self);
    }

    pub fn write(self: *Self, addr: u16, val: u8) !void {
        switch (addr) {
            0x8000...0x9FFF => {
                if (self.stat.mode != 3 or !self.lcdc.lcd_enable) self.vram[addr - 0x8000] = val;
            },
            0xFE00...0xFE9F => self.oam[addr - 0xFE00] = val,
            0xFF40 => self.lcdc = @bitCast(val),
            0xFF41 => self.stat = @bitCast((val & 0x78) + self.stat.mode + (@as(u8, if (self.stat.lyc_eq_ly) 1 else 0) << 2)),
            0xFF42 => self.scy = val,
            0xFF43 => self.scx = val,
            0xFF44 => {},
            0xFF45 => {
                self.lyc = val;

                if (self.lyc == self.ly) {
                    self.stat.lyc_eq_ly = true;
                }
                if (self.stat_int_line == false and self.stat.lyc_int and self.stat.lyc_eq_ly) {
                    self.stat_interrupt.* = true;
                    self.stat_int_line = true;
                }
            },
            0xFF47 => self.bgp = val,
            0xFF48 => self.obp0 = val,
            0xFF49 => self.obp1 = val,
            0xFF4A => self.wy = val,
            0xFF4B => self.wx = val,
            else => {
                return MemoryError.WriteNotAllowed;
            },
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

    fn loadSpriteBuffer(self: *Self) !void {
        self.sprite_buffer.clearRetainingCapacity();

        for (0..40) |i| {
            const sprite_bytes = self.oam[4 * i .. 4 * i + 4];
            const sprite_data = std.mem.bytesAsValue(SpriteData, sprite_bytes);

            const sprite_height: u8 = if (self.lcdc.obj_size) 16 else 8;

            if (sprite_data.x > 0 and (self.ly + 16) >= sprite_data.y and (self.ly + 16) < sprite_data.y + sprite_height and self.sprite_buffer.items.len < 10) {
                try self.sprite_buffer.append(Sprite{
                    .position = i,
                    .data = sprite_data.*,
                });
            }
        }
    }

    fn getSpritePixels(self: *Self, buf: []u2, sprite: *const Sprite) void {
        const offset = 2 * ((@as(u16, self.ly) -% @as(u16, sprite.data.y)) % 8);

        var tile_idx = sprite.data.tile_idx;
        if (self.lcdc.obj_size) {
            var top = (@as(u16, self.ly) + 16 -% @as(u16, sprite.data.y)) < 8;
            if (sprite.data.y_flip) {
                top = !top;
            }
            tile_idx = if (top) sprite.data.tile_idx & 0xfe else sprite.data.tile_idx | 0x01;
        }

        var tile_addr = 0x8000 + 16 * @as(u16, tile_idx);

        if (sprite.data.y_flip) {
            tile_addr += 14 - offset;
        } else {
            tile_addr += offset;
        }

        const low = self.read(tile_addr);
        const high = self.read(tile_addr + 1);

        for (0..8) |i| {
            if (i >= buf.len) {
                break;
            }

            const exp: u3 = @truncate(i);

            const mask = if (sprite.data.x_flip) std.math.pow(u8, 2, exp) else std.math.pow(u8, 2, 7 - exp);
            var val: u2 = 0;
            if (high & mask == mask) {
                val += 2;
            }
            if (low & mask == mask) {
                val += 1;
            }

            const color = self.getColor(&sprite.data, val);

            if (val == 0) {
                continue;
            }

            if (sprite.data.priority) {
                if (buf[i] != 0) {
                    continue;
                }
            }

            buf[i] = color;
        }
    }

    fn getColor(self: *Self, sprite: *const SpriteData, color_id: u2) u2 {
        const palette = if (sprite.dmg_palette == 1) self.obp1 else self.obp0;
        return switch (color_id) {
            0 => @truncate(palette),
            1 => @truncate(palette >> 2),
            2 => @truncate(palette >> 4),
            3 => @truncate(palette >> 6),
        };
    }

    pub fn tick(self: *Self, ticks: usize) !void {
        if (!self.lcdc.lcd_enable) {
            return;
        }

        var stat_ints = STATInts.new();
        self.cycles += ticks;

        switch (self.stat.mode) {
            2 => {
                stat_ints.mode2 = self.stat.mode2_int;
                if (self.cycles >= 80) {
                    self.cycles -= 80;

                    try self.loadSpriteBuffer();

                    self.stat.mode = 3;
                }
            },
            3 => {
                if (self.cycles >= 172) {
                    self.cycles -= 172;

                    var line_buffer: [160]u2 = [_]u2{0} ** 160;

                    if (self.lcdc.bg_enable) {
                        var bg_to_skip: usize = self.scx % 8;
                        var bg_counter: usize = 0;

                        bg: for (0..21) |i| {
                            const lx: u16 = @truncate(i);
                            const x: u16 = ((self.scx / 8) + lx) & 0x1F;
                            const y: u16 = ((@as(u16, self.scy) + @as(u16, self.ly)) & 0xFF) / 8;

                            const tile_map_bank: u16 = if (self.lcdc.bg_tile_map_select) 0x9c00 else 0x9800;
                            const tile_map_addr: u16 = tile_map_bank + y * 32 + x;
                            const tile_number = self.read(tile_map_addr);

                            var tile_data_addr: u16 = 0;
                            if (self.lcdc.tile_data_select) {
                                tile_data_addr = 0x8000 + 16 * @as(u16, tile_number);
                            } else {
                                tile_data_addr = 0x9000;
                                tile_data_addr += 16 * ((@as(u16, tile_number) ^ 0x80));
                                tile_data_addr -= 16 * 128;
                            }

                            tile_data_addr += 2 * ((@as(u16, self.ly) + @as(u16, self.scy)) % 8);

                            const low = self.read(tile_data_addr);
                            const high = self.read(tile_data_addr + 1);

                            for (0..8) |j| {
                                if (bg_to_skip > 0) {
                                    bg_to_skip -= 1;
                                    continue;
                                }

                                const exp: u3 = @truncate(j);
                                const mask = std.math.pow(u8, 2, 7 - exp);
                                var val: u2 = 0;
                                if (high & mask == mask) {
                                    val += 2;
                                }
                                if (low & mask == mask) {
                                    val += 1;
                                }

                                line_buffer[bg_counter] = val;
                                bg_counter += 1;
                                if (bg_counter == 160) {
                                    break :bg;
                                }
                            }
                        }

                        var had_window = false;
                        for (0..20) |i| {
                            if (!self.lcdc.window_enable) break;

                            const pos_y = @as(u16, self.ly);
                            if ((pos_y < self.wy) or (pos_y > @as(u16, self.wy) + 256)) {
                                continue;
                            }

                            const pos_x: u16 = @intCast(i * 8);
                            if ((pos_x < self.wx - 7) or (pos_x > @as(u16, self.wx) + 249)) {
                                continue;
                            }

                            const lx: u16 = @truncate(i);
                            const x: u16 = lx - ((self.wx - 7)) / 8;
                            const y: u16 = self.window_line_counter / 8;

                            const tile_map_bank: u16 = if (self.lcdc.window_tile_map) 0x9c00 else 0x9800;

                            const tile_map_addr: u16 = tile_map_bank + y * 32 + x;
                            const tile_number = self.read(tile_map_addr);

                            var tile_data_addr: u16 = 0;
                            if (self.lcdc.tile_data_select) {
                                tile_data_addr = 0x8000 + 16 * @as(u16, tile_number);
                            } else {
                                tile_data_addr = 0x9000;
                                tile_data_addr += 16 * ((@as(u16, tile_number) ^ 0x80));
                                tile_data_addr -= 16 * 128;
                            }

                            tile_data_addr += 2 * (self.window_line_counter % 8);

                            const low = self.read(tile_data_addr);
                            const high = self.read(tile_data_addr + 1);

                            for (0..8) |j| {
                                const exp: u3 = @truncate(j);
                                const mask = std.math.pow(u8, 2, 7 - exp);
                                var val: u2 = 0;
                                if (high & mask == mask) {
                                    val += 2;
                                }
                                if (low & mask == mask) {
                                    val += 1;
                                }

                                had_window = true;
                                line_buffer[pos_x + j] = val;
                            }
                        }

                        if (had_window) {
                            self.window_line_counter += 1;
                        }
                    }

                    if (self.lcdc.obj_enable) {
                        var used_sprites: [160]usize = [_]usize{40} ** 160;

                        for (self.sprite_buffer.items) |sprite| {
                            if (sprite.data.x >= 168 or sprite.data.x < 8) {
                                continue;
                            }

                            if (used_sprites[sprite.data.x - 8] < sprite.position) {
                                continue;
                            }

                            used_sprites[sprite.data.x - 8] = sprite.position;

                            self.getSpritePixels(line_buffer[sprite.data.x - 8 ..], &sprite);
                        }
                    }

                    for (line_buffer, 0..) |val, x| {
                        self.lcd.push_pixel(val, x, self.ly);
                    }

                    self.stat.mode = 0;
                }
            },
            0 => {
                stat_ints.mode0 = self.stat.mode0_int;
                if (self.cycles >= 204) {
                    self.cycles -= 204;

                    self.ly += 1;
                    if (self.ly < 144) {
                        self.stat.mode = 2;
                    } else {
                        try self.lcd.render();
                        self.window_line_counter = 0;
                        self.stat.mode = 1;
                        self.vblank_interrupt.* = true;
                    }
                }
            },
            1 => {
                stat_ints.mode1 = self.stat.mode1_int;
                if (self.cycles >= 456) {
                    self.cycles -= 456;
                    self.ly = (self.ly + 1) % 154;

                    if (self.ly == 0) {
                        self.stat.mode = 2;
                    }
                }
            },
        }

        self.stat.lyc_eq_ly = self.ly == self.lyc;
        if (self.stat.lyc_int and self.stat.lyc_eq_ly) stat_ints.lyc = true;

        const any_stat_int = stat_ints.any();
        if (self.stat_int_line == false and any_stat_int) {
            self.stat_interrupt.* = true;
        }
        self.stat_int_line = any_stat_int;
    }
};

pub const LCD = struct {
    alloc: std.mem.Allocator,

    framebuffer: [width * height]Color,

    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,

    cpu: ?*CPU,

    const Self = @This();
    const width = 200;
    const height = 144;

    const Color = packed struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };

    pub fn new(alloc: std.mem.Allocator) !*LCD {
        const scale = 5;

        const lcd = try alloc.create(LCD);
        lcd.alloc = alloc;
        lcd.framebuffer = undefined;
        lcd.cpu = null;

        const window_opt = c.SDL_CreateWindow("GameZigBoy", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, width * scale, height * scale, 0);
        if (window_opt == null) {
            return DisplayError.InitFailed;
        }

        lcd.window = window_opt.?;

        lcd.renderer = c.SDL_CreateRenderer(lcd.window, -1, c.SDL_RENDERER_ACCELERATED).?;

        const texture_opt = c.SDL_CreateTexture(lcd.renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STREAMING, width, height);
        if (texture_opt == null) {
            return DisplayError.InitFailed;
        }

        lcd.texture = texture_opt.?;

        if (c.SDL_RenderSetScale(lcd.renderer, scale, scale) != 0) {
            return DisplayError.InitFailed;
        }

        return lcd;
    }

    pub fn setFullscreen(self: *Self) !void {
        var dm: c.SDL_DisplayMode = undefined;

        if (c.SDL_GetDesktopDisplayMode(0, &dm) != 0) {
            return DisplayError.InitFailed;
        }

        const w_scale: f32 = @floatFromInt(@divTrunc(dm.w, width));
        const h_scale: f32 = @floatFromInt(@divTrunc(dm.h, height));

        const scale = if (w_scale > h_scale) h_scale else w_scale;

        if (c.SDL_SetWindowFullscreen(self.window, c.SDL_WINDOW_FULLSCREEN_DESKTOP) != 0) {
            return DisplayError.InitFailed;
        }
        if (c.SDL_RenderSetScale(self.renderer, scale, scale) != 0) {
            return DisplayError.InitFailed;
        }
    }

    pub fn setWindowMode(self: *Self) !void {
        const scale = 5;

        c.SDL_SetWindowSize(self.window, width * scale, height * scale);

        if (c.SDL_RenderSetScale(self.renderer, scale, scale) != 0) {
            return DisplayError.InitFailed;
        }
    }

    pub fn push_pixel(self: *Self, pixel: u2, x: usize, y: usize) void {
        self.framebuffer[y * width + x] = switch (pixel) {
            0 => Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
            1 => Color{ .r = 160, .g = 160, .b = 160, .a = 255 },
            2 => Color{ .r = 80, .g = 80, .b = 80, .a = 255 },
            3 => Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
        };
    }

    pub fn render(self: *Self) !void {
        var x_scale: f32 = undefined;
        var y_scale: f32 = undefined;
        var window_width: i32 = undefined;
        var window_height: i32 = undefined;

        c.SDL_RenderGetScale(self.renderer, &x_scale, &y_scale);
        c.SDL_GetWindowSize(self.window, &window_width, &window_height);

        const x_shift: i32 = @intFromFloat((@as(f32, @floatFromInt(window_width)) - (@as(f32, @floatFromInt(width)) * x_scale)) / (2 * x_scale));
        _ = c.SDL_RenderSetViewport(self.renderer, &c.SDL_Rect{ .x = x_shift, .y = 0, .w = width, .h = height });

        const rect = c.SDL_Rect{
            .x = 0,
            .y = 0,
            .w = width,
            .h = height,
        };

        const ptr: *anyopaque = @ptrCast(@alignCast(&self.framebuffer));
        _ = c.SDL_UpdateTexture(self.texture, &rect, ptr, 800);
        _ = c.SDL_RenderCopy(self.renderer, self.texture, null, &rect);

        const font = c.TTF_OpenFont("/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf", 24).?;

        if (self.cpu != null) {
            var buf = [_]u8{0} ** 64;
            {
                _ = try std.fmt.bufPrintZ(&buf, "A:{x}", .{self.cpu.?.a()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 0, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "F:{x}", .{self.cpu.?.f()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 10, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "B:{x}", .{self.cpu.?.b()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 20, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "C:{x}", .{self.cpu.?.c()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 30, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "D:{x}", .{self.cpu.?.d()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 40, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "E:{x}", .{self.cpu.?.e()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 50, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "H:{x}", .{self.cpu.?.h()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 60, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "L:{x}", .{self.cpu.?.l()});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 70, .w = 20, .h = 8 });
            }

            {
                _ = try std.fmt.bufPrintZ(&buf, "PC:{x}", .{self.cpu.?.pc});
                const surface = c.TTF_RenderText_Solid(font, &buf, c.SDL_Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
                const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface);
                _ = c.SDL_RenderCopy(self.renderer, texture, null, &c.SDL_Rect{ .x = 160, .y = 80, .w = 20, .h = 8 });
            }
        }

        c.SDL_RenderPresent(self.renderer);
    }

    pub fn deinit(self: *Self) void {
        self.alloc.destroy(self);
    }
};
