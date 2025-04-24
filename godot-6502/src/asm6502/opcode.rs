#[derive(Debug, PartialEq, Copy, Clone)]
pub enum ModeType {
    ZeroPage,
    Implied,
    Relative,
    Immediate,
    Accumulator,
    Absolute,
    ZeroPageX,
    ZeroPageY,
    AbsoluteX,
    AbsoluteY,
    IndirectX,
    IndirectY,
    Indirect
}

#[derive(Debug)]
pub struct ModeInfo {
    pub mode: ModeType,
    pub opcode: u8
}

pub const INSTS: [&[u8; 3]; 56] = [
    b"ADC", b"AND", b"ASL", b"BCC", b"BCS", b"BEQ", b"BIT", b"BMI", b"BNE", b"BPL", b"BRK", b"BVC", b"BVS",
    b"CLC", b"CLD", b"CLI", b"CLV", b"CMP", b"CPX", b"CPY", b"DEC", b"DEX", b"DEY", b"EOR", b"INC", b"INX",
    b"INY", b"JMP", b"JSR", b"LDA", b"LDX", b"LDY", b"LSR", b"NOP", b"ORA", b"PHA", b"PHP", b"PLA", b"PLP",
    b"ROL", b"ROR", b"RTI", b"RTS", b"SBC", b"SEC", b"SED", b"SEI", b"STA", b"STX", b"STY", b"TAX", b"TAY",
    b"TSX", b"TXA", b"TXS", b"TYA",
];

pub const INSTS_SIZE: [u8; 56] = [2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 2, 2, 1, 1, 3, 3, 2, 2, 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1];

#[allow(unused_variables)]
pub const INSTR_NAMES: [&str; 56] = ["ADC", "AND", "ASL", "BCC", "BCS", "BEQ", "BIT", "BMI", "BNE", "BPL", "BRK", "BVC", "BVS", "CLC", "CLD", "CLI", "CLV", "CMP", "CPX", "CPY", "DEC", "DEX", "DEY", "EOR", "INC", "INX", "INY", "JMP", "JSR", "LDA", "LDX", "LDY", "LSR", "NOP", "ORA", "PHA", "PHP", "PLA", "PLP", "ROL", "ROR", "RTI", "RTS", "SBC", "SEC", "SED", "SEI", "STA", "STX", "STY", "TAX", "TAY", "TSX", "TXA", "TXS", "TYA"];

