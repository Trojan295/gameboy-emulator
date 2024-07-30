// TODO: move the reads/writes to the Channel structs

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
        if (self.sample_counter >= 96) {
            self.sample_counter -= 96;

            var sample: f32 = 0;
            sample += self.ch1.getSample() / 4;
            sample += self.ch2.getSample() / 4;
            sample += self.ch3.getSample() / 4;
            sample += self.ch4.getSample() / 4;

            self.buffer[self.buf_pos] = sample / 4;
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
            0xff10 => @as(u8, self.ch1.sweep_shift) + (@as(u8, self.ch1.sweep_period) << 4) + boolToInt(self.ch1.sweep_direction, 3) + 0x80,
            0xff11 => 0x3f + (@as(u8, self.ch1.duty) << 6),
            0xff12 => @as(u8, self.ch1.env_period) + boolToInt(self.ch1.env_dir, 3) + (@as(u8, self.ch1.initial_volume) << 4),
            0xff13 => 0xff,
            0xff14 => 0xbf + boolToInt(self.ch1.length_enable, 6),

            0xff16 => 0x3f + (@as(u8, self.ch2.duty) << 6),
            0xff17 => @as(u8, self.ch2.env_period) + boolToInt(self.ch2.env_dir, 3) + (@as(u8, self.ch2.initial_volume) << 4),
            0xff18 => 0xff,
            0xff19 => 0xbf + boolToInt(self.ch2.length_enable, 6),

            0xff1a => 0x7f + boolToInt(self.ch3.dac_on, 7),
            0xff1b => 0xff,
            0xff1c => 0x9f + (@as(u8, self.ch3.output_level) << 5),
            0xff1d => 0xff,
            0xff1e => 0xbf + boolToInt(self.ch3.length_enable, 6),

            0xff20 => 0xff,
            0xff21 => @as(u8, self.ch4.env_period) + boolToInt(self.ch4.env_dir, 3) + (@as(u8, self.ch4.initial_volume) << 4),
            0xff22 => @as(u8, self.ch4.clock_divider) + boolToInt(self.ch4.lfsr_width, 3) + (@as(u8, self.ch4.clock_shift) << 4),
            0xff23 => 0xbf + boolToInt(self.ch4.length_enable, 6),

            0xff24 => @bitCast(self.nr50),
            0xff25 => @bitCast(self.nr51),
            0xff26 => @as(u8, @bitCast(self.nr52)) + 0x70 + boolToInt(self.ch1.isRunning(), 0) + boolToInt(self.ch2.isRunning(), 1) + boolToInt(self.ch3.isRunning(), 2) + boolToInt(self.ch4.isRunning(), 3),

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
        //std.debug.print("audio write {x}: {x}\n", .{ addr, val });

        if (!self.nr52.audio_on and addr != 0xff26) {
            return;
        }

        switch (addr) {
            0xff10 => {
                self.ch1.sweep_shift = @truncate(val);
                self.ch1.sweep_direction = val & 0x8 == 0x8;
                self.ch1.sweep_period = @truncate(val >> 4);
            },
            0xff11 => {
                self.ch1.length = @truncate(val & 0x3f);
                self.ch1.duty = @truncate(val >> 6);
            },
            0xff12 => {
                self.ch1.env_period = @truncate(val);
                self.ch1.env_dir = val & 0x8 == 0x8;
                self.ch1.initial_volume = @truncate(val >> 4);
                if (!self.ch1.dacEnabled()) {
                    self.ch1.running = false;
                }
            },
            0xff13 => {
                self.ch1.period = (self.ch1.period & 0x700) + val;
            },
            0xff14 => {
                self.ch1.period = (@as(u11, val & 0x7) << 8) + (self.ch1.period & 0xff);
                const enable_length = val & 0x40 == 0x40;
                const trigger = val & 0x80 == 0x80;

                if (enable_length and !self.ch1.length_enable and !self.ch1.frame_sequencer.nextClocks().length and self.ch1.length != 64) {
                    self.ch1.length += 1;
                    if (self.ch1.length == 64) {
                        self.ch1.running = false;
                    }
                }

                if (trigger) {
                    self.ch1.trigger(enable_length);
                }

                self.ch1.length_enable = enable_length;
            },
            0xff16 => {
                self.ch2.length = @truncate(val & 0x3f);
                self.ch2.duty = @truncate(val >> 6);
            },
            0xff17 => {
                self.ch2.env_period = @truncate(val);
                self.ch2.env_dir = val & 0x8 == 0x8;
                self.ch2.initial_volume = @truncate(val >> 4);
                if (!self.ch2.dacEnabled()) {
                    self.ch2.running = false;
                }
            },
            0xff18 => {
                self.ch2.period = (self.ch2.period & 0x700) + val;
            },
            0xff19 => {
                self.ch2.period = (@as(u11, val & 0x7) << 8) + (self.ch2.period & 0xff);
                const enable_length = val & 0x40 == 0x40;
                const trigger = val & 0x80 == 0x80;

                if (enable_length and !self.ch2.length_enable and !self.ch2.frame_sequencer.nextClocks().length and self.ch2.length < 64) {
                    self.ch2.length += 1;
                    if (self.ch2.length == 64) {
                        self.ch2.running = false;
                    }
                }

                if (trigger) {
                    self.ch2.trigger(enable_length);
                }

                self.ch2.length_enable = enable_length;
            },
            0xff1a => {
                self.ch3.dac_on = val & 0x80 == 0x80;
                if (!self.ch3.dac_on) {
                    self.ch3.running = false;
                }
            },
            0xff1b => {
                self.ch3.length = val;
            },
            0xff1c => {
                self.ch3.output_level = @truncate(val >> 5);
            },
            0xff1d => {
                self.ch3.period = (self.ch3.period & 0x700) + val;
            },
            0xff1e => {
                self.ch3.period = (@as(u11, val & 0x7) << 8) + (self.ch3.period & 0xff);
                const enable_length = val & 0x40 == 0x40;
                const trigger = val & 0x80 == 0x80;

                if (enable_length and !self.ch3.length_enable and !self.ch3.frame_sequencer.nextClocks().length and self.ch3.length < 256) {
                    self.ch3.length += 1;
                    if (self.ch3.length == 256) {
                        self.ch3.running = false;
                    }
                }

                if (trigger) {
                    self.ch3.trigger(enable_length);
                }

                self.ch3.length_enable = enable_length;
            },
            0xff20 => {
                self.ch4.length = @truncate(val & 0x3f);
            },
            0xff21 => {
                self.ch4.env_period = @truncate(val);
                self.ch4.env_dir = val & 0x8 == 0x8;
                self.ch4.initial_volume = @truncate(val >> 4);
                if (!self.ch4.dacEnabled()) {
                    self.ch4.running = false;
                }
            },
            0xff22 => {
                self.ch4.clock_divider = @truncate(val);
                self.ch4.lfsr_width = val & 0x08 == 0x08;
                self.ch4.clock_shift = @truncate(val >> 4);
            },
            0xff23 => {
                const enable_length = val & 0x40 == 0x40;
                const trigger = val & 0x80 == 0x80;

                if (enable_length and !self.ch4.length_enable and !self.ch4.frame_sequencer.nextClocks().length and self.ch4.length < 64) {
                    self.ch4.length += 1;
                    if (self.ch4.length == 64) {
                        self.ch4.running = false;
                    }
                }

                if (trigger) {
                    self.ch4.trigger(enable_length);
                }

                self.ch4.length_enable = enable_length;
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

    length_enable: bool,
    length: u7,

    freq_shadow_req: u11,
    sweep_enabled: bool,
    sweep_timer: u3,
    sweep_period: u3,
    sweep_direction: bool,
    sweep_shift: u3,

    duty: u2,

    initial_volume: u4,
    env_dir: bool,
    env_period: u3,
    env_timer: u3,
    volume: u4,

    period: u11,
    period_divider: u11,

    ptr: u3,

    frame_sequencer: FrameSequencer,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .length_enable = false,
            .length = 0,

            .freq_shadow_req = 0,
            .sweep_enabled = false,
            .sweep_timer = 0,

            .sweep_period = 0,
            .sweep_direction = false,
            .sweep_shift = 0,
            .duty = 0,
            .initial_volume = 0,
            .env_dir = false,
            .env_period = 0,
            .env_timer = 0,

            .period = 0,
            .period_divider = 0,

            .volume = 0,

            .ptr = 0,

            .frame_sequencer = FrameSequencer.new(),
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

        const clocks = self.frame_sequencer.tick(ticks);

        if (clocks.sweep and self.sweep_enabled and self.sweep_period > 0) {
            self.sweep_timer, const lof = @subWithOverflow(self.sweep_timer, 1);

            if (lof > 0) {
                self.sweep_timer = self.sweep_period - 1;

                const next_period = self.nextSweepPeriod();

                if (next_period.overflow) {
                    self.running = false;
                } else {
                    if (self.sweep_shift > 0) {
                        self.period = next_period.period;
                        self.freq_shadow_req = next_period.period;

                        if (self.nextSweepPeriod().overflow) self.running = false;
                    }
                }
            }
        }

        if (clocks.vol_env and self.env_period > 0) {
            self.env_timer, const eof = @subWithOverflow(self.env_timer, 1);

            if (eof > 0) {
                self.env_timer = self.env_period - 1;

                if (self.env_dir) {
                    if (self.volume < 15) self.volume += 1;
                } else {
                    if (self.volume > 1) self.volume -= 1;
                }
            }
        }

        if (clocks.length and self.length_enable and self.length < 64) {
            self.length += 1;
            if (self.length == 64) {
                self.running = false;
            }
        }
    }

    fn trigger(self: *Self, enable_length: bool) void {
        if (self.length == 64) {
            const next_len_clock = self.frame_sequencer.nextClocks().length;
            if (enable_length and !next_len_clock) self.length = 1 else self.length = 0;
        }

        self.period_divider = self.period;
        self.volume = self.initial_volume;

        self.freq_shadow_req = self.period;
        self.sweep_enabled = (self.sweep_shift > 0) or (self.sweep_period > 0);
        if (self.sweep_period > 0) self.sweep_timer = self.sweep_period - 1;

        const next_sweep = self.nextSweepPeriod();
        if (self.sweep_shift > 0) {
            if (next_sweep.overflow) return;
            self.period = next_sweep.period;
        }

        if (!self.dacEnabled()) return;

        self.running = true;
    }

    fn nextSweepPeriod(self: *const Self) struct { period: u11, overflow: bool } {
        const delta: u11 = @intFromFloat(@as(f32, @floatFromInt(self.freq_shadow_req)) / std.math.pow(f32, 2, @floatFromInt(self.sweep_shift)));

        if (self.sweep_direction) {
            return .{ .period = self.freq_shadow_req - delta, .overflow = false };
        } else {
            const period, const of = @addWithOverflow(self.freq_shadow_req, delta);
            return .{ .period = period, .overflow = of > 0 };
        }
    }

    fn dacEnabled(self: *Self) bool {
        return !(self.initial_volume == 0 and !self.env_dir);
    }

    fn isRunning(self: *Self) bool {
        return self.dacEnabled() and self.running;
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

    length_enable: bool,
    length: u7,

    duty: u2,

    initial_volume: u4,
    env_dir: bool,
    env_period: u3,
    env_timer: u3,
    volume: u4,

    period: u11,
    period_divider: u11,

    ptr: u3,

    frame_sequencer: FrameSequencer,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .length_enable = false,
            .length = 0,

            .duty = 0,
            .initial_volume = 0,
            .env_dir = false,
            .env_period = 0,
            .env_timer = 0,

            .period = 0,
            .period_divider = 0,

            .volume = 0,

            .ptr = 0,

            .frame_sequencer = FrameSequencer.new(),
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

        const clocks = self.frame_sequencer.tick(ticks);

        if (clocks.vol_env and self.env_period > 0) {
            self.env_timer, const eof = @subWithOverflow(self.env_timer, 1);

            if (eof > 0) {
                self.env_timer = self.env_period - 1;

                if (self.env_dir) {
                    if (self.volume < 15) self.volume += 1;
                } else {
                    if (self.volume > 1) self.volume -= 1;
                }
            }
        }

        if (clocks.length and self.length_enable and self.length < 64) {
            self.length += 1;
            if (self.length == 64) {
                self.running = false;
            }
        }
    }

    fn trigger(self: *Self, enable_length: bool) void {
        if (self.length == 64) {
            const next_len_clock = self.frame_sequencer.nextClocks().length;
            if (enable_length and !next_len_clock) self.length = 1 else self.length = 0;
        }

        self.period_divider = self.period;
        self.volume = self.initial_volume;

        if (!self.dacEnabled()) return;

        self.running = true;
    }

    fn dacEnabled(self: *Self) bool {
        return !(self.initial_volume == 0 and !self.env_dir);
    }

    fn isRunning(self: *Self) bool {
        return self.dacEnabled() and self.running;
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

const Channel3 = struct {
    ticks: usize,
    running: bool,

    dac_on: bool,
    output_level: u2,
    period: u11,
    length_enable: bool,

    length: u9,
    period_divider: u11,

    ptr: u4,
    wave: [16]u8,

    frame_sequencer: FrameSequencer,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .dac_on = false,
            .output_level = 0,
            .period = 0,
            .length_enable = false,

            .length = 0,
            .period_divider = 0,

            .ptr = 0,
            .wave = undefined,

            .frame_sequencer = FrameSequencer.new(),
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

        const clocks = self.frame_sequencer.tick(ticks);

        if (clocks.length and self.length_enable and self.length < 256) {
            self.length += 1;
            if (self.length == 256) {
                self.running = false;
            }
        }
    }

    fn trigger(self: *Self, enable_length: bool) void {
        if (self.length == 256) {
            const next_len_clock = self.frame_sequencer.nextClocks().length;
            if (enable_length and !next_len_clock) self.length = 1 else self.length = 0;
        }

        self.period_divider = self.period;

        if (!self.dac_on) return;

        self.running = true;
    }

    fn isRunning(self: *Self) bool {
        return self.dac_on and self.running;
    }

    fn getSample(self: *Self) f32 {
        if (!self.running) {
            return 0;
        }

        const volume: f32 = switch (self.output_level) {
            0 => 0,
            1 => 1,
            2 => 0.5,
            3 => 0.25,
        };
        const wave: f32 = (@as(f32, @floatFromInt(self.wave[self.ptr])) / 128) - 1;

        return wave * volume;
    }
};

const Channel4 = struct {
    ticks: usize,
    running: bool,

    length_enable: bool,
    length: u7,

    duty: u2,

    initial_volume: u4,
    env_dir: bool,
    env_period: u3,
    env_timer: u3,
    volume: u4,

    clock_divider: u3,
    lfsr_width: bool,
    clock_shift: u4,
    lfsr: u16,
    lfsr_timer: usize,

    ptr: u3,

    frame_sequencer: FrameSequencer,

    const Self = @This();

    fn new() Self {
        return Self{
            .ticks = 0,
            .running = false,

            .length_enable = false,
            .length = 0,

            .duty = 0,
            .initial_volume = 0,
            .env_dir = false,
            .env_period = 0,
            .env_timer = 0,
            .volume = 0,

            .clock_divider = 0,
            .lfsr_width = false,
            .clock_shift = 0,
            .lfsr = 0,
            .lfsr_timer = 0,

            .ptr = 0,

            .frame_sequencer = FrameSequencer.new(),
        };
    }

    fn tick(self: *Self, ticks: usize) void {
        self.ticks += ticks;
        while (self.ticks >= 4) {
            self.ticks -= 4;
            self.lfsr_timer += 1;
            const freq = self.frequency();

            if (self.lfsr_timer >= freq) {
                //std.debug.print("freq: {}\n", .{freq});
                self.lfsr_timer = 0;
                self.shiftLfsr();
            }
        }

        const clocks = self.frame_sequencer.tick(ticks);

        if (clocks.vol_env and self.env_period > 0) {
            self.env_timer, const eof = @subWithOverflow(self.env_timer, 1);

            if (eof > 0) {
                self.env_timer = self.env_period - 1;

                if (self.env_dir) {
                    if (self.volume < 15) self.volume += 1;
                } else {
                    if (self.volume > 1) self.volume -= 1;
                }
            }
        }

        if (clocks.length and self.length_enable and self.length < 64) {
            self.length += 1;
            if (self.length == 64) {
                self.running = false;
            }
        }
    }

    fn frequency(self: *const Self) usize {
        const divider: f32 = if (self.clock_divider == 0) 0.5 else @floatFromInt(self.clock_divider);
        const shift: f32 = std.math.pow(f32, 2, @floatFromInt(self.clock_shift));

        return @intFromFloat(divider * shift);
    }

    fn shiftLfsr(self: *Self) void {
        const bit0: u1 = @truncate(self.lfsr);
        const bit1: u1 = @truncate(self.lfsr >> 1);
        const result: u1 = if (bit0 == bit1) 1 else 0;

        self.lfsr = @shrExact(self.lfsr & 0xfffe, 1) + (@as(u16, result) << 15);
        //if (self.lfsr_width) {
        //    self.lfsr = (self.lfsr & 0xff7f) + (@as(u16, result) << 7);
        //}
    }

    fn trigger(self: *Self, enable_length: bool) void {
        if (self.length == 64) {
            const next_len_clock = self.frame_sequencer.nextClocks().length;
            if (enable_length and !next_len_clock) self.length = 1 else self.length = 0;
        }

        self.volume = self.initial_volume;
        self.lfsr = 0;

        if (!self.dacEnabled()) return;

        self.running = true;
    }

    fn dacEnabled(self: *Self) bool {
        return !(self.initial_volume == 0 and !self.env_dir);
    }

    fn isRunning(self: *Self) bool {
        return self.dacEnabled() and self.running;
    }

    fn getSample(self: *Self) f32 {
        if (!self.running) {
            return 0;
        }

        const amplitude = @as(f32, @floatFromInt(self.volume)) / 16;

        return if (self.lfsr & 0x01 == 0x01) amplitude else -amplitude;
    }
};

const FrameSequencer = struct {
    divider: u13,
    state: u3,

    const Clocks = struct {
        length: bool,
        vol_env: bool,
        sweep: bool,
    };

    const Self = @This();

    fn new() FrameSequencer {
        return Self{
            .divider = 0,
            .state = 0,
        };
    }

    fn tick(self: *Self, ticks: usize) Clocks {
        self.divider, const overflow = @addWithOverflow(self.divider, @as(u13, @truncate(ticks)));
        if (overflow > 0) {
            self.state +%= 1;
            return getClocks(self.state);
        }
        return Clocks{ .length = false, .vol_env = false, .sweep = false };
    }

    fn nextClocks(self: *const Self) Clocks {
        return getClocks(self.state +% 1);
    }

    fn getClocks(state: u3) Clocks {
        return switch (state) {
            0 => Clocks{ .length = true, .vol_env = false, .sweep = false },
            1 => Clocks{ .length = false, .vol_env = false, .sweep = false },
            2 => Clocks{ .length = true, .vol_env = false, .sweep = true },
            3 => Clocks{ .length = false, .vol_env = false, .sweep = false },
            4 => Clocks{ .length = true, .vol_env = false, .sweep = false },
            5 => Clocks{ .length = false, .vol_env = false, .sweep = false },
            6 => Clocks{ .length = true, .vol_env = false, .sweep = true },
            7 => Clocks{ .length = false, .vol_env = true, .sweep = false },
        };
    }
};
