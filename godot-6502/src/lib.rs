use godot::prelude::*;
use std::sync::{Arc, Mutex};
use std::thread;
use mos6502::memory::Bus;
use mos6502::memory::Memory;
use mos6502::instruction::Nmos6502;
use mos6502::cpu::CPU;
use std::time::Instant;

use uuid::Uuid;

use lazy_static::lazy_static;
use std::collections::HashMap;

#[derive(Clone)]
struct CPUWrapper {
    cpu: Arc<Mutex<CPU<Memory, Nmos6502>>>,
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
            self.cpu.lock().unwrap().single_step();
        }
    }
}

struct Orchestrator {
    cpus: HashMap<Uuid, CPUWrapper>
}

impl Orchestrator {
    pub fn new() -> Self {
        Self {
            cpus: HashMap::new()
        }
    }

    pub fn remove_cpu(&mut self, key: Uuid) {
        self.cpus.remove(&key);
    }

    pub fn get_cpu(&self, key: Uuid) -> &CPUWrapper {
        match self.cpus.get(&key) {
            Some(cpu_wrapper) => cpu_wrapper,
            None => panic!("No CPU found for key {}", key)
        }
    }

    pub fn create_cpu_from_file(&mut self, path: String) -> Uuid {
        let key = uuid::Uuid::new_v4();

        let cpu = Arc::new(Mutex::new(CPU::new(Memory::new(), Nmos6502)));

        let program = std::fs::read(path).unwrap();
        cpu.lock().unwrap().memory.set_bytes(0x0600, &program);
        cpu.lock().unwrap().registers.program_counter = 0x0600;

        self.cpus.insert(key, CPUWrapper {
            cpu,
        });

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
    frequency: i32
}

#[godot_api]
impl Emulator6502 {
    #[func]
    pub fn create_cpu(path: String, frequency: i32) -> Gd<Self> {
        let key = ORCHESTRATOR.lock().unwrap().create_cpu_from_file(path);
        return Gd::from_object(Emulator6502 {
            key: key.to_string(),
            frequency
        })
    }

    fn cpu(&self) -> CPUWrapper {   
        let key = Uuid::parse_str(&self.key).unwrap();
        let guard = ORCHESTRATOR.lock().unwrap();
        let cpu = guard.get_cpu(key).clone();
        drop(guard);
        cpu
    }

    #[func]
    pub fn _process(&self, delta: f64) {
        // Calculate how many CPU cycles to execute based on time delta and target frequency
        let steps = (delta * self.frequency as f64) as u32;
        self.cpu().run_steps(steps);
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
    pub fn get_cpu_state(&self) -> String {
        let cpu = self.cpu().get_cpu();
        let mut state = String::new();
        state.push_str(&format!("PC: {:04x}\n", cpu.lock().unwrap().registers.program_counter));
        state.push_str(&format!("A: {:02x}\n", cpu.lock().unwrap().registers.accumulator));
        state.push_str(&format!("X: {:02x}\n", cpu.lock().unwrap().registers.index_x));
        state.push_str(&format!("Y: {:02x}\n", cpu.lock().unwrap().registers.index_y));
        state.push_str(&format!("P: {:02x}\n", cpu.lock().unwrap().registers.status));
        state.push_str(&format!("SP: {:02x}\n", cpu.lock().unwrap().registers.stack_pointer.0));
        state.push_str(&format!("Status: {:02x}\n", cpu.lock().unwrap().registers.status));
        state
    }

    #[func]
    pub fn set_memory(&self, address: u16, value: u8) {
        let cpu = self.cpu().get_cpu();
        let mut cpu_guard = cpu.lock().unwrap();
        cpu_guard.memory.set_byte(address, value);
    }
}
