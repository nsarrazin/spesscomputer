use mos6502::memory::Bus;
use mos6502::memory::Memory;
use mos6502::instruction::Nmos6502;
use mos6502::cpu;
use std::fs::read;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Instant;
use redis::{Client, Commands};

mod utils;
use utils::compile_file;

pub fn create_cpu(path: &str) -> Arc<Mutex<cpu::CPU<Memory, Nmos6502>>> {
    let program = match read(path) {
        Ok(data) => data,
        Err(err) => {
            panic!("Error reading {}: {}", path, err);
        }
    };

    let cpu = Arc::new(Mutex::new(cpu::CPU::new(Memory::new(), Nmos6502)));

    cpu.lock().unwrap().memory.set_bytes(0x0600, &program);
    cpu.lock().unwrap().registers.program_counter = 0x0600;

    let thread_cpu = cpu.clone();

    thread::spawn(move || {
        let client = Client::open("redis://127.0.0.1/").unwrap();
        let mut con = client.get_connection().unwrap();
    
        loop {
            let page_3: Vec<u8> = con.get("computer").unwrap_or_default();
            for (i, &value) in page_3.iter().take(32).enumerate() {
                thread_cpu.lock().unwrap().memory.set_byte(0x0200 + i as u16, value);
            }

            // println!("{:?}", page_3);
            let _: () = con.set("computer", page_3).unwrap();

            println!("Speed: {:02X}", thread_cpu.lock().unwrap().memory.get_byte(0x0204));
            thread_cpu.lock().unwrap().single_step();

            let registers = thread_cpu.lock().unwrap().registers;
            println!("PC: {:04X}, A: {:02X}, X: {:02X}, Y: {:02X}, P: {:02X}", registers.program_counter, registers.accumulator, registers.index_x, registers.index_y, registers.status);
            
            if registers.program_counter == 0xFFFF {
                println!("CPU halted - PC reached 0xFFFF");
                break;
            }
            
            // stepping cpu at 5khz (200us per cycle)
            let mut page_3 = Vec::with_capacity(32);
            for i in 0..32 {
                page_3.push(thread_cpu.lock().unwrap().memory.get_byte(0x0200 + i));
            }

            // println!("{:?}", page_3);
            let _: () = con.set("computer", page_3).unwrap();

            let start = Instant::now();
            let duration = start.elapsed();


            if duration.as_micros() < 200 {
                spin_sleep::sleep(std::time::Duration::from_micros(
                    200 - duration.as_micros() as u64,
                ));
            } else {
                println!(
                    "Clock cycle took an unexpected {:?}us ",
                    duration.as_micros()
                );
            }
        }
    });

    return cpu;
}

fn main() {
    compile_file("demo", "examples/");
    let _cpu = create_cpu("examples/demo.bin");

    while true {
        spin_sleep::sleep(std::time::Duration::from_millis(10));
    }
}
