use godot::prelude::*;
use mos6502::cpu::CPU;
use mos6502::instruction::Nmos6502;
use mos6502::memory::Bus;
use mos6502::memory::Memory;
use std::sync::{Arc, Condvar, Mutex};

use uuid::Uuid;

use lazy_static::lazy_static;
use std::collections::HashMap;

pub mod asm6502;

#[derive(Clone)]
struct CPUWrapper {
    cpu: Arc<Mutex<CPU<Memory, Nmos6502>>>,
    is_running: Arc<Mutex<bool>>,
    completion_cvar: Arc<(Mutex<bool>, Condvar)>,
    start_address: Arc<Mutex<u16>>, // program load address
    offset_to_line: Arc<Mutex<HashMap<u16, u32>>>, // offset in program -> line
}

impl CPUWrapper {
    pub fn get_cpu(&self) -> Arc<Mutex<CPU<Memory, Nmos6502>>> {
        self.cpu.clone()
    }

    pub fn run_step(&self) {
        self.cpu.lock().unwrap().single_step();
    }

    pub fn run_steps(&self, steps: u32) {
        let mut guard = self.cpu.lock().unwrap();
        for _ in 0..steps {
            guard.single_step();
        }
    }

    pub fn run_steps_async(&self, steps: u32) {
        let cpu = self.cpu.clone();
        let is_running = self.is_running.clone();
        let completion_cvar = self.completion_cvar.clone();

        let (lock, _cvar) = &*completion_cvar;
        *is_running.lock().unwrap() = true;
        *lock.lock().unwrap() = true;

        std::thread::spawn(move || {
            for _ in 0..steps {
                cpu.lock().unwrap().single_step();
            }

            let (lock, cvar) = &*completion_cvar;
            let mut completed = lock.lock().unwrap();
            *completed = false;
            *is_running.lock().unwrap() = false;
            cvar.notify_one();
        });
    }

    pub fn wait_until_done(&self) {
        let (lock, cvar) = &*self.completion_cvar;
        let mut completed = lock.lock().unwrap();
        while *completed {
            // godot_warn!("Waiting for CPU to finish previous processing... Is the server lagging?");
            completed = cvar.wait(completed).unwrap();
        }
    }

    pub fn set_mapping(&self, start_address: u16, mapping: HashMap<u16, u32>) {
        *self.start_address.lock().unwrap() = start_address;
        let mut guard = self.offset_to_line.lock().unwrap();
        guard.clear();
        guard.extend(mapping.into_iter());
    }

    pub fn get_line_number(&self, pc: u16) -> Option<u32> {
        let start: u16 = *self.start_address.lock().unwrap();
        if pc < start {
            return None;
        }
        let offset = pc.wrapping_sub(start);
        let map = self.offset_to_line.lock().unwrap();
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

        let cpu = Arc::new(Mutex::new(CPU::new(Memory::new(), Nmos6502)));

        cpu.lock()
            .unwrap()
            .memory
            .set_bytes(start_address, &program);
        cpu.lock().unwrap().registers.program_counter = start_address;

        let wrapper = CPUWrapper {
            cpu,
            is_running: Arc::new(Mutex::new(false)),
            completion_cvar: Arc::new((Mutex::new(false), Condvar::new())),
            start_address: Arc::new(Mutex::new(start_address)),
            offset_to_line: Arc::new(Mutex::new(mapping)),
        };

        self.cpus.insert(key, wrapper);

        return key;
    }
}

