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
}

impl CPUWrapper {
    pub fn get_cpu(&self) -> Arc<Mutex<CPU<Memory, Nmos6502>>> {
        self.cpu.clone()
    }

    pub fn run_step(&self) {
        self.cpu.lock().unwrap().single_step();
    }

    pub fn run_steps(&self, steps: u32) {
        for _ in 0..steps {
            self.run_step();
        }
    }

    pub fn run_steps_async(&self, steps: u32) {
        let cpu = self.cpu.clone();
        let is_running = self.is_running.clone();
        let completion_cvar = self.completion_cvar.clone();

        let (lock, cvar) = &*completion_cvar;
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

    pub fn create_cpu(&mut self, start_address: u16, program: Vec<u8>) -> Uuid {
        let key = uuid::Uuid::new_v4();

        let cpu = Arc::new(Mutex::new(CPU::new(Memory::new(), Nmos6502)));

        cpu.lock()
            .unwrap()
            .memory
            .set_bytes(start_address, &program);
        cpu.lock().unwrap().registers.program_counter = start_address;

        self.cpus.insert(
            key,
            CPUWrapper {
                cpu,
                is_running: Arc::new(Mutex::new(false)),
                completion_cvar: Arc::new((Mutex::new(false), Condvar::new())),
            },
        );

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
}

#[godot_api]
impl Emulator6502 {
    #[func]
    pub fn create_cpu(frequency: i32) -> Gd<Self> {
        let key = ORCHESTRATOR.lock().unwrap().create_cpu(0x0600, Vec::new());
        return Gd::from_object(Emulator6502 {
            key: key.to_string(),
            frequency,
        });
    }

    #[func]
    pub fn load_program(&self, program: Array<u8>, start_address: u16) {
        let key = Uuid::parse_str(&self.key).unwrap();
        let guard = ORCHESTRATOR.lock().unwrap();
        let cpu = guard.get_cpu(key).clone().get_cpu();

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
    }

    #[func]
    pub fn load_program_from_string(&self, assembly_code: String, start_address: u16) {
        let program = match asm6502::assemble_string(&assembly_code) {
            Ok(bytes) if !bytes.is_empty() => {
                godot_print!("Successfully compiled assembly from string");
                bytes
            }
            _ => {
                godot_error!("Failed to compile assembly from string");
                Vec::new()
            }
        };

        // Convert Vec<u8> to Godot Array<u8>
        let mut godot_array = Array::new();
        for byte in program {
            godot_array.push(byte);
        }

        self.load_program(godot_array, start_address);
    }

    #[func]
    pub fn create_cpu_from_string(assembly_code: String, frequency: i32) -> Gd<Self> {
        let program = match asm6502::assemble_string(&assembly_code) {
            Ok(bytes) if !bytes.is_empty() => {
                godot_print!("Successfully compiled assembly from string");
                bytes
            }
            _ => {
                godot_error!("Failed to compile assembly from string");
                Vec::new()
            }
        };

        let key = ORCHESTRATOR.lock().unwrap().create_cpu(0x0600, program);
        return Gd::from_object(Emulator6502 {
            key: key.to_string(),
            frequency,
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
    pub fn execute_cycles_for_duration(&self, delta: f64) {
        // Calculate how many CPU cycles to execute based on time delta and target frequency
        let steps = (delta * self.frequency as f64) as u32;
        self.cpu().run_steps_async(steps);
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
}
