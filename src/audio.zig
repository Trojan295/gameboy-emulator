const std = @import("std");
const AudioError = @import("errors.zig").AudioError;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_mixer.h");
});

pub const Audio = struct {
    alloc: std.mem.Allocator,
    audio_dev_id: c.SDL_AudioDeviceID,
    buffer: [1024]f32,
    buf_pos: usize,

    ch1: Channel1,
    ch2: Channel2,
    ch3: Channel3,
    ch4: Channel4,

    cycles: u13,
    sample_counter: usize,
    length_timer: u1,

    nr50: NR50,
    nr51: NR51,
    nr52: NR52,

    ch1_running: bool,
    ch1_timer: u6,

    const Self = @This();

    const NR50 = packed struct {
        right_volume: u3,
        vin_right: bool,
        left_volume: u3,
        vin_left: bool,
    };
    const NR51 = packed struct {
        ch1_right: bool,
        ch2_right: bool,
        ch3_right: bool,
        ch4_right: bool,
        ch1_left: bool,
        ch2_left: bool,
        ch3_left: bool,
        ch4_left: bool,
    };
    const NR52 = packed struct {
        _n: u7,
        audio_on: bool,
    };
    pub fn new(alloc: std.mem.Allocator) !*Self {
        const spec = c.SDL_AudioSpec{
            .freq = 44150,
            .format = c.AUDIO_F32,
            .channels = 1,
            .samples = 1024,
        };

        var obt = c.SDL_AudioSpec{};
        const dev_id = c.SDL_OpenAudioDevice(null, 0, @constCast(&spec), &obt, c.SDL_AUDIO_ALLOW_ANY_CHANGE);
        if (dev_id < 0) {
            return AudioError.CannotPlay;
        }

        c.SDL_PauseAudioDevice(dev_id, 0);

        const audio: *Audio = try alloc.create(Audio);
        audio.* = Audio{
            .alloc = alloc,
            .audio_dev_id = dev_id,
            .buffer = undefined,
            .buf_pos = 0,

            .nr50 = @bitCast(@as(u8, 0)),
            .nr51 = @bitCast(@as(u8, 0)),
            .nr52 = @bitCast(@as(u8, 0)),

            .ch1 = Channel1.new(),
            .ch2 = Channel2.new(),
            .ch3 = Channel3.new(),
            .ch4 = Channel4.new(),

            .cycles = 0,
            .length_timer = 0,
            .sample_counter = 0,

            .ch1_running = false,
            .ch1_timer = 0,
        };

        return audio;
    }

    pub fn tick(self: *Self, ticks: usize) void {
        self.ch1.tick(ticks);
        self.ch2.tick(ticks);
        self.ch3.tick(ticks);
        self.ch4.tick(ticks);

        self.sample_counter += ticks;
        if (self.sample_counter >= 95) {
            self.sample_counter -= 95;

            const sample = (self.ch1.getSample() + self.ch2.getSample() + self.ch3.getSample() + self.ch4.getSample()) / 4;
            self.buffer[self.buf_pos] = sample;
            self.buf_pos += 1;

            if (self.buf_pos == self.buffer.len) {
                self.buf_pos = 0;
                // TODO: is this a good way...?
                c.SDL_ClearQueuedAudio(self.audio_dev_id);
                _ = c.SDL_QueueAudio(self.audio_dev_id, &self.buffer, self.buffer.len * 4);
            }
        }

        self.cycles, const cycle_of = @addWithOverflow(self.cycles, @as(u13, @intCast(ticks)));
        if (cycle_of == 0) {
            return;
        }
    }

    fn getPeriod(self: *Self) u11 {
        return self.nr13 + (@as(u11, @intCast(self.nr14.period)) << 8);
    }

    fn setPeriod(self: *Self, period: u11) void {
        self.nr13 = @truncate(period);
        self.nr14.period = @truncate(period >> 8);
    }

    pub fn read(self: *Self, addr: u16) u8 {
        const val: u8 = switch (addr) {
            0xff10 => @as(u8, self.ch1.period_step) + (@as(u8, self.ch1.period_pace) << 4) + boolToInt(self.ch1.period_direction, 3) + 0x80,
            0xff11 => 0x3f + (@as(u8, self.ch1.duty) << 6),
            0xff12 => @as(u8, self.ch1.env_sweep_pace) + boolToInt(self.ch1.env_dir, 3) + (@as(u8, self.ch1.initial_volume) << 4),
            0xff13 => 0xff,
            0xff14 => 0xbf + boolToInt(self.ch1.length_enable, 6),

            0xff16 => 0x3f + (@as(u8, self.ch2.duty) << 6),
            0xff17 => @as(u8, self.ch2.env_sweep_pace) + boolToInt(self.ch2.env_dir, 3) + (@as(u8, self.ch2.initial_volume) << 4),
            0xff18 => 0xff,
            0xff19 => 0xbf + boolToInt(self.ch2.length_enable, 6),

            0xff1a => 0x7f + boolToInt(self.ch3.dac_on, 7),
            0xff1b => 0xff,
            0xff1c => 0x9f + (@as(u8, self.ch3.output_level) << 5),
            0xff1d => 0xff,
            0xff1e => 0xbf + boolToInt(self.ch3.length_enable, 6),

            0xff20 => 0xff,
            0xff21 => @as(u8, self.ch4.env_sweep_pace) + boolToInt(self.ch4.env_dir, 3) + (@as(u8, self.ch4.initial_volume) << 4),
            0xff22 => @as(u8, self.ch4.clock_divider) + boolToInt(self.ch4.lfsr_width, 3) + (@as(u8, self.ch4.clock_shift) << 4),
            0xff23 => 0xbf + boolToInt(self.ch4.length_enable, 6),

            0xff24 => @bitCast(self.nr50),
            0xff25 => @bitCast(self.nr51),
            0xff26 => @as(u8, @bitCast(self.nr52)) + 0x70 + boolToInt(self.ch1.running, 0) + boolToInt(self.ch2.running, 1) + boolToInt(self.ch3.running, 2) + boolToInt(self.ch4.running, 3),

            0xff30...0xff3f => self.ch3.wave[addr - 0xff30],
            else => 0xff,
        };

        //std.debug.print("audio read {x}: {x}\n", .{ addr, val });

        return val;
    }

    fn boolToInt(b: bool, comptime pow: u3) u8 {
        return if (b) (1 << pow) else 0;
    }

    pub fn write(self: *Self, addr: u16, val: u8) void {
        if (!self.nr52.audio_on and addr != 0xff26) {
            return;
        }

        //std.debug.print("audio write {x}: {x}\n", .{ addr, val });

        switch (addr) {
            0xff10 => {
                self.ch1.period_step = @truncate(val);
                self.ch1.period_direction = val & 0x8 == 0x8;
                self.ch1.period_pace = @truncate(val >> 4);
            },
            0xff11 => {
                const time: u6 = @truncate(val);

                self.ch1.initial_timer_length = time;
                if (self.ch1.running) self.ch1.length = time;
                self.ch1.duty = @truncate(val >> 6);
            },
            0xff12 => {
                self.ch1.env_sweep_pace = @truncate(val);
                self.ch1.env_dir = val & 0x8 == 0x8;
                self.ch1.initial_volume = @truncate(val >> 4);
            },
            0xff13 => {
                self.ch1.period = (self.ch1.period & 0x700) + val;
            },
            0xff14 => {
                self.ch1.period = (@as(u11, val & 0x7) << 8) + (self.ch1.period & 0xff);
                self.ch1.length_enable = val & 0x40 == 0x40;
                if (val & 0x80 == 0x80) {
                    self.ch1.trigger();
                }
            },
            0xff16 => {
                self.ch2.initial_timer_length = @truncate(val);
                self.ch2.duty = @truncate(val >> 6);
            },
            0xff17 => {
                self.ch2.env_sweep_pace = @truncate(val);
                self.ch2.env_dir = val & 0x8 == 0x8;
                self.ch2.initial_volume = @truncate(val >> 4);
            },
            0xff18 => {
                self.ch2.period = (self.ch2.period & 0x700) + val;
            },
            0xff19 => {
                self.ch2.period = (@as(u11, val & 0x7) << 8) + (self.ch2.period & 0xff);
                self.ch2.length_enable = val & 0x40 == 0x40;
                if (val & 0x80 == 0x80) {
                    self.ch2.trigger();
                }
            },
            0xff1a => {
                self.ch3.dac_on = val & 0x80 == 0x80;
            },
            0xff1b => {
                self.ch3.initial_timer_length = val;
            },
            0xff1c => {
                self.ch3.output_level = @truncate(val >> 5);
            },
            0xff1d => {
                self.ch3.period = (self.ch3.period & 0x700) + val;
            },
            0xff1e => {
                self.ch3.period = (@as(u11, val & 0x7) << 8) + (self.ch3.period & 0xff);
                self.ch3.length_enable = val & 0x40 == 0x40;
                if (val & 0x80 == 0x80) {
                    self.ch3.trigger();
                }
            },
            0xff20 => {
                self.ch4.initial_timer_length = @truncate(val);
            },
            0xff21 => {
                self.ch4.env_sweep_pace = @truncate(val);
                self.ch4.env_dir = val & 0x8 == 0x8;
                self.ch4.initial_volume = @truncate(val >> 4);
            },
            0xff22 => {
                self.ch4.clock_divider = @truncate(val);
                self.ch4.lfsr_width = val & 0x08 == 0x08;
                self.ch4.clock_shift = @truncate(val >> 4);
            },
            0xff23 => {
                self.ch4.length_enable = val & 0x40 == 0x40;
                if (val & 0x80 == 0x80) self.ch4.trigger();
            },
            0xff24 => self.nr50 = @bitCast(val),
            0xff25 => self.nr51 = @bitCast(val),
            0xff26 => {
                if (val & 0x80 == 0x80) {
                    self.nr52.audio_on = true;
                } else {
                    for (0xff10..0xff26) |a| {
                        self.write(@truncate(a), 0);
                    }

                    self.nr52.audio_on = false;
                }
            },

            0xff30...0xff3f => self.ch3.wave[addr - 0xff30] = val,

            else => {},
        }
    }
};

