use godot::prelude::*;
use rv6502emu::cpu::Cpu;
use std::cell::RefCell;
use std::rc::Rc;

use uuid::Uuid;

use std::collections::HashMap;

pub mod asm6502;

#[derive(Clone)]
struct CPUWrapper {
    cpu: Rc<RefCell<Cpu>>,
    start_address: Rc<RefCell<u16>>, // program load address
    offset_to_line: Rc<RefCell<HashMap<u16, u32>>>, // offset in program -> line
}

impl CPUWrapper {
    pub fn get_cpu(&self) -> Rc<RefCell<Cpu>> {
        self.cpu.clone()
    }

    pub fn run_step(&self) {
        // Execute a single instruction using run with a limit of 1
        let _ = self.cpu.borrow_mut().run(None, 1);
    }

    pub fn run_steps_async(&self, steps: u32) {
        let _ = self.cpu.borrow_mut().run(None, steps as usize);
    }

    pub fn wait_until_done(&self) {
        // No-op (synchronous run)
    }

    pub fn set_mapping(&self, start_address: u16, mapping: HashMap<u16, u32>) {
        *self.start_address.borrow_mut() = start_address;
        let mut map = self.offset_to_line.borrow_mut();
        map.clear();
        map.extend(mapping.into_iter());
    }

    pub fn get_line_number(&self, pc: u16) -> Option<u32> {
        let start: u16 = *self.start_address.borrow();
        if pc < start {
            return None;
        }
        let offset = pc.wrapping_sub(start);
        let map = self.offset_to_line.borrow();
        map.get(&offset).copied()
    }
}

struct Orchestrator {
    cpus: HashMap<Uuid, CPUWrapper>,
}

impl Orchestrator {
    pub fn new() -> Self {
        Self {
            cpus: HashMap::new(),
        }
    }

    pub fn remove_cpu(&mut self, key: Uuid) {
        self.cpus.remove(&key);
    }

    pub fn get_cpu(&self, key: Uuid) -> &CPUWrapper {
        match self.cpus.get(&key) {
            Some(cpu_wrapper) => cpu_wrapper,
            None => panic!("No CPU found for key {}", key),
        }
    }

    pub fn create_cpu(
        &mut self,
        start_address: u16,
        program: Vec<u8>,
        mapping: HashMap<u16, u32>,
    ) -> Uuid {
        let key = uuid::Uuid::new_v4();

        // create a MOS6502 (default) CPU with default bus and 64k memory
        let mut cpu_obj = Cpu::new_default(None);
        // load program bytes into memory
        let mem = cpu_obj.bus.get_memory();
        for (i, b) in program.iter().enumerate() {
            let _ = mem.write_byte(start_address as usize + i, *b);
        }
        // reset CPU so SP/flags/PC are correctly initialized
        let _ = cpu_obj.reset(Some(start_address));

        let cpu = Rc::new(RefCell::new(cpu_obj));

        let wrapper = CPUWrapper {
            cpu,
            start_address: Rc::new(RefCell::new(start_address)),
            offset_to_line: Rc::new(RefCell::new(mapping)),
        };

        self.cpus.insert(key, wrapper);

        return key;
    }
}

thread_local! {
    static ORCHESTRATOR: RefCell<Orchestrator> = RefCell::new(Orchestrator::new());
}

struct MyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}

#[derive(GodotClass)]
#[class(init, base=Node3D)]
struct Emulator6502 {
    key: String,
    frequency: i32,
    partial_step: f32,
}

#[godot_api]
impl Emulator6502 {
    #[func]
    pub fn create_cpu(frequency: i32) -> Gd<Self> {
        let key = ORCHESTRATOR.with(|o| {
            o.borrow_mut()
                .create_cpu(0x0600, Vec::new(), HashMap::new())
        });
        return Gd::from_object(Emulator6502 {
            key: key.to_string(),
            frequency,
            partial_step: 0.0,
        });
    }

    #[func]
    pub fn load_program(&self, program: Array<u8>, start_address: u16) {
        let key = Uuid::parse_str(&self.key).unwrap();
        let cpuw = ORCHESTRATOR.with(|o| o.borrow().get_cpu(key).clone());
        let cpu = cpuw.get_cpu();

        // Convert Godot Array<u8> to Vec<u8>
        let mut vec_program = Vec::with_capacity(program.len() as usize);
        for i in 0..program.len() {
            if let Some(byte) = program.get(i) {
                vec_program.push(byte);
            }
        }

        let mut c = cpu.borrow_mut();
        let mem = c.bus.get_memory();
        for (i, b) in vec_program.iter().enumerate() {
            let _ = mem.write_byte(start_address as usize + i, *b);
        }
        let _ = c.reset(Some(start_address));
        // Do not change mapping here; use load_program_from_string to set mapping when assembling
        *cpuw.start_address.borrow_mut() = start_address;
    }

