<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { EditorState, type Extension } from '@codemirror/state';
  import { EditorView, keymap, Decoration, type DecorationSet, lineNumbers } from '@codemirror/view';
  import { defaultKeymap, history, historyKeymap, insertTab, indentSelection, deleteCharBackward } from '@codemirror/commands';
  import { searchKeymap, highlightSelectionMatches } from '@codemirror/search';
  import { lintGutter, linter, type Diagnostic } from '@codemirror/lint';
  import { HighlightStyle, syntaxHighlighting } from '@codemirror/language';
  import { tags as t } from '@lezer/highlight';
  import { autocompletion, completeFromList } from '@codemirror/autocomplete';
  import { StateField, StateEffect, RangeSet } from '@codemirror/state';

  interface Props {
    value?: string;
    placeholder?: string;
    readOnly?: boolean;
    className?: string;
  }

  let {
    value = $bindable(''),
    placeholder = 'Enter 6502 assembly code...',
    readOnly = false,
    className = ''
  }: Props = $props();

  let editorContainer: HTMLDivElement;
  let view: EditorView | null = null;
  let isDirty = $state(false);
  let originalCode = $state('');

  // 6502 opcodes and directives
  const OPCODES = [
    'ADC', 'AND', 'ASL', 'BCC', 'BCS', 'BEQ', 'BIT', 'BMI', 'BNE', 'BPL', 'BRK', 'BVC', 'BVS',
    'CLC', 'CLD', 'CLI', 'CLV', 'CMP', 'CPX', 'CPY', 'DEC', 'DEX', 'DEY', 'EOR', 'INC', 'INX', 'INY',
    'JMP', 'JSR', 'LDA', 'LDX', 'LDY', 'LSR', 'NOP', 'ORA', 'PHA', 'PHP', 'PLA', 'PLP', 'ROL', 'ROR',
    'RTI', 'RTS', 'SBC', 'SEC', 'SED', 'SEI', 'STA', 'STX', 'STY', 'TAX', 'TAY', 'TSX', 'TXA', 'TXS', 'TYA'
  ];

  const DIRECTIVES = [
    '.org', '.byte', '.word', '.dcb', '.db', '.dw', '.text', '.fill', '.include', '.equ', '.define'
  ];

  const REGISTERS = ['A', 'X', 'Y'];
  const opcodeSet = new Set(OPCODES);

  // Custom dedent function for Shift+Tab
  function dedentLine(view: EditorView): boolean {
    const { state } = view;
    const changes = [];
    
    // Get the current line
    const line = state.doc.lineAt(state.selection.main.head);
    const text = line.text;
    
    // Find leading whitespace
    const match = text.match(/^(\s*)/);
    const leadingWhitespace = match ? match[1] : '';
    
    if (leadingWhitespace.length > 0) {
      // Remove one level of indentation (prefer tabs, fall back to spaces)
      let newLeading = '';
      if (leadingWhitespace.startsWith('\t')) {
        // Remove one tab
        newLeading = leadingWhitespace.slice(1);
      } else if (leadingWhitespace.startsWith('  ')) {
        // Remove two spaces (assuming 2-space indentation)
        newLeading = leadingWhitespace.slice(2);
      } else if (leadingWhitespace.startsWith(' ')) {
        // Remove one space
        newLeading = leadingWhitespace.slice(1);
      } else {
        return false; // No change needed
      }
      
      changes.push({
        from: line.from,
        to: line.from + leadingWhitespace.length,
        insert: newLeading
      });
      
      view.dispatch({ changes });
      return true;
    }
    
    return false;
  }

  // Create decorations for syntax highlighting
  const highlightField = StateField.define<DecorationSet>({
    create(state) {
      return createHighlighting(state.doc.toString());
    },
    update(decorations, tr) {
      decorations = decorations.map(tr.changes);
      
      if (tr.docChanged) {
        decorations = createHighlighting(tr.newDoc.toString());
      }
      
      return decorations;
    },
    provide: field => EditorView.decorations.from(field)
  });

  // Function to create highlighting decorations
  function createHighlighting(text: string): DecorationSet {
    const decoratedRanges: Array<{from: number, to: number, decoration: any}> = [];
    const covered = new Array(text.length).fill(false);

    // Define decoration types
    const opcodeDecoration = Decoration.mark({ class: "cm-asm-opcode" });
    const directiveDecoration = Decoration.mark({ class: "cm-asm-directive" });
    const labelDecoration = Decoration.mark({ class: "cm-asm-label" });
    const numberDecoration = Decoration.mark({ class: "cm-asm-number" });
    const stringDecoration = Decoration.mark({ class: "cm-asm-string" });
    const registerDecoration = Decoration.mark({ class: "cm-asm-register" });
    const operatorDecoration = Decoration.mark({ class: "cm-asm-operator" });
    const commentDecoration = Decoration.mark({ class: "cm-asm-comment" });
    const variableDecoration = Decoration.mark({ class: "cm-asm-variable" });

    // Helper function to add decoration if not already covered
    function addDecoration(from: number, to: number, decoration: any) {
      // Check if any part of this range is already covered
      for (let i = from; i < to; i++) {
        if (covered[i]) return; // Skip if overlapping
      }
      
      // Mark as covered
      for (let i = from; i < to; i++) {
        covered[i] = true;
      }
      
      decoratedRanges.push({ from, to, decoration });
    }

    // Apply patterns in priority order (most specific first)
    
    // 1. Comments (highest priority - covers everything after ;)
    let match;
    const commentRegex = /;.*$/gm;
    while ((match = commentRegex.exec(text)) !== null) {
      addDecoration(match.index, match.index + match[0].length, commentDecoration);
    }
    commentRegex.lastIndex = 0;

    // 2. String literals
    const stringRegex = /"([^"\\]|\\.)*"/g;
    while ((match = stringRegex.exec(text)) !== null) {
      addDecoration(match.index, match.index + match[0].length, stringDecoration);
    }
    stringRegex.lastIndex = 0;

    // 3. Labels (at start of line)
    const labelRegex = /^[ \t]*[A-Za-z_][A-Za-z0-9_]*:/gm;
    while ((match = labelRegex.exec(text)) !== null) {
      addDecoration(match.index, match.index + match[0].length, labelDecoration);
    }
    labelRegex.lastIndex = 0;

    // 4. Directives
    const directiveRegex = /\.[A-Za-z_][A-Za-z0-9_]*/g;
    while ((match = directiveRegex.exec(text)) !== null) {
      addDecoration(match.index, match.index + match[0].length, directiveDecoration);
    }
    directiveRegex.lastIndex = 0;

    // 5. Numbers
    const patterns = [
      { regex: /\$[0-9A-Fa-f]+/g, decoration: numberDecoration },
      { regex: /%[01]+/g, decoration: numberDecoration },
      { regex: /\b\d+\b/g, decoration: numberDecoration }
    ];

    patterns.forEach(pattern => {
      while ((match = pattern.regex.exec(text)) !== null) {
        addDecoration(match.index, match.index + match[0].length, pattern.decoration);
      }
      pattern.regex.lastIndex = 0;
    });

    // 6. Registers
    const registerRegex = /\b[AXY]\b/g;
    while ((match = registerRegex.exec(text)) !== null) {
      addDecoration(match.index, match.index + match[0].length, registerDecoration);
    }
    registerRegex.lastIndex = 0;

    // 7. Opcodes and variables
    const opcodeRegex = /\b[A-Za-z]{3}\b/g;
    while ((match = opcodeRegex.exec(text)) !== null) {
      const opcode = match[0].toUpperCase();
      const decoration = OPCODES.includes(opcode) ? opcodeDecoration : variableDecoration;
      addDecoration(match.index, match.index + match[0].length, decoration);
    }
    opcodeRegex.lastIndex = 0;

    // 8. Operators (lowest priority)
    const operatorRegex = /[#,()[\]+\-*]/g;
    while ((match = operatorRegex.exec(text)) !== null) {
      addDecoration(match.index, match.index + match[0].length, operatorDecoration);
    }
    operatorRegex.lastIndex = 0;

    // Sort by position and create decorations
    decoratedRanges.sort((a, b) => a.from - b.from);
    const finalDecorations = decoratedRanges.map(range => 
      range.decoration.range(range.from, range.to)
    );

    return RangeSet.of(finalDecorations);
  }

  // Autocompletion
  const completions = autocompletion({
    override: [
      completeFromList([
        ...OPCODES.map(op => ({ label: op, type: 'keyword', info: `6502 opcode: ${op}` })),
        ...DIRECTIVES.map(dir => ({ label: dir, type: 'keyword', info: `Assembler directive: ${dir}` })),
        ...REGISTERS.map(reg => ({ label: reg, type: 'variable', info: `${reg} register` }))
      ])
    ]
  });

  // Linter for unknown opcodes
  const asmLinter = linter((view): Diagnostic[] => {
    const diagnostics: Diagnostic[] = [];
    const doc = view.state.doc;
    
    for (let i = 1; i <= doc.lines; i++) {
      const line = doc.line(i);
      const text = line.text;
      
      // Remove labels and get the instruction part
      const cleanText = text.replace(/^\s*[A-Za-z_][A-Za-z0-9_]*:\s*/, '');
      const match = cleanText.match(/^\s*([A-Za-z]{3})\b/i);
      
      if (match) {
        const opcode = match[1].toUpperCase();
        if (!opcodeSet.has(opcode)) {
          const opcodeStart = line.from + text.indexOf(match[1]);
          diagnostics.push({
            from: opcodeStart,
            to: opcodeStart + match[1].length,
            severity: 'error',
            message: `Unknown opcode: ${opcode}`
          });
        }
      }
    }
    
    return diagnostics;
  });

  // Editor theme
  const theme = EditorView.theme({
    '&': {
      backgroundColor: '#111827',
      color: '#e5e7eb',
      fontSize: '14px',
      height: '100%'
    },
    '.cm-content': {
      fontFamily: "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace",
      padding: '16px',
      lineHeight: '1.5'
    },
    '.cm-editor': {
      height: '100%'
    },
    '.cm-scroller': {
      height: '100%'
    },
    '.cm-gutters': {
      backgroundColor: '#0b0f19',
      color: '#64748b',
      border: 'none',
      paddingRight: '4px'
    },
    '.cm-activeLineGutter': {
      backgroundColor: '#0b1220'
    },
    '.cm-activeLine': {
      backgroundColor: '#0b1220'
    },
    '.cm-selectionBackground, &.cm-focused .cm-selectionBackground, .cm-content ::selection': {
      backgroundColor: '#1f2a44'
    },
    '.cm-cursor': {
      borderLeftColor: '#22d3ee'
    },
    '.cm-focused': {
      outline: 'none'
    },
    // Syntax highlighting classes
    '.cm-asm-opcode': {
      color: '#f59e0b',
      fontWeight: '700'
    },
    '.cm-asm-directive': {
      color: '#f59e0b',
      fontWeight: '700'
    },
    '.cm-asm-label': {
      color: '#22d3ee',
      fontWeight: '600'
    },
    '.cm-asm-number': {
      color: '#a3e635'
    },
    '.cm-asm-string': {
      color: '#38bdf8'
    },
    '.cm-asm-register': {
      color: '#86efac',
      fontWeight: '600'
    },
    '.cm-asm-operator': {
      color: '#f97316'
    },
    '.cm-asm-comment': {
      color: '#9ca3af',
      fontStyle: 'italic'
    },
    '.cm-asm-variable': {
      color: '#cbd5e1'
    },
    // Current execution line highlight
    '.cm-exec-line': {
      backgroundColor: '#fde68a33'
    }
  }, { dark: true });

  // Dynamic exec-line highlighter
  const setExecLineEffect = StateEffect.define<number | null>();
  const execLineField = StateField.define<DecorationSet>({
    create() {
      return Decoration.none;
    },
    update(value, tr) {
      value = value.map(tr.changes);
      for (const e of tr.effects) {
        if (e.is(setExecLineEffect)) {
          if (e.value == null) return Decoration.none;
          const lineNum1 = Math.max(1, Math.min(tr.state.doc.lines, (e.value as number) + 1));
          const line = tr.state.doc.line(lineNum1);
          const deco = Decoration.line({ class: 'cm-exec-line' }).range(line.from);
          return Decoration.set([deco]);
        }
      }
      return value;
    },
    provide: f => EditorView.decorations.from(f)
  });

  let lastExecLine: number | null = null;

  async function pollExecLine() {
    try {
      const helper = (window as any).WebHelper;
      if (!helper || !view) return;
      
      // Don't highlight execution line if editor is dirty
      if (isDirty) {
        if (lastExecLine !== null) {
          lastExecLine = null;
          view.dispatch({ effects: setExecLineEffect.of(null) });
        }
        return;
      }
      
      const line: number | null | undefined = await helper.getLineNumber();
      if (line !== lastExecLine && view) {
        lastExecLine = line ?? null;
        view.dispatch({ effects: setExecLineEffect.of(lastExecLine) });
      }
    } catch (err) {
      // ignore polling errors to keep loop running
    }
  }

  // Initialize editor
  function createEditor() {
    try {
      const extensions: Extension[] = [
        highlightField,
        execLineField,
        lineNumbers(),
        keymap.of([
          { key: 'Tab', run: insertTab },
          { key: 'Shift-Tab', run: dedentLine },
          ...defaultKeymap, 
          ...historyKeymap, 
          ...searchKeymap
        ]),
        history(),
        highlightSelectionMatches(),
        completions,
        lintGutter(),
        asmLinter,
        theme,
        EditorView.lineWrapping,
        EditorView.editable.of(!readOnly),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            const newValue = update.state.doc.toString();
            if (newValue !== value) {
              value = newValue;
            }
            // Update dirty state
            isDirty = newValue !== originalCode;
          }
        })
      ];

      const state = EditorState.create({
        doc: value || '',
        extensions
      });

      return new EditorView({
        state,
        parent: editorContainer
      });
    } catch (error) {
      console.error('Failed to create editor:', error);
      return null;
    }
  }

  onMount(() => {
    view = createEditor();
    originalCode = value;
    isDirty = false;

    function updateLoop() {
      pollExecLine();
      requestAnimationFrame(updateLoop);
    }

    requestAnimationFrame(updateLoop);
  });

  onDestroy(() => {
    view?.destroy();
    view = null;
  });

  // React to external value changes
  $effect(() => {
    if (view && value !== undefined) {
      const currentValue = view.state.doc.toString();
      if (value !== currentValue) {
        try {
          view.dispatch({
            changes: {
              from: 0,
              to: view.state.doc.length,
              insert: value
            }
          });
          // Update original code and reset dirty state when value changes externally
          originalCode = value;
          isDirty = false;
        } catch (error) {
          console.error('Failed to update editor value:', error);
        }
      }
    }
  });
</script>

<div 
  bind:this={editorContainer} 
  class={className}
  style:height="100%"
  style:border-radius="12px"
  style:overflow="hidden"
  style:box-shadow="0 10px 30px rgba(0,0,0,0.35)"
  aria-label={placeholder}
></div>

<style>
  :global(.cm-editor) {
    height: 100% !important;
  }
  
  :global(.cm-scroller) {
    height: 100% !important;
  }
</style>