lazy_static! {
    static ref ORCHESTRATOR: Mutex<Orchestrator> = Mutex::new(Orchestrator::new());
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
        let key = ORCHESTRATOR
            .lock()
            .unwrap()
            .create_cpu(0x0600, Vec::new(), HashMap::new());
        return Gd::from_object(Emulator6502 {
            key: key.to_string(),
            frequency,
            partial_step: 0.0,
        });
    }

    #[func]
    pub fn load_program(&self, program: Array<u8>, start_address: u16) {
        let key = Uuid::parse_str(&self.key).unwrap();
        let guard = ORCHESTRATOR.lock().unwrap();
        let cpuw = guard.get_cpu(key).clone();
        let cpu = cpuw.get_cpu();

        // Convert Godot Array<u8> to Vec<u8>
        let mut vec_program = Vec::with_capacity(program.len() as usize);
        for i in 0..program.len() {
            if let Some(byte) = program.get(i) {
                vec_program.push(byte);
            }
        }

        cpu.lock()
            .unwrap()
            .memory
            .set_bytes(start_address, &vec_program);
        cpu.lock().unwrap().registers.program_counter = start_address;
        // Do not change mapping here; use load_program_from_string to set mapping when assembling
        *cpuw.start_address.lock().unwrap() = start_address;
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
        let mut orchestrator = ORCHESTRATOR.lock().unwrap();
        let cpuw = orchestrator.get_cpu(key).clone();
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
                let key =
                    ORCHESTRATOR
                        .lock()
                        .unwrap()
                        .create_cpu(0x0600, Vec::new(), HashMap::new());
                return Gd::from_object(Emulator6502 {
                    key: key.to_string(),
                    frequency,
                    partial_step: 0.0,
                });
            }
        };

        let key =
            ORCHESTRATOR
                .lock()
                .unwrap()
                .create_cpu(0x0600, output.bytes, output.offset_to_line);
        return Gd::from_object(Emulator6502 {
            key: key.to_string(),
            frequency,
            partial_step: 0.0,
        });
    }

    fn cpu(&self) -> CPUWrapper {
        let key = Uuid::parse_str(&self.key).unwrap();
        let guard = ORCHESTRATOR.lock().unwrap();
        let cpu = guard.get_cpu(key).clone();
        drop(guard);
        cpu
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
        let mut memory = cpu.lock().unwrap().memory;
        let mut mmio = Array::new();
        for i in 0x200..0x1200 {
            mmio.push(memory.get_byte(i));
        }
        mmio
    }

    #[func]
    pub fn get_cpu_state(&self) -> Dictionary {
        let cpu = self.cpu().get_cpu();
        let cpu_guard = cpu.lock().unwrap();

        let mut state = Dictionary::new();
        let _ = state.insert("pc", cpu_guard.registers.program_counter);
        let _ = state.insert("a", cpu_guard.registers.accumulator);
        let _ = state.insert("x", cpu_guard.registers.index_x);
        let _ = state.insert("y", cpu_guard.registers.index_y);
        let _ = state.insert("p", cpu_guard.registers.status.bits());
        let _ = state.insert("sp", cpu_guard.registers.stack_pointer.0);

        state
    }

    #[func]
    pub fn read_page(&self, page: u8) -> Array<u8> {
        let cpu = self.cpu().get_cpu();
        let mut memory = cpu.lock().unwrap().memory;
        let mut result = Array::new();
        let page_address = (page as u16 * 256) as u16;
        for i in 0..256 {
            result.push(memory.get_byte(page_address + i as u16));
        }
        result
    }

    #[func]
    pub fn read_memory(&self, address: u16) -> u8 {
        let cpu = self.cpu().get_cpu();
        let mut cpu_guard = cpu.lock().unwrap();
        cpu_guard.memory.get_byte(address)
    }

    #[func]
    pub fn set_memory(&self, address: u16, value: u8) {
        let cpu = self.cpu().get_cpu();
        let mut cpu_guard = cpu.lock().unwrap();
        cpu_guard.memory.set_byte(address, value);
    }

    #[func]
    pub fn set_program_counter(&self, address: u16) {
        let cpu = self.cpu().get_cpu();
        let mut cpu_guard = cpu.lock().unwrap();
        cpu_guard.registers.program_counter = address;
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
    pub fn get_line_number(&self, pc: u16) -> i32 {
        let line = self.cpu().get_line_number(pc);
        match line {
            Some(line) => line as i32,
            None => -1,
        }
    }
}
