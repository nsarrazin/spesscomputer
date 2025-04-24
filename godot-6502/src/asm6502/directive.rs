use strum_macros::EnumDiscriminants;

use super::code_gen::CodeGeneratorError;

#[derive(Debug, PartialEq, Copy, Clone)]
pub enum DirectiveEnum {
    Org,
    Incbin,
    Byte,
    Word,
    Ascii,
    Asciiz,
    Warning,
    Fail,
    Include,
    Pad,
    Fillvalue,
    Dsb,
    Dsw,
}

#[derive(Debug, PartialEq, Clone, EnumDiscriminants)]
#[strum_discriminants(name(DirectiveType))]
pub enum DirectiveValue {
    Byte(u8),
    Word(u16),
    String(String),
    Reference(String),
}

impl DirectiveValue {
    pub fn get_word(&self) -> Result<u16, CodeGeneratorError> {
        match self {
            DirectiveValue::Word(number) => Ok(*number),
            _ => Err(CodeGeneratorError::ExpectedThis("Word information")),
        }
    }

    pub fn get_byte(&self) -> Result<u8, CodeGeneratorError> {
        match self {
            DirectiveValue::Byte(number) => Ok(*number),
            _ => Err(CodeGeneratorError::ExpectedThis("Byte information")),
        }
    }
}

#[derive(Debug, PartialEq, Copy, Clone)]
pub enum DirectiveVariableSize {
    None,
    Min(usize),
    Length(usize),
}

#[derive(Debug, PartialEq, Clone)]
pub struct DirectiveInfo {
    pub name: &'static str,
    pub directive: DirectiveEnum,
    pub size: DirectiveVariableSize,
    pub values: &'static [DirectiveType],
}

pub const SYSTEM_DIRECTIVES: &[DirectiveInfo] = &[
    DirectiveInfo {
        name: "BYTE",
        directive: DirectiveEnum::Byte,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::Byte, DirectiveType::String],
    },
    DirectiveInfo {
        name: "DB",
        directive: DirectiveEnum::Byte,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::Byte, DirectiveType::String],
    },
    DirectiveInfo {
        name: "WORD",
        directive: DirectiveEnum::Word,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::Byte, DirectiveType::Word],
    },
    DirectiveInfo {
        name: "DW",
        directive: DirectiveEnum::Word,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::Byte, DirectiveType::Word],
    },
    DirectiveInfo {
        name: "ORG",
        directive: DirectiveEnum::Org,
        size: DirectiveVariableSize::Length(1),
        values: &[DirectiveType::Word],
    },
    DirectiveInfo {
        name: "INCBIN",
        directive: DirectiveEnum::Incbin,
        size: DirectiveVariableSize::Length(1),
        values: &[DirectiveType::String],
    },
    DirectiveInfo {
        name: "ASCII",
        directive: DirectiveEnum::Ascii,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::String],
    },
    DirectiveInfo {
        name: "ASCIIZ",
        directive: DirectiveEnum::Asciiz,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::String],
    },
    DirectiveInfo {
        name: "WARNING",
        directive: DirectiveEnum::Warning,
        size: DirectiveVariableSize::Min(1),
        values: &[
            DirectiveType::String,
            DirectiveType::Word,
            DirectiveType::Byte,
        ],
    },
    DirectiveInfo {
        name: "FAIL",
        directive: DirectiveEnum::Fail,
        size: DirectiveVariableSize::Length(1),
        values: &[
            DirectiveType::String,
            DirectiveType::Word,
            DirectiveType::Byte,
        ],
    },
    DirectiveInfo {
        name: "INCLUDE",
        directive: DirectiveEnum::Include,
        size: DirectiveVariableSize::Length(1),
        values: &[DirectiveType::String],
    },
    DirectiveInfo {
        name: "PAD",
        directive: DirectiveEnum::Pad,
        size: DirectiveVariableSize::Length(1),
        values: &[DirectiveType::Word],
    },
    DirectiveInfo {
        name: "FILLVALUE",
        directive: DirectiveEnum::Fillvalue,
        size: DirectiveVariableSize::Length(1),
        values: &[DirectiveType::Byte],
    },
    DirectiveInfo {
        name: "DSB",
        directive: DirectiveEnum::Dsb,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::Byte, DirectiveType::Word],
    },
    DirectiveInfo {
        name: "DSW",
        directive: DirectiveEnum::Dsw,
        size: DirectiveVariableSize::Min(1),
        values: &[DirectiveType::Byte, DirectiveType::Word],
    },
];