const Channel1 = struct {
    ticks: usize,
    running: bool,

    period_pace: u3,
    period_direction: bool,
    period_step: u3,
    duty: u2,
    initial_timer_length: u6,
    initial_volume: u4,
    env_dir: bool,
    env_sweep_pace: u3,
    period: u11,
    length_enable: bool,

    length_divider: u14,
    length: u6,
    period_divider: u11,

    period_sweep_divider: u15,
    period_sweep_counter: u3,

    volume: u4,
    env_divider: u16,

    ptr: u3,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .period_pace = 0,
            .period_direction = false,
            .period_step = 0,
            .duty = 0,
            .initial_timer_length = 0,
            .initial_volume = 0,
            .env_dir = false,
            .env_sweep_pace = 0,
            .period = 0,
            .length_enable = false,

            .length = 0,
            .length_divider = 0,
            .period_divider = 0,

            .period_sweep_divider = 0,
            .period_sweep_counter = 0,

            .env_divider = 0,
            .volume = 0,

            .ptr = 0,
        };
    }

    fn tick(self: *Self, ticks: usize) void {
        self.ticks += ticks;
        while (self.ticks >= 4) {
            self.ticks -= 4;

            self.period_divider, const of = @addWithOverflow(self.period_divider, 1);
            if (of > 0) {
                self.period_divider = self.period;
                self.ptr +%= 1;
            }
        }

        {
            self.period_sweep_divider, const of = @addWithOverflow(self.period_sweep_divider, @as(u15, @intCast(ticks)));
            if (of > 0 and self.period_pace > 0) {
                self.period_sweep_counter, const lof = @subWithOverflow(self.period_sweep_counter, 1);
                if (lof > 0) {
                    self.period_sweep_counter = self.period_pace;
                    const delta: u11 = @intFromFloat(@as(f32, @floatFromInt(self.period)) / std.math.pow(f32, 2, @floatFromInt(self.period_step)));
                    if (self.period_direction) {
                        self.period -= delta;
                    } else {
                        self.period, const dof = @addWithOverflow(self.period, delta);
                        if (dof > 0) {
                            self.period_pace = 0;
                        }
                    }
                }
            }
        }

        {
            self.env_divider, const of = @addWithOverflow(self.env_divider, @as(u16, @intCast(ticks)));
            if (of > 0) {
                if (self.env_dir) {
                    if (self.volume != 15) self.volume += 1;
                } else {
                    if (self.volume != 0) self.volume -= 1;
                }
            }
        }

        self.length_divider, const of = @addWithOverflow(self.length_divider, @as(u14, @intCast(ticks)));
        if (of > 0 and self.length_enable and self.running) {
            self.length, const lof = @addWithOverflow(self.length, 1);
            std.debug.print("length: {}\n", .{self.length});
            if (lof > 0) {
                std.debug.print("overflow\n", .{});
                self.running = false;
            }
        }
    }

    fn trigger(self: *Self) void {
        self.period_divider = self.period;
        self.volume = self.initial_volume;
        self.length = self.initial_timer_length;
        self.running = true;
    }

    fn getSample(self: *Self) f32 {
        if (!self.running) {
            return 0;
        }

        const volume: f32 = (@as(f32, @floatFromInt(self.volume)) / 16);
        const wave: f32 = switch (self.duty) {
            0 => if (self.ptr < 7) 1 else -1,
            1 => if (self.ptr < 6) 1 else -1,
            2 => if (self.ptr < 4) 1 else -1,
            3 => if (self.ptr < 2) 1 else -1,
        };

        return volume * wave;
    }
};

