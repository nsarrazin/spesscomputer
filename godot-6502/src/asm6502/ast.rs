use std::{
    cell::{Cell, RefCell},
    fs::File,
    io::Read,
    path::PathBuf,
};

#[cfg(not(test))]
use log::{info, warn}; // Use log crate when building application

#[cfg(test)]
use std::{println as info, println as warn}; // Workaround to use prinltn! for logs.
use thiserror::Error;

use super::{
    context::Context,
    directive::{DirectiveEnum, DirectiveType, DirectiveValue, SYSTEM_DIRECTIVES},
    opcode::{BRANCH_INSTS, INSTS_SIZE},
    parser::{Parser, Token, TokenType},
    tool::print_error,
};

#[derive(Debug, PartialEq)]
pub enum InstrValue {
    Byte(u8),
    Word(u16),
    Reference(String),
    LocalReference(String),
}

#[derive(Debug, PartialEq)]
pub enum InstrInfoRegister {
    None,
    X,
    Y,
}

#[derive(Debug, PartialEq)]
pub struct InstrInfo {
    pub value: InstrValue,
    pub is_immediate: bool,
    pub in_parenthesis: bool,
    pub register: InstrInfoRegister,
}

#[derive(Debug, Copy, Clone)]
pub enum BranchType {
    Generic,
    Local,
}

#[derive(Debug)]
pub enum Ast {
    InstrImplied(usize),
    Instr(usize, InstrInfo),
    Branch(String, BranchType),
    Directive(DirectiveEnum, Vec<DirectiveValue>),
}

#[derive(Debug)]
pub struct AstInfo {
    pub line: usize,
    pub column: usize,
    pub ast: Ast,
    pub end: usize,
}

#[derive(Debug, Error)]
pub enum AstGeneratorError {
    #[error("Syntax issue")]
    SyntaxIssue {
        #[allow(dead_code)]
        line: usize,
        #[allow(dead_code)]
        column: usize,
        #[allow(dead_code)]
        end: usize,
        #[allow(dead_code)]
        message: String,
    },

    #[error("Out of scope")]
    OutOfScope,

    #[error("Internal error")]
    InternalError,

    #[error("IO Error ({0})")]
    IOError(#[from] std::io::Error),

    #[error("'{0}' reference already defined)")]
    ReferenceAlreadyDefined(String),
}

impl AstGeneratorError {
    pub fn syntax_issue(context: &Context, token_index: usize, message: String) -> Self {
        let token_info = &context.tokens.borrow()[token_index];
        AstGeneratorError::SyntaxIssue {
            column: token_info.column,
            end: token_info.end,
            line: token_info.line,
            message,
        }
    }
}

#[derive(Debug)]
pub struct AstGenerator {
    pub index: Cell<usize>,
    pub(crate) size: Cell<usize>,
    pub include_asm: RefCell<Option<DirectiveValue>>,
}

impl AstGenerator {
    pub fn new() -> Self {
        Self {
            index: Cell::new(0),
            size: Cell::new(0),
            include_asm: Default::default(),
        }
    }

    fn empty_check(&self) -> Result<(), AstGeneratorError> {
        match self.index.get() >= self.size.get() {
            true => Err(AstGeneratorError::OutOfScope),
            false => Ok(()),
        }
    }

    fn eat(&self) -> Result<usize, AstGeneratorError> {
        self.empty_check()?;
        self.index.set(self.index.get() + 1);
        Ok(self.index.get() - 1)
    }

    fn peek(&self) -> Result<usize, AstGeneratorError> {
        self.empty_check()?;
        Ok(self.index.get())
    }

    fn eat_expected(
        &self,
        context: &Context,
        token_type: TokenType,
        error: AstGeneratorError,
    ) -> Result<(), AstGeneratorError> {
        let token_index = self.eat()?;
        let token = &context.tokens.borrow()[token_index];

        if TokenType::from(&token.token) != token_type {
            return Err(error);
        }
        Ok(())
    }

