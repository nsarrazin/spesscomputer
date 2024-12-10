#!/bin/bash

# Remove any existing object and binary files
rm -f "$1.o" "$1.bin"

# Compile the assembly file using ca65
ca65 "$1.a65"

# Link the object file using ld65 with the linker config
ld65 -C linker.cfg -o "$1.bin" "$1.o"

# Copy the binary file to the godot directory
cp "$1.bin" "../godot/binaries/$1.bin"