const Channel2 = struct {
    ticks: usize,
    running: bool,

    duty: u2,
    initial_timer_length: u6,
    initial_volume: u4,
    env_dir: bool,
    env_sweep_pace: u3,
    period: u11,
    length_enable: bool,

    length_divider: u14,
    length: u6,
    period_divider: u11,
    volume: u4,
    env_divider: u16,

    ptr: u3,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .duty = 0,
            .initial_timer_length = 0,
            .initial_volume = 0,
            .env_dir = false,
            .env_sweep_pace = 0,
            .period = 0,
            .length_enable = false,

            .length_divider = 0,
            .length = 0,
            .period_divider = 0,
            .env_divider = 0,
            .volume = 0,

            .ptr = 0,
        };
    }

    fn tick(self: *Self, ticks: usize) void {
        self.ticks += ticks;
        while (self.ticks >= 4) {
            self.ticks -= 4;

            self.period_divider, const of = @addWithOverflow(self.period_divider, 1);
            if (of > 0) {
                self.period_divider = self.period;
                self.ptr +%= 1;
            }
        }

        {
            self.env_divider, const of = @addWithOverflow(self.env_divider, @as(u16, @intCast(ticks)));
            if (of > 0) {
                if (self.env_dir) {
                    if (self.volume != 15) self.volume += 1;
                } else {
                    if (self.volume != 0) self.volume -= 1;
                }
            }
        }

        if (self.length_enable) {
            self.length_divider, const of = @addWithOverflow(self.length_divider, @as(u14, @intCast(ticks)));
            if (of > 0) {
                self.length, const lof = @addWithOverflow(self.length, 1);
                if (lof > 0) {
                    self.running = false;
                }
            }
        }
    }

    fn trigger(self: *Self) void {
        self.period_divider = self.period;
        self.length = self.initial_timer_length;
        self.running = true;
    }

    fn getSample(self: *Self) f32 {
        if (!self.running) {
            return 0;
        }

        const volume: f32 = (@as(f32, @floatFromInt(self.initial_volume)) / 16);
        const wave: f32 = switch (self.duty) {
            0 => if (self.ptr < 7) 1 else -1,
            1 => if (self.ptr < 6) 1 else -1,
            2 => if (self.ptr < 4) 1 else -1,
            3 => if (self.ptr < 2) 1 else -1,
        };

        return volume * wave;
    }
};

