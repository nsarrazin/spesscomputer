#[cfg(not(test))]
use log::{info, warn};
use std::fs::File;
use std::io::BufReader;
use std::io::Read;
use std::{collections::HashMap, str::Utf8Error}; // Use log crate when building application

#[cfg(test)]
use std::{println as info, println as warn}; // Workaround to use prinltn! for logs.
use thiserror::Error;

use super::ast::{InstrInfo, InstrInfoRegister, InstrValue};
use super::context::Context;
use super::opcode::BRANCH_INSTS;
use super::tool::print_error;
use super::{
    ast::{Ast, BranchType},
    directive::{DirectiveEnum, DirectiveValue},
    opcode::{ModeType, MODES},
};

#[derive(Error, Debug)]
pub enum CodeGeneratorError {
    #[error("Unsupported directive value")]
    UnsupportedDirectiveValue,
    #[error("Internal error")]
    InternalError,
    #[error("Illegal opcode")]
    IllegalOpcode,
    #[error("Number not applicable")]
    NumberNotApplicable,
    #[error("Branch information not found")]
    UnresolvedBranches,
    #[error("Reference information not found")]
    UnresolvedReference,
    #[error("Expected &String")]
    StringExpected,
    #[error("IO Error ({0})")]
    IOError(#[from] std::io::Error),
    #[error("Text convertion issue ({0})")]
    Utf8Error(#[from] Utf8Error),
    #[error("Expected {0}")]
    ExpectedThis(&'static str),
    #[error("{0}")]
    ProgramFailed(String),
}

#[derive(Debug)]
pub struct CodeGenerator {
    pub index: usize,
    pub size: usize,
    pub silent: bool,

    pub start_point: u16,
    pub fillvalue: u8,
    pub branches: HashMap<String, usize>,
    pub local_branches: HashMap<String, usize>,
    pub unresolved_relative_jump: Vec<(String, usize, usize)>,
    pub unresolved_absolute_jumps: Vec<(String, usize, usize)>,
    pub unresolved_local_branches: Vec<(String, usize, usize)>,
}

impl CodeGenerator {
    pub fn new() -> Self {
        Self {
            index: 0,
            size: 0,
            silent: false,
            start_point: Default::default(),
            fillvalue: 0x00,
            branches: Default::default(),
            local_branches: Default::default(),
            unresolved_local_branches: Default::default(),
            unresolved_relative_jump: Default::default(),
            unresolved_absolute_jumps: Default::default(),
        }
    }

    fn empty_check(&self) -> Result<(), CodeGeneratorError> {
        match self.index >= self.size {
            true => Err(CodeGeneratorError::InternalError),
            false => Ok(()),
        }
    }

    fn eat(&mut self) -> Result<usize, CodeGeneratorError> {
        self.empty_check()?;
        self.index += 1;
        Ok(self.index - 1)
    }

    fn push_number(
        &mut self,
        target: &mut Vec<u8>,
        number: u16,
        mode: ModeType,
    ) -> Result<(), CodeGeneratorError> {
        match mode {
            ModeType::Relative
            | ModeType::Immediate
            | ModeType::ZeroPage
            | ModeType::ZeroPageX
            | ModeType::ZeroPageY
            | ModeType::IndirectX
            | ModeType::IndirectY => {
                target.push(number as u8);
            }
            ModeType::Implied => return Err(CodeGeneratorError::NumberNotApplicable),
            ModeType::Accumulator => return Err(CodeGeneratorError::NumberNotApplicable),
            ModeType::Absolute | ModeType::AbsoluteX | ModeType::AbsoluteY | ModeType::Indirect => {
                target.push(number as u8);
                target.push((number >> 8) as u8);
            }
        };

        Ok(())
    }

    fn build_relative_jump(
        target: &mut [u8],
        ast_index: usize,
        reference: &String,
        branches: &mut HashMap<String, usize>,
        unresolved_jump: &mut Vec<(String, usize, usize)>,
    ) -> (u16, ModeType) {
        match branches.get(reference) {
            Some(branch_position) => (
                (*branch_position as i16 - (target.len() + 2) as i16) as u16,
                ModeType::Relative,
            ),
            None => {
                unresolved_jump.push((reference.clone(), target.len() + 1, ast_index));
                (0, ModeType::Relative)
            }
        }
    }

    fn build_absolute_jump(
        target: &mut [u8],
        ast_index: usize,
        reference: &String,
        branches: &mut HashMap<String, usize>,
        unresolved_jump: &mut Vec<(String, usize, usize)>,
    ) -> (u16, ModeType) {
        match branches.get(reference) {
            Some(branch_position) => (*branch_position as u16, ModeType::Absolute),
            None => {
                unresolved_jump.push((reference.clone(), target.len() + 1, ast_index));
                (0, ModeType::Absolute)
            }
        }
    }

    fn generate_instr(
        &mut self,
        target: &mut Vec<u8>,
        ast_index: usize,
        instr: usize,
        value: &InstrInfo,
    ) -> Result<(), CodeGeneratorError> {
        let modes = MODES[instr];
        let mut found = false;
        let relative_jump = BRANCH_INSTS.contains(&instr);

        let (number, mut possible_mode) = match &value.value {
            InstrValue::Byte(byte) => (*byte as u16, ModeType::ZeroPage),
            InstrValue::Word(word) => (*word, ModeType::Absolute),
            InstrValue::Reference(reference) => match relative_jump {
                true => Self::build_relative_jump(
                    target,
                    ast_index,
                    reference,
                    &mut self.branches,
                    &mut self.unresolved_relative_jump,
                ),
                false => Self::build_absolute_jump(
                    target,
                    ast_index,
                    reference,
                    &mut self.branches,
                    &mut self.unresolved_absolute_jumps,
                ),
            },
            InstrValue::LocalReference(reference) => match relative_jump {
                true => Self::build_relative_jump(
                    target,
                    ast_index,
                    reference,
                    &mut self.local_branches,
                    &mut self.unresolved_local_branches,
                ),
                false => Self::build_absolute_jump(
                    target,
                    ast_index,
                    reference,
                    &mut self.local_branches,
                    &mut self.unresolved_local_branches,
                ),
            },
        };

        if value.in_parenthesis {
            possible_mode = match value.register {
                InstrInfoRegister::None => ModeType::Indirect,
                InstrInfoRegister::X => ModeType::IndirectX,
                InstrInfoRegister::Y => ModeType::IndirectY,
            };
        } else {
            possible_mode = match value.register {
                InstrInfoRegister::None => possible_mode,
                InstrInfoRegister::X => match possible_mode {
                    ModeType::ZeroPage => ModeType::ZeroPageX,
                    _ => ModeType::AbsoluteX,
                },
                InstrInfoRegister::Y => match possible_mode {
                    ModeType::ZeroPage => ModeType::ZeroPageY,
                    _ => ModeType::AbsoluteY,
                },
            };
        }

        if value.is_immediate {
            possible_mode = ModeType::Immediate;
        }

        if BRANCH_INSTS.contains(&instr) {
            possible_mode = ModeType::Relative;
        }

        for search_mode in modes.iter() {
            if search_mode.mode == possible_mode {
                target.push(search_mode.opcode);
                self.push_number(target, number, possible_mode)?;
                found = true;
                break;
            }
        }

        if !found {
            return Err(CodeGeneratorError::IllegalOpcode);
        }
        Ok(())
    }

    fn generate_implied(
        &mut self,
        target: &mut Vec<u8>,
        position: usize,
    ) -> Result<(), CodeGeneratorError> {
        let modes = MODES[position];
        for search_mode in modes.iter() {
            if search_mode.mode == ModeType::Implied {
                target.push(search_mode.opcode);
                break;
            }
        }
        Ok(())
    }

    fn generate_branch(
        &mut self,
        target: &mut [u8],
        name: &str,
        branch_type: BranchType,
    ) -> Result<(), CodeGeneratorError> {
        let absolute_address = self.start_point as usize + target.len();
        match branch_type {
            BranchType::Generic => {
                self.branches.insert(name.to_owned(), absolute_address);
                self.local_branches.clear();
            }
            BranchType::Local => {
                self.local_branches.insert(name.to_owned(), target.len());
                self.build_unresolved_local_branches(target)?;
            }
        };
        Ok(())
    }

    fn build_unresolved_relative_jump(
        &mut self,
        target: &mut [u8],
    ) -> Result<(), CodeGeneratorError> {
        for (branch_name, position, _) in self.unresolved_relative_jump.iter() {
            match self.branches.get(branch_name) {
                Some(branch_position) => {
                    target[*position] = (*branch_position as i8 - *position as i8 - 1) as u8
                }
                None => return Err(CodeGeneratorError::UnresolvedBranches),
            };
        }

        Ok(())
    }

    fn build_unresolved_local_branches(
        &mut self,
        target: &mut [u8],
    ) -> Result<(), CodeGeneratorError> {
        for (branch_name, position, _) in self.unresolved_local_branches.iter() {
            if let Some(branch_position) = self.local_branches.get(branch_name) {
                target[*position] = (*branch_position as i8 - *position as i8 - 1) as u8;
            };
        }

        Ok(())
    }

    fn build_unresolved_jumps(&mut self, target: &mut [u8]) -> Result<(), CodeGeneratorError> {
        for (branch_name, position, _) in self.unresolved_absolute_jumps.iter() {
            match self.branches.get(branch_name) {
                Some(branch_position) => {
                    let jump_position = *branch_position as u16;

                    target[*position] = jump_position as u8;
                    target[*position + 1] = (jump_position >> 8) as u8;
                }
                None => return Err(CodeGeneratorError::UnresolvedBranches),
            };
        }

        Ok(())
    }

    fn directive_org(&mut self, values: &[DirectiveValue]) -> Result<(), CodeGeneratorError> {
        self.start_point = values[0].get_word()?;
        Ok(())
    }

    fn directive_incbin(
        &mut self,
        target: &mut Vec<u8>,
        values: &[DirectiveValue],
    ) -> Result<(), CodeGeneratorError> {
        let file_path = match &values[0] {
            DirectiveValue::String(name) => name,
            _ => return Err(CodeGeneratorError::StringExpected),
        };

        let file = File::open(file_path)?;

        let buffer_reader: BufReader<File> = BufReader::new(file);
        for buffer in buffer_reader.bytes() {
            match buffer {
                Ok(byte) => target.push(byte),
                Err(error) => return Err(CodeGeneratorError::IOError(error)),
            }
        }
        Ok(())
    }

    fn directive_byte(
        &mut self,
        target: &mut Vec<u8>,
        values: &[DirectiveValue],
    ) -> Result<(), CodeGeneratorError> {
        for value in values.iter() {
            match value {
                DirectiveValue::Byte(byte) => target.push(*byte),
                DirectiveValue::String(string) => {
                    string.as_bytes().iter().for_each(|byte| target.push(*byte))
                }
                _ => return Err(CodeGeneratorError::ExpectedThis("byte or &String")),
            };
        }
        Ok(())
    }

    fn directive_word(
        &mut self,
        target: &mut Vec<u8>,
        values: &[DirectiveValue],
    ) -> Result<(), CodeGeneratorError> {
        for value in values.iter() {
            match value {
                DirectiveValue::Byte(word) => {
                    target.push(*word);
                    target.push(0x00);
                }
                DirectiveValue::Word(word) => {
                    target.push(*word as u8);
                    target.push((*word >> 8) as u8);
                }
                _ => return Err(CodeGeneratorError::ExpectedThis("word")),
            }
        }
        Ok(())
    }

    fn directive_ascii(
        &mut self,
        target: &mut Vec<u8>,
        values: &[DirectiveValue],
        add_null: bool,
    ) -> Result<(), CodeGeneratorError> {
        for value in values.iter() {
            let string = match value {
                DirectiveValue::String(string) => string,
                _ => return Err(CodeGeneratorError::ExpectedThis("string")),
            };

            string.as_bytes().iter().for_each(|byte| target.push(*byte));

            let bytes = string.as_bytes();
            if add_null && bytes[bytes.len() - 1] != 0x0 {
                target.push(0x0);
            }
        }
        Ok(())
    }

    fn directive_warning(&mut self, values: &[DirectiveValue]) -> Result<(), CodeGeneratorError> {
        let mut message = String::new();

        for value in values.iter() {
            match value {
                DirectiveValue::String(string) => message += &string[..],
                DirectiveValue::Word(word) => message += &format!("0x{:02X}", word),
                DirectiveValue::Byte(byte) => message += &format!("0x{:02X}", byte),
                _ => return Err(CodeGeneratorError::ExpectedThis("string")),
            };
        }

        if !self.silent {
            warn!("{}", message);
        }
        Ok(())
    }

    fn directive_fail(&mut self, values: &[DirectiveValue]) -> Result<(), CodeGeneratorError> {
        let mut message = String::new();

        for value in values.iter() {
            match value {
                DirectiveValue::String(string) => message += &string[..],
                DirectiveValue::Word(word) => message += &format!("0x{:02X}", word),
                DirectiveValue::Byte(byte) => message += &format!("0x{:02X}", byte),
                _ => return Err(CodeGeneratorError::ExpectedThis("string")),
            };
        }
        Err(CodeGeneratorError::ProgramFailed(message))
    }

    fn directive_pad(
        &mut self,
        target: &mut Vec<u8>,
        values: &[DirectiveValue],
    ) -> Result<(), CodeGeneratorError> {
        let address = match &values[0] {
            DirectiveValue::Word(address) => *address,
            _ => return Err(CodeGeneratorError::ExpectedThis("word")),
        };

        for _ in 0..(address as usize - target.len()) {
            target.push(self.fillvalue);
        }

        Ok(())
    }

    fn directive_fillvalue(&mut self, values: &[DirectiveValue]) -> Result<(), CodeGeneratorError> {
        self.fillvalue = values[0].get_byte()?;
        Ok(())
    }

    fn directive_define_storage_byte(
        &self,
        target: &mut Vec<u8>,
        values: &[DirectiveValue],
    ) -> Result<(), CodeGeneratorError> {
        let mut filler = 0x00;
        let times = match &values[0] {
            DirectiveValue::Byte(byte) => *byte,
            DirectiveValue::Word(word) => *word as u8,
            _ => return Err(CodeGeneratorError::UnsupportedDirectiveValue),
        };

        if values.len() > 1 {
            if let Ok(new_filler) = values[1].get_byte() {
                filler = new_filler;
            }
        }

        for _ in 0..times {
            target.push(filler);
        }

        Ok(())
    }

    fn directive_define_storage_word(
        &self,
        target: &mut Vec<u8>,
        values: &[DirectiveValue],
    ) -> Result<(), CodeGeneratorError> {
        let mut filler: u16 = 0x00;
        let times = match &values[0] {
            DirectiveValue::Byte(byte) => *byte as u16,
            DirectiveValue::Word(word) => *word,
            _ => return Err(CodeGeneratorError::UnsupportedDirectiveValue),
        };

        if values.len() > 1 {
            if let Ok(new_filler) = values[1].get_word() {
                filler = new_filler;
            }
        }

        for _ in 0..times {
            target.push(filler as u8);
            target.push((filler >> 8) as u8);
        }

        Ok(())
    }

    fn generate_directive(
        &mut self,
        target: &mut Vec<u8>,
        option: DirectiveEnum,
        values: &[DirectiveValue],
    ) -> Result<(), CodeGeneratorError> {
        match option {
            DirectiveEnum::Org => self.directive_org(values)?,
            DirectiveEnum::Incbin => self.directive_incbin(target, values)?,
            DirectiveEnum::Byte => self.directive_byte(target, values)?,
            DirectiveEnum::Word => self.directive_word(target, values)?,
            DirectiveEnum::Ascii => self.directive_ascii(target, values, false)?,
            DirectiveEnum::Asciiz => self.directive_ascii(target, values, true)?,
            DirectiveEnum::Warning => self.directive_warning(values)?,
            DirectiveEnum::Fail => self.directive_fail(values)?,
            DirectiveEnum::Include => (),
            DirectiveEnum::Pad => self.directive_pad(target, values)?,
            DirectiveEnum::Fillvalue => self.directive_fillvalue(values)?,
            DirectiveEnum::Dsb => self.directive_define_storage_byte(target, values)?,
            DirectiveEnum::Dsw => self.directive_define_storage_word(target, values)?,
        };
        Ok(())
    }

    fn inner_generate(&mut self, context: &mut Context) -> Result<(), CodeGeneratorError> {
        self.size = context.asts.borrow().len();
        let asts = context.asts.borrow();

        while self.size > self.index {
            let ast_index = self.eat()?;
            let ast = asts.get(ast_index).map(|item| &item.ast);
            let before_len = context.target.len();

            match ast {
                Some(Ast::InstrImplied(position)) => {
                    self.generate_implied(&mut context.target, *position)?
                }
                Some(Ast::Instr(position, value)) => {
                    self.generate_instr(&mut context.target, ast_index, *position, value)?
                }
                Some(Ast::Branch(name, branch_type)) => {
                    self.generate_branch(&mut context.target, name, *branch_type)?
                }
                Some(Ast::Directive(option, values)) => {
                    self.generate_directive(&mut context.target, *option, values)?
                }
                None => return Err(CodeGeneratorError::InternalError),
            };

            let after_len = context.target.len();
            if after_len > before_len {
                let line = asts[ast_index].line as u32;
                let mut map = context.offset_to_line.borrow_mut();
                for off in before_len..after_len {
                    if off <= u16::MAX as usize {
                        map.insert(off as u16, line);
                    }
                }
            }
        }

        self.build_unresolved_relative_jump(&mut context.target)?;
        self.build_unresolved_jumps(&mut context.target)?;
        Ok(())
    }

    pub fn generate(&mut self, context: Context) -> Result<Context, CodeGeneratorError> {
        let mut context = context;

        match self.inner_generate(&mut context) {
            Ok(_) => Ok(context),
            Err(error) => {
                let asts = context.asts.borrow();
                let ast = &asts[self.index - 1];
                if !context.silent {
                    let code_file = &context.code_files.borrow()[0];
                    print_error(&code_file.data, &error, ast.line, ast.column, ast.end);
                }
                Err(error)
            }
        }
    }

    pub fn dump(&self, context: &Context) {
        info!("Binary Output");
        let total_byte_per_row = 8;
        let position = self.start_point;
        let total_bytes = context.target.len();

        print!("{:04X}: ", position);
        for (index, data) in context.target.iter().enumerate() {
            print!("{:02X} ", data);

            if index > 1 && (index + 1) % total_byte_per_row == 0 && index != total_bytes - 1 {
                println!();
                print!("{:04X}: ", position + 1 + (index as u16));
            }
        }
        println!()
    }
}