    #[func]
    pub fn load_program_from_string(&self, assembly_code: String, start_address: u16) {
        // most likely we'll want to add a mapping between PC <-> code line number here
        // even though we only access the CPU in load_program so this might be an issue.
        let output = match asm6502::assemble_string(&assembly_code) {
            Ok(out) => {
                godot_print!("Successfully compiled assembly from string");
                out
            }
            _ => {
                godot_error!("Failed to compile assembly from string");
                return;
            }
        };

        // Convert Vec<u8> to Godot Array<u8>
        let mut godot_array = Array::new();
        for byte in &output.bytes {
            godot_array.push(*byte);
        }

        self.load_program(godot_array, start_address);

        // Store mapping in the CPU wrapper for later lookup
        let key = Uuid::parse_str(&self.key).unwrap();
        let cpuw = ORCHESTRATOR.with(|o| o.borrow().get_cpu(key).clone());
        cpuw.set_mapping(start_address, output.offset_to_line);
    }

    #[func]
    pub fn create_cpu_from_string(assembly_code: String, frequency: i32) -> Gd<Self> {
        let output = match asm6502::assemble_string(&assembly_code) {
            Ok(out) => {
                godot_print!("Successfully compiled assembly from string");
                out
            }
            _ => {
                godot_error!("Failed to compile assembly from string");
                // create empty CPU if failed
                let key = ORCHESTRATOR.with(|o| {
                    o.borrow_mut()
                        .create_cpu(0x0600, Vec::new(), HashMap::new())
                });
                return Gd::from_object(Emulator6502 {
                    key: key.to_string(),
                    frequency,
                    partial_step: 0.0,
                });
            }
        };

        let key = ORCHESTRATOR.with(|o| {
            o.borrow_mut()
                .create_cpu(0x0600, output.bytes, output.offset_to_line)
        });
        return Gd::from_object(Emulator6502 {
            key: key.to_string(),
            frequency,
            partial_step: 0.0,
        });
    }

    fn cpu(&self) -> CPUWrapper {
        let key = Uuid::parse_str(&self.key).unwrap();
        ORCHESTRATOR.with(|o| o.borrow().get_cpu(key).clone())
    }

    #[func]
    pub fn execute_cycles_for_duration(&mut self, delta: f32) {
        // Calculate how many CPU cycles to execute based on time delta and target frequency
        let steps = delta * self.frequency as f32;
        if steps < 1.0 {
            self.partial_step += steps;
            if (self.partial_step >= 1.0) {
                self.partial_step -= 1.0;
                self.cpu().run_step();
            }
        } else {
            self.partial_step = 0.0;
            self.cpu().run_steps_async(steps as u32);
        }
    }

    #[func]
    pub fn step(&self) {
        self.cpu().run_step();
    }

    #[func]
    pub fn get_mmio(&self) -> Array<u8> {
        let cpu = self.cpu().get_cpu();
        let mut c = cpu.borrow_mut();
        let mem = c.bus.get_memory();
        let mut mmio = Array::new();
        for i in 0x200..0x1200 {
            mmio.push(mem.read_byte(i as usize).unwrap_or(0));
        }
        mmio
    }

    #[func]
    pub fn get_cpu_state(&self) -> Dictionary {
        let cpu = self.cpu().get_cpu();
        let cpu_guard = cpu.borrow();

        let mut state = Dictionary::new();
        let _ = state.insert("pc", cpu_guard.regs.pc);
        let _ = state.insert("a", cpu_guard.regs.a);
        let _ = state.insert("x", cpu_guard.regs.x);
        let _ = state.insert("y", cpu_guard.regs.y);
        let _ = state.insert("p", cpu_guard.regs.p.bits());
        let _ = state.insert("sp", cpu_guard.regs.s as u16);

        state
    }

    #[func]
    pub fn read_page(&self, page: u8) -> Array<u8> {
        let cpu = self.cpu().get_cpu();
        let mut c = cpu.borrow_mut();
        let mem = c.bus.get_memory();
        let mut result = Array::new();
        let page_address = (page as u16 * 256) as u16;
        for i in 0..256 {
            result.push(
                mem.read_byte((page_address + i as u16) as usize)
                    .unwrap_or(0),
            );
        }
        result
    }

    #[func]
    pub fn read_memory(&self, address: u16) -> u8 {
        let cpu = self.cpu().get_cpu();
        let mut c = cpu.borrow_mut();
        let mem = c.bus.get_memory();
        mem.read_byte(address as usize).unwrap_or(0)
    }

    #[func]
    pub fn set_memory(&self, address: u16, value: u8) {
        let cpu = self.cpu().get_cpu();
        let c = &mut *cpu.borrow_mut();
        let mem = c.bus.get_memory();
        let _ = mem.write_byte(address as usize, value);
    }

    #[func]
    pub fn set_program_counter(&self, address: u16) {
        let cpu = self.cpu().get_cpu();
        let mut cpu_guard = cpu.borrow_mut();
        cpu_guard.regs.pc = address;
    }

    #[func]
    pub fn wait_until_done(&self) {
        self.cpu().wait_until_done();
    }

    #[func]
    pub fn set_frequency(&mut self, frequency: i32) {
        self.frequency = frequency
    }

    #[func]
    pub fn get_frequency(&self) -> i32 {
        self.frequency
    }

    #[func]
    pub fn get_line_number(&self, pc: u16) -> i32 {
        let line = self.cpu().get_line_number(pc);
        match line {
            Some(line) => line as i32,
            None => -1,
        }
    }
}