    fn eat_space(&self, context: &Context) -> Result<(), AstGeneratorError> {
        let token_index = self.eat()?;
        let token = &context.tokens.borrow()[token_index];
        match token.token {
            Token::Space(_) => Ok(()),
            _ => Err(AstGeneratorError::syntax_issue(
                context,
                token_index,
                "Expected space".to_string(),
            )),
        }
    }

    fn cleanup_space(&self, context: &Context) -> Result<(), AstGeneratorError> {
        if let Ok(token_index) = self.peek() {
            let token = &context.tokens.borrow()[token_index];
            if let Token::Space(_) = token.token {
                let _ = self.eat();
            }
        }
        Ok(())
    }

    fn eat_assign(&self, context: &Context) -> Result<(), AstGeneratorError> {
        let token_index = self.eat()?;
        let token = &context.tokens.borrow()[token_index];
        match token.token {
            Token::Assign => Ok(()),
            _ => Err(AstGeneratorError::syntax_issue(
                context,
                token_index,
                "Expected assign".to_string(),
            )),
        }
    }

    fn eat_text(&self, context: &Context) -> Result<String, AstGeneratorError> {
        let token_index = self.eat()?;
        let token = &context.tokens.borrow()[token_index];
        match &token.token {
            Token::Keyword(text) => Ok(text.clone()),
            Token::LocalBranch(text) => Ok(text.clone()),
            _ => Err(AstGeneratorError::syntax_issue(
                context,
                token_index,
                "Expected text".to_string(),
            )),
        }
    }