const Channel3 = struct {
    ticks: usize,
    running: bool,

    dac_on: bool,
    initial_timer_length: u8,
    output_level: u2,
    period: u11,
    length_enable: bool,

    length_divider: u14,
    length: u8,
    period_divider: u11,

    ptr: u4,
    wave: [16]u8,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .dac_on = false,
            .initial_timer_length = 0,
            .output_level = 0,
            .period = 0,
            .length_enable = false,

            .length_divider = 0,
            .length = 0,
            .period_divider = 0,

            .ptr = 0,
            .wave = undefined,
        };
    }

    fn tick(self: *Self, ticks: usize) void {
        self.ticks += ticks;
        while (self.ticks >= 4) {
            self.ticks -= 4;

            self.period_divider, const of = @addWithOverflow(self.period_divider, 1);
            if (of > 0) {
                self.period_divider = self.period;
                self.ptr +%= 1;
            }
        }

        if (self.length_enable) {
            self.length_divider, const of = @addWithOverflow(self.length_divider, @as(u14, @intCast(ticks)));
            if (of > 0) {
                self.length, const lof = @addWithOverflow(self.length, 1);
                if (lof > 0) {
                    self.running = false;
                }
            }
        }
    }

    fn trigger(self: *Self) void {
        self.period_divider = self.period;
        self.length = self.initial_timer_length;
        self.running = true;
    }

    fn getSample(self: *Self) f32 {
        if (!self.running) {
            return 0;
        }

        const volume: f32 = (@as(f32, @floatFromInt(self.output_level)) / 16);
        const wave: f32 = @as(f32, @floatFromInt(self.wave[self.ptr])) / 255;

        return volume * wave;
    }
};

