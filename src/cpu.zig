const std = @import("std");
const Opcode = @import("opcodes.zig").Opcode;

pub const CPUError = error{
    UnknownOpcode,
};

pub const MemoryError = error{
    WriteError,
};

const Memory = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        read: *const fn (ptr: *anyopaque, addr: u16) u8,
        write: *const fn (ptr: *anyopaque, addr: u16, val: u8) anyerror!void,
    };

    fn init(obj_ptr: anytype) Memory {
        const Type = @TypeOf(obj_ptr);
        return Memory{
            .ptr = obj_ptr,
            .vtable = &.{
                .read = &struct {
                    fn fun(obj: *anyopaque, addr: u16) u8 {
                        const self: Type = @ptrCast(@alignCast(obj));
                        return self.read(addr);
                    }
                }.fun,
                .write = &struct {
                    fn fun(obj: *anyopaque, addr: u16, val: u8) anyerror!void {
                        const self: Type = @ptrCast(@alignCast(obj));
                        return try self.write(addr, val);
                    }
                }.fun,
            },
        };
    }

    fn write(self: *const Memory, addr: u16, val: u8) !void {
        try self.vtable.write(self.ptr, addr, val);
    }

    fn read(self: *const Memory, addr: u16) u8 {
        return self.vtable.read(self.ptr, addr);
    }
};

