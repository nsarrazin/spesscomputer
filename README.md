# Spesscomputer

### Compile godot

We use godot with custom [large world coordinates](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html). This requires [compiling godot from source](https://docs.godotengine.org/en/stable/contributing/development/compiling/index.html#toc-devel-compiling). 
```
git clone https://github.com/godotengine/godot 
cd godot
git checkout 4.4.1-stable
scons platform=linuxbsd production=yes precision=double
```

Move the godot binary wherever you want and then add it to the GODOT4_BIN environment variable.

```bash
export GODOT4_BIN="/path/to/godot/bin"
```

We also have to [build the export templates](https://docs.godotengine.org/en/latest/contributing/development/compiling/index.html). In the same folder:

```
scons platform=web dlink_enabled=yes target=template_release precision=double
scons platform=web dlink_enabled=yes target=template_debug precision=double
```

This is required for compatibility with the custom build of godot. When you are done with this step, drop the resulting `godot.web.template_debug.double.wasm32.dlink.zip` and `godot.web.template_release.double.wasm32.dlink.zip` in `godot/.godot_templates`.

### Compile library

Navigate to the `godot-6502` directory and run:

```bash
cargo build
```

### Run godot

Open the godot project in the `godot` directory and run the scene.
