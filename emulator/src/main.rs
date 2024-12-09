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

pub fn create_cpu(path: &str, key: Option<&str>) -> Arc<Mutex<cpu::CPU<Memory, Nmos6502>>> {
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
    let key = key.unwrap_or("computer").to_string();

    thread::spawn(move || {
        let client = Client::open("redis://127.0.0.1/").unwrap();
        let mut con = client.get_connection().unwrap();
    
        loop {
            let page_3: Vec<u8> = con.get(&key).unwrap_or_default();
            for (i, &value) in page_3.iter().take(32).enumerate() {
                thread_cpu.lock().unwrap().memory.set_byte(0x0200 + i as u16, value);
            }

            // println!("{:?}", page_3);
            
            let _: () = con.set(&key, page_3).unwrap();

            thread_cpu.lock().unwrap().single_step();

            if thread_cpu.lock().unwrap().registers.program_counter == 0xFFFF {
                println!("CPU halted - PC reached 0xFFFF");
                break;
            }
            
            // stepping cpu at 5khz (200us per cycle)
            let mut page_3 = Vec::with_capacity(32);
            for i in 0..32 {
                page_3.push(thread_cpu.lock().unwrap().memory.get_byte(0x0200 + i));
            }

            let _: () = con.set(&key, page_3).unwrap();

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
    let name = "demo";
    let folder = "examples/";
    compile_file(name, folder);
    
    let mut cpus = Vec::new();
    for i in 0..1 {
        let cpu_name = format!("computer_{}", i);
        cpus.push(create_cpu(
            &format!("{}/{}.bin", folder, name),
            Some(cpu_name.as_str())
        ));
    }

    loop {
        spin_sleep::sleep(std::time::Duration::from_millis(10));
    }
}