pub const CPU = struct {
    af: u16,
    bc: u16,
    de: u16,
    hl: u16,
    sp: u16,
    pc: u16,
    ime: bool,
    memory: Memory,

    halted: bool,

    const Self = @This();

    pub fn getFlags(self: *Self) *FlagsRegister {
        return @ptrCast(&self.af);
    }

    pub fn executeOp(self: *Self) !usize {
        var int_flags = self.readMemory(u8, 0xff0f);
        const int_enabled = self.readMemory(u8, 0xffff);

        const masked_ints = int_flags & int_enabled;

        if (masked_ints > 0) {
            if (self.halted) self.halted = false;
        }

        if (self.ime and masked_ints > 0) {
            self.ime = false;

            if (masked_ints & 0x01 > 0) {
                int_flags -= 0x01;
                try self.callAddr(0x40);
            } else if (masked_ints & 0x02 > 0) {
                int_flags -= 0x02;
                try self.callAddr(0x48);
            } else if (masked_ints & 0x04 > 0) {
                int_flags -= 0x04;
                try self.callAddr(0x50);
            } else if (masked_ints & 0x08 > 0) {
                int_flags -= 0x08;
                try self.callAddr(0x58);
            } else if (masked_ints & 0x10 > 0) {
                int_flags -= 0x10;
                try self.callAddr(0x60);
            }

            try self.writeMemory(u8, 0xff0f, int_flags);
            return 20;
        }

        if (self.halted) return 4;

        const opcode_byte = self.readProgramMemory(u8);
        const opcode: Opcode = @enumFromInt(opcode_byte);
        self.pc += 1;

        try switch (opcode) {
            Opcode.NOP => {},
            Opcode.STOP => {},

            Opcode.LD_a16_addr_SP => {
                const addr = self.readProgramMemory(u16);
                try self.writeMemory(u16, addr, self.sp);
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
            Opcode.LD_BC_addr_A => try self.writeMemory(u8, self.bc, self.a()),
            Opcode.LD_DE_addr_A => try self.writeMemory(u8, self.de, self.a()),
            Opcode.LD_HLI_addr_A => {
                try self.writeMemory(u8, self.hl, self.a());
                self.hl += 1;
            },
            Opcode.LD_HLD_addr_A => {
                try self.writeMemory(u8, self.hl, self.a());
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
                try self.writeMemory(u8, self.hl, self.readProgramMemory(u8));
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
            Opcode.LD_HL_addr_B => try self.writeMemory(u8, self.hl, self.b()),
            Opcode.LD_A_B => self.setA(self.b()),
            Opcode.LD_B_C => self.setB(self.c()),
            Opcode.LD_C_C => {},
            Opcode.LD_D_C => self.setD(self.c()),
            Opcode.LD_E_C => self.setE(self.c()),
            Opcode.LD_H_C => self.setH(self.c()),
            Opcode.LD_L_C => self.setL(self.c()),
            Opcode.LD_HL_addr_C => try self.writeMemory(u8, self.hl, self.c()),
            Opcode.LD_A_C => self.setA(self.c()),
            Opcode.LD_B_D => self.setB(self.d()),
            Opcode.LD_C_D => self.setC(self.d()),
            Opcode.LD_D_D => {},
            Opcode.LD_E_D => self.setE(self.d()),
            Opcode.LD_H_D => self.setH(self.d()),
            Opcode.LD_L_D => self.setL(self.d()),
            Opcode.LD_HL_addr_D => try self.writeMemory(u8, self.hl, self.d()),
            Opcode.LD_A_D => self.setA(self.d()),
            Opcode.LD_B_E => self.setB(self.e()),
            Opcode.LD_C_E => self.setC(self.e()),
            Opcode.LD_D_E => self.setD(self.e()),
            Opcode.LD_E_E => {},
            Opcode.LD_H_E => self.setH(self.e()),
            Opcode.LD_L_E => self.setL(self.e()),
            Opcode.LD_HL_addr_E => try self.writeMemory(u8, self.hl, self.e()),
            Opcode.LD_A_E => self.setA(self.e()),
            Opcode.LD_B_H => self.setB(self.h()),
            Opcode.LD_C_H => self.setC(self.h()),
            Opcode.LD_D_H => self.setD(self.h()),
            Opcode.LD_E_H => self.setE(self.h()),
            Opcode.LD_H_H => {},
            Opcode.LD_L_H => self.setL(self.h()),
            Opcode.LD_HL_addr_H => try self.writeMemory(u8, self.hl, self.h()),
            Opcode.LD_A_H => self.setA(self.h()),
            Opcode.LD_B_L => self.setB(self.l()),
            Opcode.LD_C_L => self.setC(self.l()),
            Opcode.LD_D_L => self.setD(self.l()),
            Opcode.LD_E_L => self.setE(self.l()),
            Opcode.LD_H_L => self.setH(self.l()),
            Opcode.LD_L_L => {},
            Opcode.LD_HL_addr_L => try self.writeMemory(u8, self.hl, self.l()),
            Opcode.LD_A_L => self.setA(self.l()),
            Opcode.LD_B_HL_addr => self.setB(self.readMemory(u8, self.hl)),
            Opcode.LD_C_HL_addr => self.setC(self.readMemory(u8, self.hl)),
            Opcode.LD_D_HL_addr => self.setD(self.readMemory(u8, self.hl)),
            Opcode.LD_E_HL_addr => self.setE(self.readMemory(u8, self.hl)),
            Opcode.LD_H_HL_addr => self.setH(self.readMemory(u8, self.hl)),
            Opcode.LD_L_HL_addr => self.setL(self.readMemory(u8, self.hl)),
            Opcode.HALT => self.halted = true,
            Opcode.LD_A_HL_addr => self.setA(self.readMemory(u8, self.hl)),
            Opcode.LD_B_A => self.setB(self.a()),
            Opcode.LD_C_A => self.setC(self.a()),
            Opcode.LD_D_A => self.setD(self.a()),
            Opcode.LD_E_A => self.setE(self.a()),
            Opcode.LD_H_A => self.setH(self.a()),
            Opcode.LD_L_A => self.setL(self.a()),
            Opcode.LD_HL_addr_A => try self.writeMemory(u8, self.hl, self.a()),
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

            Opcode.INC_BC => self.bc +%= 1,
            Opcode.INC_DE => self.de +%= 1,
            Opcode.INC_HL => self.hl +%= 1,
            Opcode.INC_SP => self.sp +%= 1,
            Opcode.INC_A => self.setA(self.inc8(self.a())),
            Opcode.INC_B => self.setB(self.inc8(self.b())),
            Opcode.INC_C => self.setC(self.inc8(self.c())),
            Opcode.INC_D => self.setD(self.inc8(self.d())),
            Opcode.INC_E => self.setE(self.inc8(self.e())),
            Opcode.INC_H => self.setH(self.inc8(self.h())),
            Opcode.INC_L => self.setL(self.inc8(self.l())),
            Opcode.INC_HL_ADDR => try self.writeMemory(u8, self.hl, self.inc8(self.readMemory(u8, self.hl))),

            Opcode.DEC_BC => self.bc -%= 1,
            Opcode.DEC_DE => self.de -%= 1,
            Opcode.DEC_HL => self.hl -%= 1,
            Opcode.DEC_SP => self.sp -%= 1,
            Opcode.DEC_A => self.setA(self.dec8(self.a())),
            Opcode.DEC_B => self.setB(self.dec8(self.b())),
            Opcode.DEC_D => self.setD(self.dec8(self.d())),
            Opcode.DEC_H => self.setH(self.dec8(self.h())),
            Opcode.DEC_C => self.setC(self.dec8(self.c())),
            Opcode.DEC_E => self.setE(self.dec8(self.e())),
            Opcode.DEC_L => self.setL(self.dec8(self.l())),
            Opcode.DEC_HL_ADDR => try self.writeMemory(u8, self.hl, self.dec8(self.readMemory(u8, self.hl))),

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

            Opcode.RET_NZ => {
                if (!self.getFlags().zero) self.pc = self.popStack();
            },
            Opcode.RET_Z => {
                if (self.getFlags().zero) self.pc = self.popStack();
            },
            Opcode.RET_NC => {
                if (!self.getFlags().carry) self.pc = self.popStack();
            },
            Opcode.RET_C => {
                if (self.getFlags().carry) self.pc = self.popStack();
            },
            Opcode.ADD_SP_e8 => {
                const val = self.readProgramMemory(u8);

                self.getFlags().carry = ((self.sp & 0xff)) + (val & 0xff) > 0xff;
                self.getFlags().half_carry = ((self.sp & 0xf) + (val & 0xf)) > 0xf;
                self.getFlags().zero = false;
                self.getFlags().substract = false;

                self.sp +%= val;
                if (val & 0x80 == 0x80) {
                    self.sp -%= 256;
                }

                self.pc += 1;
            },

            Opcode.LDH_a8_addr_A => {
                const addr = @as(u16, self.readProgramMemory(u8)) + 0xff00;
                self.pc += 1;
                try self.writeMemory(u8, addr, self.a());
            },
            Opcode.LDH_A_a8_addr => {
                const addr = @as(u16, self.readProgramMemory(u8)) + 0xff00;
                self.pc += 1;
                self.setA(self.readMemory(u8, addr));
            },
            Opcode.LD_HL_SP_add_e8 => {
                const val = self.readProgramMemory(u8);

                self.getFlags().carry = ((self.sp & 0xff)) + (val & 0xff) > 0xff;
                self.getFlags().half_carry = ((self.sp & 0xf) + (val & 0xf)) > 0xf;
                self.getFlags().zero = false;
                self.getFlags().substract = false;

                self.hl = self.sp +% val;
                if (val & 0x80 == 0x80) {
                    self.hl -%= 256;
                }

                self.pc += 1;
            },

            Opcode.LD_A_a16_addr => {
                self.setA(self.readMemory(u8, self.readProgramMemory(u16)));
                self.pc += 2;
            },
            Opcode.LD_A_C_addr => {
                self.setA(self.readMemory(u8, @as(u16, self.c()) + 0xff00));
            },
            Opcode.LD_a16_addr_A => {
                const addr = self.readProgramMemory(u16);
                try self.writeMemory(u8, addr, self.a());
                self.pc += 2;
            },
            Opcode.LD_C_addr_A => {
                const addr = @as(u16, self.c()) + 0xff00;
                try self.writeMemory(u8, addr, self.a());
            },
            Opcode.LD_SP_HL => self.sp = self.hl,

            Opcode.DI => {
                self.ime = false;
            },
            Opcode.EI => {
                self.ime = true;
            },
            Opcode.PREFIX => {
                const prefixed_opcode = self.readProgramMemory(u8);
                self.pc += 1;

                var reg_val: u8 = switch (prefixed_opcode & 0o7) {
                    0 => self.b(),
                    1 => self.c(),
                    2 => self.d(),
                    3 => self.e(),
                    4 => self.h(),
                    5 => self.l(),
                    6 => self.readMemory(u8, self.hl),
                    7 => self.a(),
                    else => return CPUError.UnknownOpcode,
                };

                switch (prefixed_opcode & 0o300) {
                    0o000 => {
                        switch (prefixed_opcode & 0o370) {
                            0o000 => {
                                self.getFlags().substract = false;
                                self.getFlags().half_carry = false;
                                const shifted, const overflow = @shlWithOverflow(reg_val, 1);
                                self.getFlags().carry = overflow == 1;
                                reg_val = overflow + shifted;
                                self.getFlags().zero = reg_val == 0;
                            },
                            0o010 => {
                                self.getFlags().substract = false;
                                self.getFlags().half_carry = false;
                                const lsb: u1 = @truncate(reg_val);
                                reg_val = (reg_val >> 1) + (@as(u8, lsb) << 7);
                                self.getFlags().carry = lsb == 1;
                                self.getFlags().zero = reg_val == 0;
                            },
                            0o020 => {
                                self.getFlags().substract = false;
                                self.getFlags().half_carry = false;
                                const shifted, const carry = @shlWithOverflow(reg_val, 1);
                                reg_val = if (self.getFlags().carry) shifted + 1 else shifted;
                                self.getFlags().carry = carry == 1;
                                self.getFlags().zero = reg_val == 0;
                            },
                            0o030 => {
                                self.getFlags().substract = false;
                                self.getFlags().half_carry = false;
                                const lsb: u1 = @truncate(reg_val);
                                const carry_bit: u8 = if (self.getFlags().carry) 1 else 0;
                                reg_val = (reg_val >> 1) + (carry_bit << 7);
                                self.getFlags().carry = lsb == 1;
                                self.getFlags().zero = reg_val == 0;
                            },
                            0o040 => {
                                self.getFlags().substract = false;
                                self.getFlags().half_carry = false;
                                const shifted, const overflow = @shlWithOverflow(reg_val, 1);
                                self.getFlags().carry = overflow == 1;
                                reg_val = shifted;
                                self.getFlags().zero = reg_val == 0;
                            },
                            0o050 => {
                                self.getFlags().substract = false;
                                self.getFlags().half_carry = false;
                                self.getFlags().carry = reg_val & 1 == 1;
                                reg_val = (reg_val >> 1) + (reg_val & 0x80);
                                self.getFlags().zero = reg_val == 0;
                            },
                            0o060 => {
                                const upper = reg_val & 0xf0;
                                const lower = reg_val & 0xf;

                                reg_val = (upper >> 4) + (lower << 4);

                                self.getFlags().carry = false;
                                self.getFlags().half_carry = false;
                                self.getFlags().substract = false;
                                self.getFlags().zero = reg_val == 0;
                            },
                            0o070 => {
                                self.getFlags().substract = false;
                                self.getFlags().half_carry = false;
                                self.getFlags().carry = reg_val & 1 == 1;
                                reg_val = (reg_val >> 1);
                                self.getFlags().zero = reg_val == 0;
                            },
                            else => {
                                return CPUError.UnknownOpcode;
                            },
                        }
                    },
                    0o100 => {
                        const bit = (prefixed_opcode & 0o70) >> 3;
                        const test_mask = std.math.pow(u8, 2, bit);

                        self.getFlags().zero = reg_val & test_mask == 0;
                        self.getFlags().substract = false;
                        self.getFlags().half_carry = true;
                    },
                    0o200 => {
                        const bit = (prefixed_opcode & 0o70) >> 3;
                        const mask = std.math.pow(u8, 2, bit);
                        reg_val &= ~mask;
                    },
                    0o300 => {
                        const bit = (prefixed_opcode & 0o70) >> 3;
                        const mask = std.math.pow(u8, 2, bit);
                        reg_val |= mask;
                    },
                    else => {},
                }

                switch (prefixed_opcode & 0o7) {
                    0 => self.setB(reg_val),
                    1 => self.setC(reg_val),
                    2 => self.setD(reg_val),
                    3 => self.setE(reg_val),
                    4 => self.setH(reg_val),
                    5 => self.setL(reg_val),
                    6 => try self.writeMemory(u8, self.hl, reg_val),
                    7 => self.setA(reg_val),
                    else => return CPUError.UnknownOpcode,
                }
            },

            Opcode.PUSH_BC => try self.pushStack(self.bc),
            Opcode.PUSH_DE => try self.pushStack(self.de),
            Opcode.PUSH_HL => try self.pushStack(self.hl),
            Opcode.PUSH_AF => try self.pushStack(self.af),
            Opcode.POP_BC => self.bc = self.popStack(),
            Opcode.POP_DE => self.de = self.popStack(),
            Opcode.POP_HL => self.hl = self.popStack(),
            Opcode.POP_AF => {
                self.af = self.popStack();
                self.setF(self.f() & 0xf0);
            },

            Opcode.CALL_NZ_a16 => {
                if (!self.getFlags().zero) try self.call() else self.pc += 2;
            },
            Opcode.CALL_NC_a16 => {
                if (!self.getFlags().carry) try self.call() else self.pc += 2;
            },
            Opcode.CALL_Z_a16 => {
                if (self.getFlags().zero) try self.call() else self.pc += 2;
            },
            Opcode.CALL_C_a16 => {
                if (self.getFlags().carry) try self.call() else self.pc += 2;
            },
            Opcode.CALL_a16 => self.call(),
            Opcode.RET => self.pc = self.popStack(),
            Opcode.RETI => {
                self.ime = true;
                self.pc = self.popStack();
            },

            Opcode.JP_a16 => self.jump(self.readProgramMemory(u16)),
            Opcode.JP_HL => self.jump(self.hl),
            Opcode.JP_Z_a16 => {
                if (self.getFlags().zero) self.jump(self.readProgramMemory(u16)) else self.pc += 2;
            },
            Opcode.JP_C_a16 => {
                if (self.getFlags().carry) self.pc = self.readProgramMemory(u16) else self.pc += 2;
            },
            Opcode.JP_NZ_a16 => {
                if (!self.getFlags().zero) self.pc = self.readProgramMemory(u16) else self.pc += 2;
            },
            Opcode.JP_NC_a16 => {
                if (!self.getFlags().carry) self.pc = self.readProgramMemory(u16) else self.pc += 2;
            },
            Opcode.ADD_A_n8 => {
                self.setA(self.add8(self.a(), self.readProgramMemory(u8)));
                self.pc += 1;
            },
            Opcode.ADC_A_n8 => {
                self.setA(self.add8c(self.a(), self.readProgramMemory(u8)));
                self.pc += 1;
            },
            Opcode.SUB_A_n8 => {
                self.setA(self.sub8(self.a(), self.readProgramMemory(u8)));
                self.pc += 1;
            },
            Opcode.SBC_A_n8 => {
                self.setA(self.sub8c(self.a(), self.readProgramMemory(u8)));
                self.pc += 1;
            },
            Opcode.AND_A_n8 => {
                self.setA(self.and8(self.a(), self.readProgramMemory(u8)));
                self.pc += 1;
            },
            Opcode.OR_A_n8 => {
                self.setA(self.or8(self.a(), self.readProgramMemory(u8)));
                self.pc += 1;
            },
            Opcode.XOR_A_n8 => {
                self.setA(self.xor8(self.a(), self.readProgramMemory(u8)));
                self.pc += 1;
            },
            Opcode.CP_A_n8 => {
                _ = self.sub8(self.a(), self.readProgramMemory(u8));
                self.pc += 1;
            },

            Opcode.RST_00 => self.callAddr(0),
            Opcode.RST_08 => self.callAddr(8),
            Opcode.RST_10 => self.callAddr(0x10),
            Opcode.RST_18 => self.callAddr(0x18),
            Opcode.RST_20 => self.callAddr(0x20),
            Opcode.RST_28 => self.callAddr(0x28),
            Opcode.RST_30 => self.callAddr(0x30),
            Opcode.RST_38 => self.callAddr(0x38),
        };

        return switch (opcode_byte & 0o300) {
            0o000 => switch (opcode_byte & 0o007) {
                0 => switch (opcode) {
                    Opcode.NOP => 4,
                    Opcode.LD_a16_addr_SP => 20,
                    Opcode.STOP => 4,
                    Opcode.JR_e8 => 12,
                    Opcode.JR_NZ_e8 => if (!self.getFlags().zero) 12 else 8,
                    Opcode.JR_Z_e8 => if (self.getFlags().zero) 12 else 8,
                    Opcode.JR_NC_e8 => if (!self.getFlags().carry) 12 else 8,
                    Opcode.JR_C_e8 => if (self.getFlags().carry) 12 else 8,
                    else => 12,
                },
                1 => if (((opcode_byte & 0o70) % 16) == 0) 12 else 8,
                2 => 8,
                3 => 8,
                4 => if (opcode == Opcode.INC_HL_ADDR) 12 else 4,
                5 => if (opcode == Opcode.DEC_HL_ADDR) 12 else 4,
                6 => if (opcode == Opcode.LD_HL_ADDR_n8) 12 else 4,
                7 => 4,
                else => return CPUError.UnknownOpcode,
            },
            0o100 => if (opcode_byte & 6 == 6) 8 else 4,
            0o200 => if (opcode_byte & 6 == 6) 8 else 4,
            0o300 => switch (opcode_byte & 0o007) {
                0 => switch (opcode) {
                    Opcode.RET_NZ => if (!self.getFlags().zero) 20 else 8,
                    Opcode.RET_Z => if (self.getFlags().zero) 20 else 8,
                    Opcode.RET_NC => if (!self.getFlags().carry) 20 else 8,
                    Opcode.RET_C => if (self.getFlags().carry) 20 else 8,
                    Opcode.LDH_a8_addr_A => 12,
                    Opcode.ADD_SP_e8 => 16,
                    Opcode.LDH_A_a8_addr => 12,
                    Opcode.LD_HL_SP_add_e8 => 12,
                    else => return CPUError.UnknownOpcode,
                },
                1 => switch (opcode) {
                    Opcode.POP_BC => 12,
                    Opcode.RET => 16,
                    Opcode.POP_DE => 12,
                    Opcode.RETI => 16,
                    Opcode.POP_HL => 12,
                    Opcode.JP_HL => 4,
                    Opcode.POP_AF => 12,
                    Opcode.LD_SP_HL => 8,
                    else => return CPUError.UnknownOpcode,
                },
                2 => switch (opcode) {
                    Opcode.JP_NZ_a16 => if (!self.getFlags().zero) 16 else 12,
                    Opcode.JP_Z_a16 => if (self.getFlags().zero) 16 else 12,
                    Opcode.JP_NC_a16 => if (!self.getFlags().carry) 16 else 12,
                    Opcode.JP_C_a16 => if (self.getFlags().carry) 16 else 12,
                    Opcode.LD_C_addr_A => 8,
                    Opcode.LD_a16_addr_A => 16,
                    Opcode.LD_A_C_addr => 8,
                    Opcode.LD_A_a16_addr => 16,
                    else => return CPUError.UnknownOpcode,
                },
                3 => switch (opcode) {
                    Opcode.JP_a16 => 16,
                    Opcode.PREFIX => switch (self.readMemory(u8, self.pc - 1) & 0o07) {
                        6 => if (self.readMemory(u8, self.pc - 1) & 0o300 == 0o100) 12 else 16,
                        else => 8,
                    },
                    Opcode.DI => 4,
                    Opcode.EI => 4,
                    else => return CPUError.UnknownOpcode,
                },
                4 => switch (opcode) {
                    Opcode.CALL_NZ_a16 => if (!self.getFlags().zero) 24 else 12,
                    Opcode.CALL_Z_a16 => if (self.getFlags().zero) 24 else 12,
                    Opcode.CALL_NC_a16 => if (!self.getFlags().carry) 24 else 12,
                    Opcode.CALL_C_a16 => if (self.getFlags().carry) 24 else 12,
                    else => return CPUError.UnknownOpcode,
                },
                5 => switch (opcode) {
                    Opcode.PUSH_BC => 16,
                    Opcode.CALL_a16 => 24,
                    Opcode.PUSH_DE => 16,
                    Opcode.PUSH_HL => 16,
                    Opcode.PUSH_AF => 16,
                    else => return CPUError.UnknownOpcode,
                },
                6 => 8,
                7 => 16,
                else => return CPUError.UnknownOpcode,
            },
            else => return CPUError.UnknownOpcode,
        };
    }

    fn popStack(self: *Self) u16 {
        self.sp += 2;
        return self.readMemory(u16, self.sp - 2);
    }

    fn pushStack(self: *Self, val: u16) !void {
        self.sp -= 2;
        try self.writeMemory(u16, self.sp, val);
    }

    fn call(self: *Self) !void {
        try self.pushStack(self.pc + 2);
        self.jump(self.readProgramMemory(u16));
    }

    fn callAddr(self: *Self, addr: u16) !void {
        try self.pushStack(self.pc);
        self.jump(addr);
    }

    fn jump(self: *Self, val: u16) void {
        self.pc = val;
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

    fn writeMemory(self: *Self, comptime T: type, addr: u16, val: T) !void {
        const size = @sizeOf(T);

        for (0..size) |i| {
            const byte: u8 = @truncate(val / std.math.pow(T, 2, @truncate(i * 8)));
            try self.memory.write(addr + @as(u16, @truncate(i)), byte);
        }
    }

    fn readMemory(self: *Self, comptime T: type, addr: u16) T {
        const size = @sizeOf(T);

        var value: T = 0;
        for (0..size) |i| {
            const ad = addr + @as(u16, @truncate(i));
            const byte = self.memory.read(ad);
            value += byte * std.math.pow(T, 2, @truncate(i * 8));
        }

        return value;
    }

    fn readProgramMemory(self: *Self, comptime T: type) T {
        return self.readMemory(T, self.pc);
    }

    pub fn a(self: *Self) u8 {
        return @truncate(self.af >> 8);
    }

    pub fn f(self: *Self) u8 {
        return @truncate(self.af);
    }

    pub fn b(self: *Self) u8 {
        return @truncate(self.bc >> 8);
    }

    pub fn c(self: *Self) u8 {
        return @truncate(self.bc);
    }

    pub fn d(self: *Self) u8 {
        return @truncate(self.de >> 8);
    }

    pub fn e(self: *Self) u8 {
        return @truncate(self.de);
    }

    pub fn h(self: *Self) u8 {
        return @truncate(self.hl >> 8);
    }

    pub fn l(self: *Self) u8 {
        return @truncate(self.hl);
    }

    pub fn s(self: *Self) u8 {
        return @truncate(self.sp >> 8);
    }

    pub fn p(self: *Self) u8 {
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
            self.pc -%= 256;
        }
        self.pc +%= val;
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

pub fn new(memory: anytype) CPU {
    return CPU{
        .af = 0,
        .bc = 0,
        .de = 0,
        .hl = 0,
        .sp = 0,
        .pc = 0,
        .ime = false,
        .halted = false,
        .memory = Memory.init(memory),
    };
}

pub const FlagsRegister = packed struct {
    _padding: u4 = 0,
    carry: bool,
    half_carry: bool,
    substract: bool,
    zero: bool,
};

const InterruptRegister = packed struct {
    vBlank: bool,
    lcd: bool,
    timer: bool,
    serial: bool,
    joypad: bool,
    _padding: u3,

    fn new() InterruptRegister {
        return InterruptRegister{
            .vBlank = false,
            .lcd = false,
            .timer = false,
            .serial = false,
            .joypad = false,
            ._padding = 0,
        };
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

    fn createCPU(self: *const Self, memory: *ArrayMemory) !CPU {
        var cpu = new(memory);
        cpu.af = (@as(u16, self.a) << 8) + self.f;
        cpu.bc = (@as(u16, self.b) << 8) + self.c;
        cpu.de = (@as(u16, self.d) << 8) + self.e;
        cpu.hl = (@as(u16, self.h) << 8) + self.l;
        cpu.pc = self.pc - 1;
        cpu.sp = self.sp;

        for (self.ram) |cell| {
            try memory.write(cell.@"0", cell.@"1");
        }

        return cpu;
    }
};

const ArrayMemory = struct {
    mem: [0x10000]u8,

    const Self = @This();

    fn read(self: *Self, addr: u16) u8 {
        return self.mem[addr];
    }

    fn write(self: *Self, addr: u16, val: u8) !void {
        self.mem[addr] = val;
    }
};

fn compareCPUs(alloc: std.mem.Allocator, self: *const CPU, other: *const CPU) !?[]const u8 {
    if (self.af != other.af) return try std.fmt.allocPrint(alloc, "AF: {d} vs {d}", .{ self.af, other.af });
    if (self.bc != other.bc) return try std.fmt.allocPrint(alloc, "BC: {d} vs {d}", .{ self.bc, other.bc });
    if (self.de != other.de) return try std.fmt.allocPrint(alloc, "DE: {d} vs {d}", .{ self.de, other.de });
    if (self.hl != other.hl) return try std.fmt.allocPrint(alloc, "HL: {d} vs {d}", .{ self.hl, other.hl });
    if (self.sp != other.sp) return try std.fmt.allocPrint(alloc, "SP: {d} vs {d}", .{ self.sp, other.sp });
    if (self.pc != other.pc) return try std.fmt.allocPrint(alloc, "PC: {d} vs {d}", .{ self.pc, other.pc });
    return null;
}

test "cpu tests" {
    const prefix = "tests/GameboyCPUTests/v2/";
    _ = prefix; // autofix
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
        "c0", "c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "c9", "ca", "cc", "cd", "ce", "cf", "d0",
        "d1", "d2", "d4", "d5", "d6", "d7", "d8", "d9", "da", "dc", "de", "df", "e0", "e1", "e2", "e5",
        "e6", "e7", "e8", "e9", "ea", "ee", "ef", "f0", "f1", "f2", "f5", "f6", "f7", "f8", "f9", "fa",
        "fe", "ff", "cb",
    };

    for (test_files) |file| {
        const path = try std.fmt.allocPrint(std.testing.allocator, "tests/GameboyCPUTests/v2/{s}.json", .{file});
        defer std.testing.allocator.free(path);
        const data = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 31457280);
        defer std.testing.allocator.free(data);

        const parsed = try std.json.parseFromSlice([]Tests, std.testing.allocator, data, .{});
        defer parsed.deinit();

        for (parsed.value) |t| {
            std.debug.print("Running test {s}...", .{t.name});

            var arr1 = ArrayMemory{ .mem = undefined };
            var arr2 = ArrayMemory{ .mem = undefined };

            var cpu = try t.initial.createCPU(&arr1);
            var final_cpu = try t.final.createCPU(&arr2);

            const duration = try cpu.executeOp();

            if (try compareCPUs(std.testing.allocator, &cpu, &final_cpu)) |err| {
                std.debug.print(" FAILED: {s}\n", .{err});
                std.testing.allocator.free(err);
                return error{FAILED}.FAILED;
            }

            try std.testing.expectEqual(arr1.mem, arr2.mem);

            std.debug.print(" PASSED! Duration: {d}\n", .{duration});
        }
    }
}
