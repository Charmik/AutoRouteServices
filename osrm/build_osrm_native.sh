#!/bin/bash
set -e

OS="$(uname -s)"

if [ "$OS" = "Linux" ]; then
    # Linux build
    cd ~/disk/osrm-backend
    rm -rf ~/disk/osrm-backend/build
    mkdir -p build
    cd ~/disk/osrm-backend/build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-Wno-error -w" -DCMAKE_CXX_FLAGS="-Wno-error -w"
    cmake --build . -j$(nproc) && cmake --build . --target install -j$(nproc)

elif [ "$OS" = "Darwin" ]; then
    # MacOS build
    cd ~/Dropbox/prog/osrm-backend/build/
    rm -rf ~/Dropbox/prog/osrm-backend/build/*
    cmake .. -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="-Wno-error -w" \
        -DCMAKE_CXX_FLAGS="-Wno-error -w" \
        -DLUA_INCLUDE_DIR=/opt/homebrew/opt/lua@5.4/include/lua5.4 \
        -DLUA_LIBRARY=/opt/homebrew/opt/lua@5.4/lib/liblua.dylib
    cmake --build . -j$(nproc) && cmake --build . --target install -j$(nproc)

else
    echo "Unsupported OS: $OS"
    exit 1
fi