    fn parse_list(
        &self,
        context: &Context,
        validator: impl Fn(DirectiveType) -> bool,
    ) -> Result<Vec<DirectiveValue>, AstGeneratorError> {
        let tokens = context.tokens.borrow();

        let mut token_found = false;
        let mut finish = false;

        self.cleanup_space(context)?;
        let mut values = Vec::new();

        while self.size.get() > self.index.get() {
            let value_index = self.eat()?;
            let value_token = &tokens.get(value_index).map(|item| &item.token);

            if token_found {
                /* comma, space, new line, end or comment expected */
                match value_token {
                    Some(Token::NewLine(_)) => finish = true,
                    Some(Token::Comment(_)) => finish = true,
                    Some(Token::End) => finish = true,
                    Some(Token::Space(_)) => (),
                    Some(Token::Comma) => token_found = false,
                    _ => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            value_index,
                            format!("Unexpected syntax ({:?})", value_token),
                        ))
                    }
                }
            } else {
                /* Expected parseable token */
                match value_token {
                    Some(Token::Keyword(keyword)) => {
                        values.push(DirectiveValue::Reference(keyword.clone()));
                        token_found = true;
                    }
                    Some(Token::Word(number)) => {
                        values.push(DirectiveValue::Word(*number));
                        token_found = true;
                    }
                    Some(Token::Byte(number)) => {
                        values.push(DirectiveValue::Byte(*number));
                        token_found = true;
                    }
                    Some(Token::String(string)) => {
                        values.push(DirectiveValue::String(string.clone()));
                        token_found = true;
                    }
                    Some(Token::NewLine(_)) => finish = true,
                    Some(Token::Comment(_)) => finish = true,
                    Some(Token::End) => finish = true,
                    Some(Token::Space(_)) => (),
                    Some(Token::Comma) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            value_index,
                            "',' not expected".to_string(),
                        ))
                    }
                    Some(_) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            value_index,
                            format!("Unexpected syntax ({:?})", value_token),
                        ))
                    }
                    None => return Err(AstGeneratorError::InternalError),
                };
            }

            if token_found && !validator(DirectiveType::from(&values[values.len() - 1])) {
                return Err(AstGeneratorError::syntax_issue(
                    context,
                    value_index,
                    format!("3. Unexpected syntax ({:?})", value_token),
                ));
            }

            if finish {
                break;
            }
        }

        Ok(values)
    }

    fn generate_directive(
        &self,
        context: &Context,
        token_index: usize,
        directive_name: &str,
    ) -> Result<(), AstGeneratorError> {
        let directive_name = directive_name.to_uppercase();
        if let Some(directive) = SYSTEM_DIRECTIVES
            .iter()
            .find(|item| item.name == &directive_name[..])
        {
            let values = self.parse_list(context, |directive_type| -> bool {
                return directive_type == DirectiveType::Reference
                    || directive.values.iter().any(|mode| *mode == directive_type);
            })?;

            match directive.size {
                super::directive::DirectiveVariableSize::None => {
                    if !values.is_empty() {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "No value expected".to_string(),
                        ));
                    }
                }
                super::directive::DirectiveVariableSize::Min(min) => {
                    if values.len() < min {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            format!("Minimum {} value(s) expected", min),
                        ));
                    }
                }
                super::directive::DirectiveVariableSize::Length(len) => {
                    if values.len() != len {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            format!("Expected {} value(s)", len),
                        ));
                    }
                }
            }

            if !directive.values.is_empty() && values.is_empty() {
                return Err(AstGeneratorError::syntax_issue(
                    context,
                    token_index,
                    "Missing information".to_string(),
                ));
            }

            match directive.directive {
                DirectiveEnum::Include => *self.include_asm.borrow_mut() = Some(values[0].clone()),
                _ => context.add_ast(token_index, Ast::Directive(directive.directive, values)),
            }
        } else {
            return Err(AstGeneratorError::syntax_issue(
                context,
                token_index,
                "Unsupported compiler configuration".to_string(),
            ));
        }
        Ok(())
    }

    fn process_include(
        &self,
        context: &Context,
        token_index: usize,
    ) -> Result<(), AstGeneratorError> {
        let include_asm = self.include_asm.replace(None);
        let mut file_path = PathBuf::new();

        if let Some(item) = include_asm {
            match item {
                DirectiveValue::String(name) => file_path.push(name),
                _ => {
                    return Err(AstGeneratorError::syntax_issue(
                        context,
                        token_index,
                        "Path expected as a string".to_string(),
                    ))
                }
            };

            let mut tokens = context.tokens.borrow_mut();
            let token = &tokens[token_index];
            let path = context.add_file(token.file_id, file_path);

            if !context.silent {
                info!("Importing {:?}", &path.as_os_str());
            }

            let mut file = File::open(&path)?;

            let mut code = Vec::new();
            file.read_to_end(&mut code)?;
            context.code_files.borrow_mut()[context.last_file_id()].data = code.clone();

            code.push(b'\n'); // Add new lines to end of the code file

            let new_context = Context::default();

            let mut parser = Parser::new(context.last_file_id(), &code[..], new_context);
            parser.parse().unwrap();

            let new_context = parser.context;

            let new_tokens = new_context.tokens.borrow();
            let current_position = self.index.get();

            if new_tokens.len() > 0 {
                for token in new_tokens.iter().take(new_tokens.len() - 1).rev() {
                    tokens.insert(current_position, token.clone());
                }

                self.size.set(tokens.len());
            }
        }

        Ok(())
    }

    fn generate_branch(
        &self,
        context: &Context,
        token_index: usize,
        name: &str,
        branch_type: BranchType,
    ) -> Result<(), AstGeneratorError> {
        context.add_ast(token_index, Ast::Branch(name.to_owned(), branch_type));
        Ok(())
    }

    fn generate_assign(
        &self,
        context: &Context,
        _: usize,
        name: &String,
    ) -> Result<(), AstGeneratorError> {
        self.cleanup_space(context)?;
        self.eat_assign(context)?;
        self.cleanup_space(context)?;

        let values = self.parse_list(context, |_| true)?;
        let has_reference = context
            .references
            .borrow_mut()
            .insert(name.to_owned(), values)
            .is_some();

        if has_reference {
            return Err(AstGeneratorError::ReferenceAlreadyDefined(name.to_owned()));
        }
        Ok(())
    }

    pub(crate) fn parse_instr_value(
        &self,
        context: &Context,
    ) -> Result<InstrInfo, AstGeneratorError> {
        self.cleanup_space(context)?;
        let tokens = context.tokens.borrow();

        let token_index = self.eat()?;
        let mut token = &tokens[token_index];

        let mut inst_info = InstrInfo {
            in_parenthesis: false,
            is_immediate: false,
            register: InstrInfoRegister::None,
            value: InstrValue::Byte(0),
        };

        let mut parenthesis_open = false;

        if let Token::OpenParenthesis = token.token {
            inst_info.in_parenthesis = true;
            parenthesis_open = true;

            self.cleanup_space(context)?;
            let token_index = self.eat()?;
            token = &tokens[token_index];
        }

        if let Token::Sharp = &token.token {
            inst_info.is_immediate = true;

            let token_index = self.eat()?;
            token = &tokens[token_index];
        }

        match &token.token {
            Token::Keyword(keyword) => {
                let references = context.references.borrow();
                if let Some(values) = references.get(keyword) {
                    if values.len() != 1 {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "Only one token required".to_string(),
                        ));
                    }

                    let first_value = &values[0];
                    match first_value {
                        DirectiveValue::Byte(byte) => inst_info.value = InstrValue::Byte(*byte),
                        DirectiveValue::Word(word) => inst_info.value = InstrValue::Word(*word),
                        _ => {
                            return Err(AstGeneratorError::syntax_issue(
                                context,
                                token_index,
                                "Invalid token for number".to_string(),
                            ))
                        }
                    };
                } else {
                    inst_info.value = InstrValue::Reference(keyword.to_owned());
                }
            }
            Token::LocalKeyword(keyword) => {
                inst_info.value = InstrValue::LocalReference(keyword.to_owned())
            }
            Token::Byte(byte) => inst_info.value = InstrValue::Byte(*byte),
            Token::Word(word) => inst_info.value = InstrValue::Word(*word),
            _ => {
                return Err(AstGeneratorError::syntax_issue(
                    context,
                    token_index,
                    "Invalid numbering number format".to_string(),
                ))
            }
        };

        self.cleanup_space(context)?;

        if let Ok(token_index) = self.peek() {
            token = &tokens[token_index];
            if let Token::CloseParenthesis = token.token {
                let _ = self.eat()?;
                parenthesis_open = false;
                self.cleanup_space(context)?;

                let token_index = self.peek()?;
                token = &tokens[token_index];
            }

            if let Token::Comma = token.token {
                self.eat()?;
                self.cleanup_space(context)?;

                let token_index = self.peek()?;
                token = &tokens[token_index];

                match &token.token {
                    Token::Keyword(value) if value == "x" || value == "X" => {
                        inst_info.register = InstrInfoRegister::X
                    }
                    Token::Keyword(value) if value == "y" || value == "Y" => {
                        inst_info.register = InstrInfoRegister::Y
                    }
                    _ => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "Expected X or Y".to_string(),
                        ))
                    }
                };

                if parenthesis_open && inst_info.register == InstrInfoRegister::Y {
                    return Err(AstGeneratorError::syntax_issue(
                        context,
                        token_index,
                        "Expected X".to_string(),
                    ));
                } else if !parenthesis_open
                    && inst_info.in_parenthesis
                    && inst_info.register == InstrInfoRegister::X
                {
                    return Err(AstGeneratorError::syntax_issue(
                        context,
                        token_index,
                        "Expected Y".to_string(),
                    ));
                }

                self.eat()?;
            }
        }

        self.cleanup_space(context)?;

        if parenthesis_open {
            self.eat_expected(
                context,
                TokenType::CloseParenthesis,
                AstGeneratorError::syntax_issue(context, token_index, "Expected ')'".to_string()),
            )?;
        }

        if inst_info.is_immediate
            && !inst_info.in_parenthesis
            && inst_info.register == InstrInfoRegister::None
        {
            if let InstrValue::Word(word) = inst_info.value {
                inst_info.value = InstrValue::Byte(word as u8);
            }
        }

        if !inst_info.is_immediate
            && inst_info.in_parenthesis
            && inst_info.register != InstrInfoRegister::None
        {
            if let InstrValue::Word(word) = inst_info.value {
                inst_info.value = InstrValue::Byte(word as u8);
            }
        }

        Ok(inst_info)
    }

    fn generate_code_block(
        &self,
        context: &Context,
        token_index: usize,
        positon: usize,
    ) -> Result<(), AstGeneratorError> {
        if INSTS_SIZE[positon] == 1 {
            context.add_ast(token_index, Ast::InstrImplied(positon));
        } else if BRANCH_INSTS.contains(&positon) {
            // Branch inst
            self.eat_space(context)?;
            let value = self.parse_instr_value(context)?;

            match value.value {
                InstrValue::Byte(_) => context.add_ast(token_index, Ast::Instr(positon, value)),
                InstrValue::Reference(_) => {
                    context.add_ast(token_index, Ast::Instr(positon, value))
                }
                InstrValue::LocalReference(_) => {
                    context.add_ast(token_index, Ast::Instr(positon, value))
                }
                _ => {
                    return Err(AstGeneratorError::syntax_issue(
                        context,
                        token_index,
                        "Relative number or branch name expected".to_string(),
                    ))
                }
            }
        } else {
            self.eat_space(context)?;
            let value = self.parse_instr_value(context)?;
            context.add_ast(token_index, Ast::Instr(positon, value));
        }

        Ok(())
    }

    fn inline_generate(&self, context: &Context) -> Result<(), AstGeneratorError> {
        self.size.set(context.tokens.borrow().len());
        let mut token_index = 0;

        while self.size.get() > self.index.get() {
            {
                token_index = self.eat()?;
                let tokens = context.tokens.borrow();

                match &tokens.get(token_index).map(|item| &item.token) {
                    Some(Token::Instr(positon)) => {
                        self.generate_code_block(context, token_index, *positon)?
                    }
                    Some(Token::Keyword(keyword)) => {
                        self.generate_assign(context, token_index, keyword)?
                    }
                    Some(Token::Directive(option)) => {
                        self.generate_directive(context, token_index, option)?
                    }
                    Some(Token::Comment(_)) => (),
                    Some(Token::Branch(name)) => {
                        self.generate_branch(context, token_index, name, BranchType::Generic)?
                    }
                    Some(Token::Byte(_)) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "Number not expected".to_string(),
                        ))
                    }
                    Some(Token::Word(_)) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "Number not expected".to_string(),
                        ))
                    }
                    Some(Token::NewLine(_)) => (),
                    Some(Token::Space(_)) => (),
                    Some(Token::OpenParenthesis) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "'(' not expected".to_string(),
                        ))
                    }
                    Some(Token::CloseParenthesis) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "')' not expected".to_string(),
                        ))
                    }
                    Some(Token::Sharp) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "'#' not expected".to_string(),
                        ))
                    }
                    Some(Token::Assign) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "'=' not expected".to_string(),
                        ))
                    }
                    Some(Token::Comma) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "',' not expected".to_string(),
                        ))
                    }
                    Some(Token::String(_)) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "String not expected".to_string(),
                        ))
                    }
                    Some(Token::LocalKeyword(_)) => {
                        return Err(AstGeneratorError::syntax_issue(
                            context,
                            token_index,
                            "Unexpected local branch name".to_string(),
                        ))
                    }
                    Some(Token::LocalBranch(name)) => {
                        self.generate_branch(context, token_index, name, BranchType::Local)?
                    }
                    Some(Token::End) => break,
                    None => return Err(AstGeneratorError::InternalError),
                }
            }

            self.process_include(context, token_index)?;
        }

        Ok(())
    }

    pub fn generate(&self, context: Context) -> Result<Context, AstGeneratorError> {
        match self.inline_generate(&context) {
            Ok(_) => Ok(context),
            Err(error) => {
                let tokens = context.tokens.borrow();
                let token = &tokens[self.index.get() - 1];

                if !context.silent {
                    let code_file = &context.code_files.borrow()[token.file_id];
                    print_error(&code_file.data, &error, token.line, token.column, token.end);
                }
                Err(error)
            }
        }
    }
}
