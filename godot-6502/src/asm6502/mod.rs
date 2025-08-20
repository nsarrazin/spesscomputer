// 6502 Assembly module
// This module handles 6502 assembly operations
mod ast;
mod code_gen;
mod context;
mod directive;
mod opcode;
mod parser;
mod tool;
use godot::prelude::*;

use ast::{AstGenerator, AstGeneratorError};
use code_gen::{CodeGenerator, CodeGeneratorError};
use context::Context;
use parser::{ParseError, Parser};

pub fn assemble_string(code: &str) -> Result<Vec<u8>, String> {
    let data = code.as_bytes().to_vec();
    let context = Context::default();

    // Use a placeholder file ID for the string input
    let file_id = 0;
    context.add_file(file_id, std::path::PathBuf::new());
    context.code_files.borrow_mut()[file_id].data = data.clone();

    // Parse the code
    let mut parser = Parser::new(file_id, &data, context);
    parser.parse().map_err(|e: ParseError| e.to_string())?;

    let context = parser.context;

    // Generate AST
    let ast_generator = AstGenerator::new();
    let context = ast_generator
        .generate(context)
        .map_err(|e: AstGeneratorError| e.to_string())?;

    // Generate code
    let mut generator = CodeGenerator::new();
    generator.silent = true;

    let context = generator
        .generate(context)
        .map_err(|e: CodeGeneratorError| e.to_string())?;

    let mut output = format!("Assembled binary ({} bytes):\n", context.target.len());
    for (i, byte) in context.target.iter().enumerate() {
        output.push_str(&format!("{:02X} ", byte));
        if (i + 1) % 16 == 0 {
            output.push('\n');
        }
    }
    if context.target.len() % 16 != 0 {
        output.push('\n');
    }
    // Return the compiled binary
    Ok(context.target)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_assemble_string() {
        let code = "LDA #$00";
        let result = assemble_string(code);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), vec![0xA9, 0x00]);
    }

    #[test]
    fn test_assemble_string_with_errors() {
        let code = "LDA #$00";
        let result = assemble_string(code);
        assert!(result.is_err());
    }
}