pub const ADC_MODES: [ModeInfo; 8] = [ModeInfo { mode: ModeType::Immediate, opcode: 0x69}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x65}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x75}, ModeInfo { mode: ModeType::Absolute, opcode: 0x6D}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x7D}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0x79}, ModeInfo { mode: ModeType::IndirectX, opcode: 0x61}, ModeInfo { mode: ModeType::IndirectY, opcode: 0x71}];
pub const AND_MODES: [ModeInfo; 8] = [ModeInfo { mode: ModeType::Immediate, opcode: 0x29}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x25}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x35}, ModeInfo { mode: ModeType::Absolute, opcode: 0x2D}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x3D}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0x39}, ModeInfo { mode: ModeType::IndirectX, opcode: 0x21}, ModeInfo { mode: ModeType::IndirectY, opcode: 0x31}];
pub const ASL_MODES: [ModeInfo; 5] = [ModeInfo { mode: ModeType::Accumulator, opcode: 0x0A}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x06}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x16}, ModeInfo { mode: ModeType::Absolute, opcode: 0x0E}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x1E}];
pub const BCC_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0x90}];
pub const BCS_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0xB0}];
pub const BEQ_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0xF0}];
pub const BIT_MODES: [ModeInfo; 2] = [ModeInfo { mode: ModeType::ZeroPage, opcode: 0x24}, ModeInfo { mode: ModeType::Absolute, opcode: 0x2C}];
pub const BMI_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0x30}];
pub const BNE_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0xD0}];
pub const BPL_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0x10}];
pub const BRK_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x00}];
pub const BVC_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0x50}];
pub const BVS_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Relative, opcode: 0x70}];
pub const CLC_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x18}];
pub const CLD_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xD8}];
pub const CLI_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x58}];
pub const CLV_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xB8}];
pub const CMP_MODES: [ModeInfo; 8] = [ModeInfo { mode: ModeType::Immediate, opcode: 0xC9}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0xC5}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0xD5}, ModeInfo { mode: ModeType::Absolute, opcode: 0xCD}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0xDD}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0xD9}, ModeInfo { mode: ModeType::IndirectX, opcode: 0xC1}, ModeInfo { mode: ModeType::IndirectY, opcode: 0xD1}];
pub const CPX_MODES: [ModeInfo; 3] = [ModeInfo { mode: ModeType::Immediate, opcode: 0xE0}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0xE4}, ModeInfo { mode: ModeType::Absolute, opcode: 0xEC}];
pub const CPY_MODES: [ModeInfo; 3] = [ModeInfo { mode: ModeType::Immediate, opcode: 0xC0}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0xC4}, ModeInfo { mode: ModeType::Absolute, opcode: 0xCC}];
pub const DEC_MODES: [ModeInfo; 4] = [ModeInfo { mode: ModeType::ZeroPage, opcode: 0xC6}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0xD6}, ModeInfo { mode: ModeType::Absolute, opcode: 0xCE}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0xDE}];
pub const DEX_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xCA}];
pub const DEY_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x88}];
pub const EOR_MODES: [ModeInfo; 8] = [ModeInfo { mode: ModeType::Immediate, opcode: 0x49}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x45}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x55}, ModeInfo { mode: ModeType::Absolute, opcode: 0x4D}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x5D}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0x59}, ModeInfo { mode: ModeType::IndirectX, opcode: 0x41}, ModeInfo { mode: ModeType::IndirectY, opcode: 0x51}];
pub const INC_MODES: [ModeInfo; 4] = [ModeInfo { mode: ModeType::ZeroPage, opcode: 0xE6}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0xF6}, ModeInfo { mode: ModeType::Absolute, opcode: 0xEE}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0xFE}];
pub const INX_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xE8}];
pub const INY_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xC8}];
pub const JMP_MODES: [ModeInfo; 2] = [ModeInfo { mode: ModeType::Absolute, opcode: 0x4C}, ModeInfo { mode: ModeType::Indirect, opcode: 0x6C}];
pub const JSR_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Absolute, opcode: 0x20}];
pub const LDA_MODES: [ModeInfo; 8] = [ModeInfo { mode: ModeType::Immediate, opcode: 0xA9}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0xA5}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0xB5}, ModeInfo { mode: ModeType::Absolute, opcode: 0xAD}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0xBD}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0xB9}, ModeInfo { mode: ModeType::IndirectX, opcode: 0xA1}, ModeInfo { mode: ModeType::IndirectY, opcode: 0xB1}];
pub const LDX_MODES: [ModeInfo; 5] = [ModeInfo { mode: ModeType::Immediate, opcode: 0xA2}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0xA6}, ModeInfo { mode: ModeType::ZeroPageY, opcode: 0xB6}, ModeInfo { mode: ModeType::Absolute, opcode: 0xAE}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0xBE}];
pub const LDY_MODES: [ModeInfo; 5] = [ModeInfo { mode: ModeType::Immediate, opcode: 0xA0}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0xA4}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0xB4}, ModeInfo { mode: ModeType::Absolute, opcode: 0xAC}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0xBC}];
pub const LSR_MODES: [ModeInfo; 5] = [ModeInfo { mode: ModeType::Accumulator, opcode: 0x4A}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x46}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x56}, ModeInfo { mode: ModeType::Absolute, opcode: 0x4E}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x5E}];
pub const NOP_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xEA}];
pub const ORA_MODES: [ModeInfo; 8] = [ModeInfo { mode: ModeType::Immediate, opcode: 0x09}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x05}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x15}, ModeInfo { mode: ModeType::Absolute, opcode: 0x0D}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x1D}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0x19}, ModeInfo { mode: ModeType::IndirectX, opcode: 0x01}, ModeInfo { mode: ModeType::IndirectY, opcode: 0x11}];
pub const PHA_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x48}];
pub const PHP_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x08}];
pub const PLA_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x68}];
pub const PLP_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x28}];
pub const ROL_MODES: [ModeInfo; 5] = [ModeInfo { mode: ModeType::Accumulator, opcode: 0x2A}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x26}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x36}, ModeInfo { mode: ModeType::Absolute, opcode: 0x2E}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x3E}];
pub const ROR_MODES: [ModeInfo; 5] = [ModeInfo { mode: ModeType::Accumulator, opcode: 0x6A}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0x66}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x76}, ModeInfo { mode: ModeType::Absolute, opcode: 0x6E}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x7E}];
pub const RTI_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x40}];
pub const RTS_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x60}];
pub const SBC_MODES: [ModeInfo; 8] = [ModeInfo { mode: ModeType::Immediate, opcode: 0xE9}, ModeInfo { mode: ModeType::ZeroPage, opcode: 0xE5}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0xF5}, ModeInfo { mode: ModeType::Absolute, opcode: 0xED}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0xFD}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0xF9}, ModeInfo { mode: ModeType::IndirectX, opcode: 0xE1}, ModeInfo { mode: ModeType::IndirectY, opcode: 0xF1}];
pub const SEC_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x38}];
pub const SED_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xF8}];
pub const SEI_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x78}];
pub const STA_MODES: [ModeInfo; 7] = [ModeInfo { mode: ModeType::ZeroPage, opcode: 0x85}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x95}, ModeInfo { mode: ModeType::Absolute, opcode: 0x8D}, ModeInfo { mode: ModeType::AbsoluteX, opcode: 0x9D}, ModeInfo { mode: ModeType::AbsoluteY, opcode: 0x99}, ModeInfo { mode: ModeType::IndirectX, opcode: 0x81}, ModeInfo { mode: ModeType::IndirectY, opcode: 0x91}];
pub const STX_MODES: [ModeInfo; 3] = [ModeInfo { mode: ModeType::ZeroPage, opcode: 0x86}, ModeInfo { mode: ModeType::ZeroPageY, opcode: 0x96}, ModeInfo { mode: ModeType::Absolute, opcode: 0x8E}];
pub const STY_MODES: [ModeInfo; 3] = [ModeInfo { mode: ModeType::ZeroPage, opcode: 0x84}, ModeInfo { mode: ModeType::ZeroPageX, opcode: 0x94}, ModeInfo { mode: ModeType::Absolute, opcode: 0x8C}];
pub const TAX_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xAA}];
pub const TAY_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xA8}];
pub const TSX_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0xBA}];
pub const TXA_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x8A}];
pub const TXS_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x9A}];
pub const TYA_MODES: [ModeInfo; 1] = [ModeInfo { mode: ModeType::Implied, opcode: 0x98}];


