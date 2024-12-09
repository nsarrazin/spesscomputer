use std::time::Instant;


pub fn compile_file(name: &str, path: &str) {
    let start_time = Instant::now();

    let _ = std::process::Command::new("rm")
        .current_dir(path)
        .arg(format!("{}.o", name))
        .arg(format!("{}.bin", name))
        .spawn();

    while std::path::Path::new(&format!("{}/{}.bin", path, name)).exists() {
        if start_time.elapsed().as_secs() > 5 {
            panic!("Timeout waiting for {}.bin to be deleted", name);
        }
    }

    // compile controller
    let _ = std::process::Command::new("ca65")
        .current_dir(path)
        .arg(format!("{}.a65", name))
        .spawn();

    while !std::path::Path::new(&format!("{}/{}.o", path, name)).exists() {
        if start_time.elapsed().as_secs() > 5 {
            panic!("Timeout waiting for {}.o to be created", name);
        }
    }

    let _ = std::process::Command::new("ld65")
        .current_dir(path)
        .arg("-C")
        .arg("linker.cfg")
        .arg("-o")
        .arg(format!("{}.bin", name))
        .arg(format!("{}.o", name))
        .spawn();

    // wait until the file exists to return, or timeout after 5s and panic
    while !std::path::Path::new(&format!("{}/{}.bin", path, name)).exists() {
        if start_time.elapsed().as_secs() > 5 {
            panic!("Timeout waiting for {}.bin to be created", name);
        }
    }
}