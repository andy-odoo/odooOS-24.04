#!/bin/bash

#Install espanso from source (X11 build) — the packaged .deb has been unreliable;
#pin to a specific release tag so this always produces the same build (bump to upgrade)
#Does not register/start the service — run `espanso service register && espanso start`
#yourself once it's installed.

ESPANSO_VERSION="v2.4.0"
BUILD_DIR="/tmp/espanso-build"

#Install X11 build dependencies

sudo apt install -y git build-essential pkg-config libx11-dev libxtst-dev libxkbcommon-dev libdbus-1-dev 'libwxgtk3.*-dev'

#Install Rust toolchain (skipped if already present)

if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
fi
source "$HOME/.cargo/env"

#Clone and build espanso

echo "Building espanso ${ESPANSO_VERSION} from source (this can take a while)..."
rm -rf "$BUILD_DIR"
git clone --branch "$ESPANSO_VERSION" --depth 1 https://github.com/espanso/espanso "$BUILD_DIR"
(cd "$BUILD_DIR" && cargo build --release --no-default-features --features modulo,vendored-tls)

#Install the binary

if [ -x "$BUILD_DIR/target/release/espanso" ]; then
    sudo mv "$BUILD_DIR/target/release/espanso" /usr/local/bin/espanso
    sudo chmod 755 /usr/local/bin/espanso
    rm -rf "$BUILD_DIR"
    echo "espanso ${ESPANSO_VERSION} installed to /usr/local/bin/espanso."
    echo "Run 'espanso service register' then 'espanso start' to enable it."
else
    echo "ERROR: espanso build failed — binary not found at target/release/espanso."
    exit 1
fi
