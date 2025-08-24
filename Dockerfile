FROM debian:bookworm-slim AS base
ARG JOBS=16

SHELL ["/bin/bash", "-lc"]
ENV DEBIAN_FRONTEND=noninteractive
ENV EMSDK_QUIET=1

RUN apt-get update && apt-get install -y \
    git curl scons python3 build-essential pkg-config cmake zip \
    libx11-dev libxcursor-dev libxinerama-dev libgl1-mesa-dev \
    libxi-dev libxrandr-dev clang lld libc6-dev libclang-dev jq xorg blender wget \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/setup_emsdk.sh /src/scripts/setup_emsdk.sh 
RUN bash /src/scripts/setup_emsdk.sh 
ENV PATH="/emsdk/upstream/emscripten:/emsdk/node/22.16.0_64bit/bin:/emsdk:${PATH}"
ENV EMSDK_QUIET=1

FROM base AS godot-build
WORKDIR /src
RUN git clone https://github.com/godotengine/godot.git -b 4.4.1-stable
WORKDIR /src/godot

# build godot at /src/godot/bin/godot.linuxbsd.editor.double.x86_64 
RUN scons -j${JOBS} platform=linuxbsd production=yes precision=double

# # must source emsdk in same shell as scons
RUN . /emsdk/emsdk_env.sh && scons -j${JOBS} platform=web dlink_enabled=yes target=template_release precision=double

# WORKDIR /src
# build the extension then the godot project
FROM base AS project-build

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && . $HOME/.cargo/env \
    && rustup toolchain install nightly \
    && rustup component add rust-src --toolchain nightly \
    && rustup target add wasm32-unknown-emscripten --toolchain nightly

ENV PATH=/root/.cargo/bin:$PATH

COPY --from=godot-build /src/godot/bin/godot.linuxbsd.editor.double.x86_64 /usr/local/bin/godot
ENV GODOT4_BIN="/usr/local/bin/godot"

WORKDIR /tmp

RUN git clone https://github.com/valerino/rv6502emu
WORKDIR /tmp/rv6502emu
RUN git checkout b5ecd2ce8382a7a891bb0d1c1ce14a17549ef73a
# have to do it this ugly way because for some reason submodules dont work
RUN cd tests && git clone https://github.com/valerino/6502_65C02_functional_tests.git

WORKDIR /src
COPY godot-6502 /src/godot-6502
WORKDIR /src/godot-6502

# Patch Cargo.toml to use local rv6502emu source
RUN sed -i 's|rv6502emu = { git = "https://github.com/valerino/rv6502emu", version = "0.1.0" }|rv6502emu = { path = "/tmp/rv6502emu" }|' Cargo.toml

# build the extension into /src/godot-6502/target/wasm32-unknown-emscripten/release/godot_6502.wasm
RUN bash -lc '. /emsdk/emsdk_env.sh && \
SYSROOT=/emsdk/upstream/emscripten/cache/sysroot && \
mkdir -p "$SYSROOT" && \
LIBCLANG_FILE=$(find /emsdk -name "libclang.so*" -type f 2>/dev/null | head -1) && \
if [ -n "$LIBCLANG_FILE" ]; then \
  export LIBCLANG_PATH=$(dirname "$LIBCLANG_FILE"); \
else \
  export LIBCLANG_PATH=/usr/lib/x86_64-linux-gnu; \
fi && \
export BINDGEN_EXTRA_CLANG_ARGS_wasm32_unknown_emscripten="--target=wasm32-unknown-emscripten --sysroot=$SYSROOT -D__EMSCRIPTEN__ -isystem$SYSROOT/include -isystem$SYSROOT/system/include" && \
export BINDGEN_EXTRA_CLANG_ARGS="--target=wasm32-unknown-emscripten --sysroot=$SYSROOT -D__EMSCRIPTEN__ -isystem$SYSROOT/include -isystem$SYSROOT/system/include" && \
cargo +nightly build -Zbuild-std --target wasm32-unknown-emscripten --release && cargo build'


COPY scripts/setup_editor_settings_version.sh /src/scripts/setup_editor_settings_version.sh
COPY scripts/setup_blender_editor_path.sh /src/scripts/setup_blender_editor_path.sh
COPY scripts/install_blender.sh /src/scripts/install_blender.sh

ENV BLENDER_VERSION="3.0.1"
ENV GODOT_VERSION="4.4"

COPY godot /src/godot
COPY --from=godot-build /src/godot/bin/godot.web.template_release.double.wasm32.dlink.zip /src/godot/.godot_templates/godot.web.template_release.double.wasm32.dlink.zip

RUN mkdir -p /web

RUN chmod +x /src/scripts/setup_editor_settings_version.sh && \
    chmod +x /src/scripts/setup_blender_editor_path.sh && \
    chmod +x /src/scripts/install_blender.sh

RUN godot -v -e --quit --headless


ENV PATH="/opt/blender:${PATH}"

RUN /src/scripts/setup_editor_settings_version.sh && \
    /src/scripts/install_blender.sh && \
    /src/scripts/setup_blender_editor_path.sh

WORKDIR /src/godot

# Install numpy for Python in project-build stage
RUN apt-get update && apt-get install -y python3-pip python3-numpy && rm -rf /var/lib/apt/lists/*


RUN $GODOT4_BIN --headless --path . --import
RUN $GODOT4_BIN --headless --path . --export-release "Web" /web/SpessComputer.html

# final stage, builds the svelte app with the wasm dependencies
FROM node:22-alpine AS web-build

COPY web /src/web

WORKDIR /src/web
RUN npm i

COPY --from=project-build /web/* /src/web/static/
RUN npm run build

# TODO: replace this with a proper server
ENTRYPOINT ["npm", "run", "preview", "--", "--host", "0.0.0.0", "--port", "3000"]