pub const MODES: [&[ModeInfo]; 56] = [&ADC_MODES, &AND_MODES, &ASL_MODES, &BCC_MODES, &BCS_MODES, &BEQ_MODES, &BIT_MODES, &BMI_MODES, &BNE_MODES, &BPL_MODES, &BRK_MODES, &BVC_MODES, &BVS_MODES, &CLC_MODES, &CLD_MODES, &CLI_MODES, &CLV_MODES, &CMP_MODES, &CPX_MODES, &CPY_MODES, &DEC_MODES, &DEX_MODES, &DEY_MODES, &EOR_MODES, &INC_MODES, &INX_MODES, &INY_MODES, &JMP_MODES, &JSR_MODES, &LDA_MODES, &LDX_MODES, &LDY_MODES, &LSR_MODES, &NOP_MODES, &ORA_MODES, &PHA_MODES, &PHP_MODES, &PLA_MODES, &PLP_MODES, &ROL_MODES, &ROR_MODES, &RTI_MODES, &RTS_MODES, &SBC_MODES, &SEC_MODES, &SED_MODES, &SEI_MODES, &STA_MODES, &STX_MODES, &STY_MODES, &TAX_MODES, &TAY_MODES, &TSX_MODES, &TXA_MODES, &TXS_MODES, &TYA_MODES];
pub const BRANCH_INSTS: [usize; 8] = [3, 4, 5, 7, 8, 9, 11, 12];
pub const JUMP_INSTS: [usize; 2] = [27, 28];