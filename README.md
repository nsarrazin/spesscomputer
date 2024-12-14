# Spesscomputer

## Setup

Requires cc65 installed and the rust toolchain.

```bash
sudo apt install cc65
```

### Compile godot

We use godot with custom [large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html). This requires [compiling godot from source](https://docs.godotengine.org/en/stable/contributing/development/compiling/index.html#toc-devel-compiling). 
```
git clone https://github.com/godotengine/godot 
cd godot
git checkout 4.3-stable
scons platform=linuxbsd production=yes precision=double
```

Move the godot binary wherever you want and then add it to the GODOT4_BIN environment variable.

```bash
export GODOT4_BIN="/path/to/godot/bin"
```

This is required for compatibility with the custom build of godot.

### Compile library

Navigate to the `godot-6502` directory and run:

```bash
cargo build
```

### Run godot

Open the godot project in the `godot` directory and run the scene.
