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
}

#[derive(Debug, PartialEq, Copy, Clone, EnumDiscriminants)]
#[strum_discriminants(name(DirectiveType))]
pub enum DirectiveValue {
    Byte(u8),
    Word(u16),
    String(&'a [u8]),
    Reference(&'a [u8]),
}

#[derive(Debug, PartialEq, Copy, Clone)]
pub enum DirectiveVariableSize {
    None,
    Min(usize),
    Length(usize),
}

#[derive(Debug, PartialEq, Clone)]
pub struct DirectiveInfo {
    pub name: &'static [u8],
    pub directive: DirectiveEnum,
    pub size: DirectiveVariableSize,
    pub value_types: &'static [DirectiveType],
}

pub const SYSTEM_DIRECTIVES: &[DirectiveInfo] = &[
    DirectiveInfo {
        name: b"BYTE",
        directive: DirectiveEnum::Byte,
        size: DirectiveVariableSize::Min(1),
        value_types: &[DirectiveType::Byte, DirectiveType::String],
    },
    DirectiveInfo {
        name: b"DB",
        directive: DirectiveEnum::Byte,
        size: DirectiveVariableSize::Min(1),
        value_types: &[DirectiveType::Byte, DirectiveType::String],
    },
    DirectiveInfo {
        name: b"DB",
        directive: DirectiveEnum::Word,
        size: DirectiveVariableSize::Min(1),
        value_types: &[DirectiveType::Word],
    },
    DirectiveInfo {
        name: b"ORG",
        directive: DirectiveEnum::Org,
        size: DirectiveVariableSize::Length(1),
        value_types: &[DirectiveType::Word],
    },
    DirectiveInfo {
        name: b"INCBIN",
        directive: DirectiveEnum::Incbin,
        size: DirectiveVariableSize::Length(1),
        value_types: &[DirectiveType::String],
    },
    DirectiveInfo {
        name: b"ASCII",
        directive: DirectiveEnum::Ascii,
        size: DirectiveVariableSize::Min(1),
        value_types: &[DirectiveType::String],
    },
    DirectiveInfo {
        name: b"ASCIIZ",
        directive: DirectiveEnum::Asciiz,
        size: DirectiveVariableSize::Min(1),
        value_types: &[DirectiveType::String],
    },
    DirectiveInfo {
        name: b"WARNING",
        directive: DirectiveEnum::Warning,
        size: DirectiveVariableSize::Length(1),
        value_types: &[DirectiveType::String],
    },
];
