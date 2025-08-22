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

### Compile Rust extension

You can compile the release build with `npm run ext:build`. 

For development inside of godot just run `cargo build`, for the web export in debug mode run `cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten`.

### Build godot project

Make sure you have built the export templates. You can export the release build with `npm run godot:export` which is equivalent to doing

```
$GODOT4_BIN --headless --path godot --export-release \"Web\" ../web/static/SpessComputer.html
```

### Build webapp

Install dependencies in the web folder: `cd web && npm i`

Once the godot build is in the static folder, you can run `npm run web:dev` in the root of the repo or export to an SPA with `npm run build`.