const Channel4 = struct {
    ticks: usize,
    running: bool,

    initial_timer_length: u6,
    clock_shift: u4,
    lfsr_width: bool,
    clock_divider: u3,
    length_enable: bool,
    initial_volume: u4,
    env_dir: bool,
    env_sweep_pace: u3,

    volume: u4,
    env_divider: u16,

    length_divider: u14,
    length: u6,

    lfsr: u16,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .initial_timer_length = 0,
            .clock_shift = 0,
            .lfsr_width = false,
            .clock_divider = 0,
            .length_enable = false,
            .initial_volume = 0,
            .env_dir = false,
            .env_sweep_pace = 0,

            .env_divider = 0,
            .volume = 0,

            .length_divider = 0,
            .length = 0,

            .lfsr = 0,
        };
    }

    fn tick(self: *Self, ticks: usize) void {
        {
            self.env_divider, const of = @addWithOverflow(self.env_divider, @as(u16, @intCast(ticks)));
            if (of > 0) {
                if (self.env_dir) {
                    if (self.volume != 15) self.volume += 1;
                } else {
                    if (self.volume != 0) self.volume -= 1;
                }
            }
        }

        if (self.length_enable) {
            self.length_divider, const of = @addWithOverflow(self.length_divider, @as(u14, @intCast(ticks)));
            if (of > 0) {
                self.length, const lof = @addWithOverflow(self.length, 1);
                if (lof > 0) {
                    self.running = false;
                }
            }
        }
    }

    fn trigger(self: *Self) void {
        self.length = self.initial_timer_length;
        self.lfsr = 1;
        self.running = true;
    }

    fn getSample(self: *Self) f32 {
        if (!self.running) {
            return 0;
        }

        return if (self.lfsr & 0x01 == 0x01) @as(f32, @floatFromInt(self.volume)) / 15 else 0;
    }
};
