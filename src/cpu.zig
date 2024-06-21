const std = @import("std");
const Opcode = @import("opcodes.zig").Opcode;

pub const CPUError = error{
    UnknownOpcode,
};

pub const CPU = struct {
    af: u16,
    bc: u16,
    de: u16,
    hl: u16,
    sp: u16,
    pc: u16,

    memory: Memory = Memory{},

    const Self = @This();

    pub fn getFlags(self: *Self) *FlagsRegister {
        return @ptrCast(&self.af);
    }
    pub fn executeOp(self: *Self) !void {
        const opcode: Opcode = @enumFromInt(self.readProgramMemory(u8));
        self.pc += 1;

        switch (opcode) {
            Opcode.NOP => {},
            Opcode.STOP => {},

            Opcode.LD_a16_addr_SP => {
                const addr = self.readProgramMemory(u16);
                self.writeMemory(u16, addr, self.sp);
                self.pc += 2;
            },
            Opcode.LD_BC_n16 => {
                self.bc = self.readProgramMemory(u16);
                self.pc += 2;
            },
            Opcode.LD_DE_n16 => {
                self.de = self.readProgramMemory(u16);
                self.pc += 2;
            },
            Opcode.LD_HL_n16 => {
                self.hl = self.readProgramMemory(u16);
                self.pc += 2;
            },
            Opcode.LD_SP_n16 => {
                self.sp = self.readProgramMemory(u16);
                self.pc += 2;
            },
            Opcode.LD_BC_addr_A => self.writeMemory(u8, self.bc, self.a()),
            Opcode.LD_DE_addr_A => self.writeMemory(u8, self.de, self.a()),
            Opcode.LD_HLI_addr_A => {
                self.writeMemory(u8, self.hl, self.a());
                self.hl += 1;
            },
            Opcode.LD_HLD_addr_A => {
                self.writeMemory(u8, self.hl, self.a());
                self.hl -= 1;
            },
            Opcode.LD_A_n8 => {
                self.setA(self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_B_n8 => {
                self.setB(self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_C_n8 => {
                self.setC(self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_D_n8 => {
                self.setD(self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_E_n8 => {
                self.setE(self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_H_n8 => {
                self.setH(self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_L_n8 => {
                self.setL(self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_HL_ADDR_n8 => {
                self.writeMemory(u8, self.hl, self.readProgramMemory(u8));
                self.pc += 1;
            },
            Opcode.LD_A_BC_addr => self.setA(self.readMemory(u8, self.bc)),
            Opcode.LD_A_DE_addr => self.setA(self.readMemory(u8, self.de)),
            Opcode.LD_A_HLI_addr => {
                self.setA(self.readMemory(u8, self.hl));
                self.hl += 1;
            },
            Opcode.LD_A_HLD_addr => {
                self.setA(self.readMemory(u8, self.hl));
                self.hl -= 1;
            },
            Opcode.LD_B_B => {},
            Opcode.LD_C_B => self.setC(self.b()),
            Opcode.LD_D_B => self.setD(self.b()),
            Opcode.LD_E_B => self.setE(self.b()),
            Opcode.LD_H_B => self.setH(self.b()),
            Opcode.LD_L_B => self.setL(self.b()),
            Opcode.LD_HL_addr_B => self.writeMemory(u8, self.hl, self.b()),
            Opcode.LD_A_B => self.setA(self.b()),
            Opcode.LD_B_C => self.setB(self.c()),
            Opcode.LD_C_C => {},
            Opcode.LD_D_C => self.setD(self.c()),
            Opcode.LD_E_C => self.setE(self.c()),
            Opcode.LD_H_C => self.setH(self.c()),
            Opcode.LD_L_C => self.setL(self.c()),
            Opcode.LD_HL_addr_C => self.writeMemory(u8, self.hl, self.c()),
            Opcode.LD_A_C => self.setA(self.c()),
            Opcode.LD_B_D => self.setB(self.d()),
            Opcode.LD_C_D => self.setC(self.d()),
            Opcode.LD_D_D => {},
            Opcode.LD_E_D => self.setE(self.d()),
            Opcode.LD_H_D => self.setH(self.d()),
            Opcode.LD_L_D => self.setL(self.d()),
            Opcode.LD_HL_addr_D => self.writeMemory(u8, self.hl, self.d()),
            Opcode.LD_A_D => self.setA(self.d()),
            Opcode.LD_B_E => self.setB(self.e()),
            Opcode.LD_C_E => self.setC(self.e()),
            Opcode.LD_D_E => self.setD(self.e()),
            Opcode.LD_E_E => {},
            Opcode.LD_H_E => self.setH(self.e()),
            Opcode.LD_L_E => self.setL(self.e()),
            Opcode.LD_HL_addr_E => self.writeMemory(u8, self.hl, self.e()),
            Opcode.LD_A_E => self.setA(self.e()),
            Opcode.LD_B_H => self.setB(self.h()),
            Opcode.LD_C_H => self.setC(self.h()),
            Opcode.LD_D_H => self.setD(self.h()),
            Opcode.LD_E_H => self.setE(self.h()),
            Opcode.LD_H_H => {},
            Opcode.LD_L_H => self.setL(self.h()),
            Opcode.LD_HL_addr_H => self.writeMemory(u8, self.hl, self.h()),
            Opcode.LD_A_H => self.setA(self.h()),
            Opcode.LD_B_L => self.setB(self.l()),
            Opcode.LD_C_L => self.setC(self.l()),
            Opcode.LD_D_L => self.setD(self.l()),
            Opcode.LD_E_L => self.setE(self.l()),
            Opcode.LD_H_L => self.setH(self.l()),
            Opcode.LD_L_L => {},
            Opcode.LD_HL_addr_L => self.writeMemory(u8, self.hl, self.l()),
            Opcode.LD_A_L => self.setA(self.l()),
            Opcode.LD_B_HL_addr => self.setB(self.readMemory(u8, self.hl)),
            Opcode.LD_C_HL_addr => self.setC(self.readMemory(u8, self.hl)),
            Opcode.LD_D_HL_addr => self.setD(self.readMemory(u8, self.hl)),
            Opcode.LD_E_HL_addr => self.setE(self.readMemory(u8, self.hl)),
            Opcode.LD_H_HL_addr => self.setH(self.readMemory(u8, self.hl)),
            Opcode.LD_L_HL_addr => self.setL(self.readMemory(u8, self.hl)),
            Opcode.HALT => {},
            Opcode.LD_A_HL_addr => self.setA(self.readMemory(u8, self.hl)),
            Opcode.LD_B_A => self.setB(self.a()),
            Opcode.LD_C_A => self.setC(self.a()),
            Opcode.LD_D_A => self.setD(self.a()),
            Opcode.LD_E_A => self.setE(self.a()),
            Opcode.LD_H_A => self.setH(self.a()),
            Opcode.LD_L_A => self.setL(self.a()),
            Opcode.LD_HL_addr_A => self.writeMemory(u8, self.hl, self.a()),
            Opcode.LD_A_A => {},

            Opcode.RLCA => {
                self.getFlags().zero = false;
                self.getFlags().substract = false;
                self.getFlags().half_carry = false;
                const shift_a, const overflow = @shlWithOverflow(self.a(), 1);
                self.getFlags().carry = overflow == 1;
                self.setA(shift_a + overflow);
            },
            Opcode.RLA => {
                self.getFlags().zero = false;
                self.getFlags().substract = false;
                self.getFlags().half_carry = false;
                const shift_a, const carry = @shlWithOverflow(self.a(), 1);
                self.setA(if (self.getFlags().carry) shift_a + 1 else shift_a);
                self.getFlags().carry = carry == 1;
            },
            Opcode.RRCA => {
                self.getFlags().zero = false;
                self.getFlags().substract = false;
                self.getFlags().half_carry = false;
                const lsb: u1 = @truncate(self.a());
                self.setA((self.a() >> 1) + (@as(u8, lsb) << 7));
                self.getFlags().carry = lsb == 1;
            },
            Opcode.RRA => {
                self.getFlags().zero = false;
                self.getFlags().substract = false;
                self.getFlags().half_carry = false;
                const lsb: u1 = @truncate(self.a());
                const carry_bit: u8 = if (self.getFlags().carry) 1 else 0;
                self.setA((self.a() >> 1) + (carry_bit << 7));
                self.getFlags().carry = lsb == 1;
            },
            Opcode.CPL => {
                self.setA(~self.a());
                self.getFlags().substract = true;
                self.getFlags().half_carry = true;
            },
            Opcode.CCF => {
                self.getFlags().carry = !self.getFlags().carry;
                self.getFlags().substract = false;
                self.getFlags().half_carry = false;
            },

            Opcode.DAA => {
                var offset: u8 = 0;
                var set_carry = false;

                const substract = self.getFlags().substract;

                if ((!substract and self.a() & 0x0f > 0x09) or self.getFlags().half_carry) {
                    offset |= 0x06;
                }
                if ((!substract and self.a() > 0x99) or self.getFlags().carry) {
                    offset |= 0x60;
                    set_carry = true;
                }

                if (!self.getFlags().substract) {
                    const r, _ = @addWithOverflow(self.a(), offset);
                    self.setA(r);
                } else {
                    const r, _ = @subWithOverflow(self.a(), offset);
                    self.setA(r);
                }

                self.getFlags().zero = self.a() == 0;
                self.getFlags().half_carry = false;
                self.getFlags().carry = set_carry;
            },

            Opcode.SCF => {
                self.getFlags().carry = true;
                self.getFlags().half_carry = false;
                self.getFlags().substract = false;
            },

            Opcode.JR_NZ_e8 => {
                if (!self.getFlags().zero) {
                    self.jumpRelative();
                }
                self.pc += 1;
            },
            Opcode.JR_NC_e8 => {
                if (!self.getFlags().carry) {
                    self.jumpRelative();
                }
                self.pc += 1;
            },
            Opcode.JR_e8 => {
                self.jumpRelative();
                self.pc += 1;
            },
            Opcode.JR_Z_e8 => {
                if (self.getFlags().zero) {
                    self.jumpRelative();
                }
                self.pc += 1;
            },
            Opcode.JR_C_e8 => {
                if (self.getFlags().carry) {
                    self.jumpRelative();
                }
                self.pc += 1;
            },

            Opcode.ADD_HL_BC => self.hl = self.add16(self.hl, self.bc),
            Opcode.ADD_HL_DE => self.hl = self.add16(self.hl, self.de),
            Opcode.ADD_HL_HL => self.hl = self.add16(self.hl, self.hl),
            Opcode.ADD_HL_SP => self.hl = self.add16(self.hl, self.sp),

            Opcode.INC_BC => self.bc += 1,
            Opcode.INC_DE => self.de += 1,
            Opcode.INC_HL => self.hl += 1,
            Opcode.INC_SP => self.sp += 1,
            Opcode.INC_A => self.setA(self.inc8(self.a())),
            Opcode.INC_B => self.setB(self.inc8(self.b())),
            Opcode.INC_C => self.setC(self.inc8(self.c())),
            Opcode.INC_D => self.setD(self.inc8(self.d())),
            Opcode.INC_E => self.setE(self.inc8(self.e())),
            Opcode.INC_H => self.setH(self.inc8(self.h())),
            Opcode.INC_L => self.setL(self.inc8(self.l())),
            Opcode.INC_HL_ADDR => self.writeMemory(u8, self.hl, self.inc8(self.readMemory(u8, self.hl))),

            Opcode.DEC_BC => self.bc -= 1,
            Opcode.DEC_DE => self.de -= 1,
            Opcode.DEC_HL => self.hl -= 1,
            Opcode.DEC_SP => self.sp -= 1,
            Opcode.DEC_A => self.setA(self.dec8(self.a())),
            Opcode.DEC_B => self.setB(self.dec8(self.b())),
            Opcode.DEC_D => self.setD(self.dec8(self.d())),
            Opcode.DEC_H => self.setH(self.dec8(self.h())),
            Opcode.DEC_C => self.setC(self.dec8(self.c())),
            Opcode.DEC_E => self.setE(self.dec8(self.e())),
            Opcode.DEC_L => self.setL(self.dec8(self.l())),
            Opcode.DEC_HL_ADDR => self.writeMemory(u8, self.hl, self.dec8(self.readMemory(u8, self.hl))),

            Opcode.ADD_A_B => self.setA(self.add8(self.a(), self.b())),
            Opcode.ADC_A_B => self.setA(self.add8c(self.a(), self.b())),
            Opcode.SUB_A_B => self.setA(self.sub8(self.a(), self.b())),
            Opcode.SBC_A_B => self.setA(self.sub8c(self.a(), self.b())),
            Opcode.AND_A_B => self.setA(self.and8(self.a(), self.b())),
            Opcode.XOR_A_B => self.setA(self.xor8(self.a(), self.b())),
            Opcode.OR_A_B => self.setA(self.or8(self.a(), self.b())),
            Opcode.CP_A_B => _ = self.sub8(self.a(), self.b()),

            Opcode.ADD_A_C => self.setA(self.add8(self.a(), self.c())),
            Opcode.ADC_A_C => self.setA(self.add8c(self.a(), self.c())),
            Opcode.SUB_A_C => self.setA(self.sub8(self.a(), self.c())),
            Opcode.SBC_A_C => self.setA(self.sub8c(self.a(), self.c())),
            Opcode.AND_A_C => self.setA(self.and8(self.a(), self.c())),
            Opcode.XOR_A_C => self.setA(self.xor8(self.a(), self.c())),
            Opcode.OR_A_C => self.setA(self.or8(self.a(), self.c())),
            Opcode.CP_A_C => _ = self.sub8(self.a(), self.c()),

            Opcode.ADD_A_D => self.setA(self.add8(self.a(), self.d())),
            Opcode.ADC_A_D => self.setA(self.add8c(self.a(), self.d())),
            Opcode.SUB_A_D => self.setA(self.sub8(self.a(), self.d())),
            Opcode.SBC_A_D => self.setA(self.sub8c(self.a(), self.d())),
            Opcode.AND_A_D => self.setA(self.and8(self.a(), self.d())),
            Opcode.XOR_A_D => self.setA(self.xor8(self.a(), self.d())),
            Opcode.OR_A_D => self.setA(self.or8(self.a(), self.d())),
            Opcode.CP_A_D => _ = self.sub8(self.a(), self.d()),

            Opcode.ADD_A_E => self.setA(self.add8(self.a(), self.e())),
            Opcode.ADC_A_E => self.setA(self.add8c(self.a(), self.e())),
            Opcode.SUB_A_E => self.setA(self.sub8(self.a(), self.e())),
            Opcode.SBC_A_E => self.setA(self.sub8c(self.a(), self.e())),
            Opcode.AND_A_E => self.setA(self.and8(self.a(), self.e())),
            Opcode.XOR_A_E => self.setA(self.xor8(self.a(), self.e())),
            Opcode.OR_A_E => self.setA(self.or8(self.a(), self.e())),
            Opcode.CP_A_E => _ = self.sub8(self.a(), self.e()),

            Opcode.ADD_A_H => self.setA(self.add8(self.a(), self.h())),
            Opcode.ADC_A_H => self.setA(self.add8c(self.a(), self.h())),
            Opcode.SUB_A_H => self.setA(self.sub8(self.a(), self.h())),
            Opcode.SBC_A_H => self.setA(self.sub8c(self.a(), self.h())),
            Opcode.AND_A_H => self.setA(self.and8(self.a(), self.h())),
            Opcode.XOR_A_H => self.setA(self.xor8(self.a(), self.h())),
            Opcode.OR_A_H => self.setA(self.or8(self.a(), self.h())),
            Opcode.CP_A_H => _ = self.sub8(self.a(), self.h()),

            Opcode.ADD_A_L => self.setA(self.add8(self.a(), self.l())),
            Opcode.ADC_A_L => self.setA(self.add8c(self.a(), self.l())),
            Opcode.SUB_A_L => self.setA(self.sub8(self.a(), self.l())),
            Opcode.SBC_A_L => self.setA(self.sub8c(self.a(), self.l())),
            Opcode.AND_A_L => self.setA(self.and8(self.a(), self.l())),
            Opcode.XOR_A_L => self.setA(self.xor8(self.a(), self.l())),
            Opcode.OR_A_L => self.setA(self.or8(self.a(), self.l())),
            Opcode.CP_A_L => _ = self.sub8(self.a(), self.l()),

            Opcode.ADD_A_HL_addr => self.setA(self.add8(self.a(), self.readMemory(u8, self.hl))),
            Opcode.ADC_A_HL_addr => self.setA(self.add8c(self.a(), self.readMemory(u8, self.hl))),
            Opcode.SUB_A_HL_addr => self.setA(self.sub8(self.a(), self.readMemory(u8, self.hl))),
            Opcode.SBC_A_HL_addr => self.setA(self.sub8c(self.a(), self.readMemory(u8, self.hl))),
            Opcode.AND_A_HL_addr => self.setA(self.and8(self.a(), self.readMemory(u8, self.hl))),
            Opcode.XOR_A_HL_addr => self.setA(self.xor8(self.a(), self.readMemory(u8, self.hl))),
            Opcode.OR_A_HL_addr => self.setA(self.or8(self.a(), self.readMemory(u8, self.hl))),
            Opcode.CP_A_HL_addr => _ = self.sub8(self.a(), self.readMemory(u8, self.hl)),

            Opcode.ADD_A_A => self.setA(self.add8(self.a(), self.a())),
            Opcode.ADC_A_A => self.setA(self.add8c(self.a(), self.a())),
            Opcode.SUB_A_A => self.setA(self.sub8(self.a(), self.a())),
            Opcode.SBC_A_A => self.setA(self.sub8c(self.a(), self.a())),
            Opcode.AND_A_A => self.setA(self.and8(self.a(), self.a())),
            Opcode.XOR_A_A => self.setA(self.xor8(self.a(), self.a())),
            Opcode.OR_A_A => self.setA(self.or8(self.a(), self.a())),
            Opcode.CP_A_A => _ = self.sub8(self.a(), self.a()),
        }
    }

    fn inc8(self: *Self, reg: u8) u8 {
        self.getFlags().substract = false;
        self.getFlags().half_carry = reg & 0xf == 0xf;
        self.getFlags().zero = reg == 0xff;
        return reg +% 1;
    }

    fn dec8(self: *Self, reg: u8) u8 {
        self.getFlags().substract = true;
        self.getFlags().half_carry = reg & 0xf == 0;
        self.getFlags().zero = reg == 1;
        return reg -% 1;
    }

    fn writeMemory(self: *Self, comptime T: type, addr: u16, val: T) void {
        const size = @sizeOf(T);

        for (0..size) |i| {
            const byte: u8 = @truncate(val / std.math.pow(T, 2, @truncate(i * 8)));
            self.memory.write(addr + @as(u16, @truncate(i)), byte);
        }
    }

    fn readMemory(self: *Self, comptime T: type, addr: u16) T {
        const size = @sizeOf(T);

        var value: T = 0;
        for (0..size) |i| {
            const byte = self.memory.read(addr + @as(u16, @truncate(i)));
            value += byte * std.math.pow(T, 2, @truncate(i * 8));
        }
        return value;
    }

    fn readProgramMemory(self: *Self, comptime T: type) T {
        return self.readMemory(T, self.pc);
    }

    fn a(self: *Self) u8 {
        return @truncate(self.af >> 8);
    }

    fn f(self: *Self) u8 {
        return @truncate(self.af);
    }

    fn b(self: *Self) u8 {
        return @truncate(self.bc >> 8);
    }

    fn c(self: *Self) u8 {
        return @truncate(self.bc);
    }

    fn d(self: *Self) u8 {
        return @truncate(self.de >> 8);
    }

    fn e(self: *Self) u8 {
        return @truncate(self.de);
    }

    fn h(self: *Self) u8 {
        return @truncate(self.hl >> 8);
    }

    fn l(self: *Self) u8 {
        return @truncate(self.hl);
    }

    fn s(self: *Self) u8 {
        return @truncate(self.sp >> 8);
    }

    fn p(self: *Self) u8 {
        return @truncate(self.sp);
    }

    fn setA(self: *Self, val: u8) void {
        self.af = (@as(u16, val) << 8) + self.f();
    }

    fn setF(self: *Self, val: u8) void {
        self.af = (@as(u16, self.a()) << 8) + val;
    }

    fn setB(self: *Self, val: u8) void {
        self.bc = (@as(u16, val) << 8) + self.c();
    }

    fn setC(self: *Self, val: u8) void {
        self.bc = (@as(u16, self.b()) << 8) + val;
    }

    fn setD(self: *Self, val: u8) void {
        self.de = (@as(u16, val) << 8) + self.e();
    }

    fn setE(self: *Self, val: u8) void {
        self.de = (@as(u16, self.d()) << 8) + val;
    }

    fn setH(self: *Self, val: u8) void {
        self.hl = (@as(u16, val) << 8) + self.l();
    }

    fn setL(self: *Self, val: u8) void {
        self.hl = (@as(u16, self.h()) << 8) + val;
    }

    fn setS(self: *Self, val: u8) void {
        self.sp = (@as(u16, val) << 8) + self.p();
    }

    fn setP(self: *Self, val: u8) void {
        self.sp = (@as(u16, self.s()) << 8) + val;
    }

    fn jumpRelative(self: *Self) void {
        const val = self.readProgramMemory(u8);
        if (val & 0x80 == 0x80) {
            self.pc -= 256;
        }
        self.pc += val;
    }

    fn add16(self: *Self, reg: u16, val: u16) u16 {
        self.getFlags().half_carry = (reg & 0xfff) + (val & 0xfff) > 0xfff;
        const result, const overflow = @addWithOverflow(reg, val);
        self.getFlags().substract = false;
        self.getFlags().carry = overflow == 1;
        return result;
    }

    fn add8(self: *Self, reg: u8, val: u8) u8 {
        const result, const overflow = @addWithOverflow(reg, val);
        self.getFlags().substract = false;
        self.getFlags().zero = result == 0;
        self.getFlags().half_carry = ((reg & 0xf) + (val & 0xf)) > 0xf;
        self.getFlags().carry = overflow == 1;
        return result;
    }

    fn add8c(self: *Self, reg: u8, val: u8) u8 {
        const carry: u8 = if (self.getFlags().carry) 1 else 0;
        const iresult, const i_overflow = @addWithOverflow(reg, val);
        const result, const overflow = @addWithOverflow(iresult, carry);

        self.getFlags().substract = false;
        self.getFlags().zero = result == 0;
        self.getFlags().half_carry = ((reg & 0xf) + (val & 0xf) + carry) > 0xf;
        self.getFlags().carry = overflow == 1 or i_overflow == 1;
        return result;
    }

    fn sub8(self: *Self, reg: u8, val: u8) u8 {
        const result = reg -% val;
        self.getFlags().substract = true;
        self.getFlags().zero = result == 0;
        self.getFlags().half_carry = ((reg & 0xf) -% (val & 0xf)) > 0xf;
        self.getFlags().carry = val > reg;
        return result;
    }

    fn sub8c(self: *Self, reg: u8, val: u8) u8 {
        const carry: u8 = if (self.getFlags().carry) 1 else 0;
        const iresult, const i_overflow = @subWithOverflow(reg, val);
        const result, const overflow = @subWithOverflow(iresult, carry);

        self.getFlags().substract = true;
        self.getFlags().zero = result == 0;
        self.getFlags().half_carry = ((reg & 0xf) -% (val & 0xf) -% carry) > 0xf;
        self.getFlags().carry = i_overflow == 1 or overflow == 1;
        return result;
    }

    fn and8(self: *Self, reg: u8, val: u8) u8 {
        const result = reg & val;
        self.getFlags().zero = result == 0;
        self.getFlags().substract = false;
        self.getFlags().half_carry = true;
        self.getFlags().carry = false;
        return result;
    }

    fn xor8(self: *Self, reg: u8, val: u8) u8 {
        const result = reg ^ val;
        self.getFlags().zero = result == 0;
        self.getFlags().substract = false;
        self.getFlags().half_carry = false;
        self.getFlags().carry = false;
        return result;
    }

    fn or8(self: *Self, reg: u8, val: u8) u8 {
        const result = reg | val;
        self.getFlags().zero = result == 0;
        self.getFlags().substract = false;
        self.getFlags().half_carry = false;
        self.getFlags().carry = false;
        return result;
    }
};

pub fn new() CPU {
    return CPU{
        .af = 0,
        .bc = 0,
        .de = 0,
        .hl = 0,
        .sp = 0,
        .pc = 0,
    };
}

pub const FlagsRegister = packed struct {
    _padding: u4 = 0,
    carry: bool,
    half_carry: bool,
    substract: bool,
    zero: bool,
};

const Memory = struct {
    ram: [65536]u8 = [_]u8{0} ** 65536,

    const Self = @This();

    fn read(self: *const Self, ptr: u16) u8 {
        return self.ram[ptr];
    }

    fn write(self: *Self, ptr: u16, val: u8) void {
        self.ram[ptr] = val;
    }
};

const Tests = struct { name: []u8, initial: CPUTestState, final: CPUTestState, cycles: []?struct { u16, u8, []u8 } };

const CPUTestState = struct {
    a: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    f: u8,
    h: u8,
    l: u8,
    pc: u16,
    sp: u16,
    ram: []struct { u16, u8 },

    const Self = @This();

    fn createCPU(self: *const Self) CPU {
        var cpu = new();
        cpu.af = (@as(u16, self.a) << 8) + self.f;
        cpu.bc = (@as(u16, self.b) << 8) + self.c;
        cpu.de = (@as(u16, self.d) << 8) + self.e;
        cpu.hl = (@as(u16, self.h) << 8) + self.l;
        cpu.pc = self.pc - 1;
        cpu.sp = self.sp;

        for (self.ram) |cell| {
            cpu.memory.ram[cell.@"0"] = cell.@"1";
        }

        return cpu;
    }
};

test "cpu tests" {
    const prefix = "tests/GameboyCPUTests/v2/";
    _ = prefix; // autofix
    // TODO: 0x09 - 0x39 tests are disabled, because I don't understand the half-carry flag behaviour
    const test_files = [_][]const u8{
        "00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "0a", "0b", "0c", "0d", "0e", "0f",
        "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "1a", "1b", "1c", "1d", "1e", "1f",
        "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "2a", "2b", "2c", "2d", "2e", "2f",
        "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "3a", "3b", "3c", "3d", "3e", "3f",
        "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "4a", "4b", "4c", "4d", "4e", "4f",
        "50", "51", "52", "53", "54", "55", "56", "57", "58", "59", "5a", "5b", "5c", "5d", "5e", "5f",
        "60", "61", "62", "63", "64", "65", "66", "67", "68", "69", "6a", "6b", "6c", "6d", "6e", "6f",
        "70", "71", "72", "73", "74", "75", "76", "77", "78", "79", "7a", "7b", "7c", "7d", "7e", "7f",
        "80", "81", "82", "83", "84", "85", "86", "87", "88", "89", "8a", "8b", "8c", "8d", "8e", "8f",
        "90", "91", "92", "93", "94", "95", "96", "97", "98", "99", "9a", "9b", "9c", "9d", "9e", "9f",
        "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "aa", "ab", "ac", "ad", "ae", "af",
        "b0", "b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9", "ba", "bb", "bc", "bd", "be", "bf",
    };

    for (test_files) |file| {
        const path = try std.fmt.allocPrint(std.testing.allocator, "tests/GameboyCPUTests/v2/{s}.json", .{file});
        defer std.testing.allocator.free(path);
        const data = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024000);
        defer std.testing.allocator.free(data);

        const parsed = try std.json.parseFromSlice([]Tests, std.testing.allocator, data, .{});
        defer parsed.deinit();

        for (parsed.value) |t| {
            std.debug.print("Running test {s}...\n", .{t.name});

            var cpu = t.initial.createCPU();
            const final_cpu = t.final.createCPU();

            try cpu.executeOp();

            std.testing.expectEqual(final_cpu, cpu) catch |err| {
                std.debug.print("error: {any}", .{err});
                return err;
            };
        }
    }
}
