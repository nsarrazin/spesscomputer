# Spesscomputer

## Setup

Requires godot installed and cargo. You will also need to install cc65.

```bash
sudo apt install cc65
```

### Compile library

Navigate to the `godot-6502` directory and run:

```bash
cargo build
```

### Compile demo assembly

Navigate to the `assembly` directory and run:

```bash
./compile.sh demo
```

### Run demo

Open the godot project in the `godot` directory and run the scene.