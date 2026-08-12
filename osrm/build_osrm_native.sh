#!/bin/bash
set -e

OS="$(uname -s)"

# --full: wipe the source tree and re-clone it from scratch.
# Without it we build whatever is already checked out in $SRC.
FULL=false
for arg in "$@"; do
    case "$arg" in
        --full) FULL=true ;;
        *) echo "Unknown option: $arg (usage: $0 [--full])"; exit 1 ;;
    esac
done

# nproc is Linux-only; getconf works on both Linux and macOS.
# nproc is Linux-only; getconf works on both Linux and macOS.
NPROC="$(getconf _NPROCESSORS_ONLN)"

# Since b63d6b4d1 all dependencies (boost, tbb, lua, libarchive, ...) come from
# vcpkg in manifest mode -- see vcpkg.json. Bootstrap it once if it's missing.
: "${VCPKG_ROOT:=$HOME/vcpkg}"
if [ ! -f "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" ]; then
    echo "Bootstrapping vcpkg into $VCPKG_ROOT ..."
    git clone https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
fi
export VCPKG_ROOT

# osrm-backend's CMakeLists.txt does cmake_policy(SET CMP0156 NEW), and that
# policy only exists in CMake 3.30+. Ubuntu 24.04 still ships 3.28, which fails
# configure with 'Policy "CMP0156" is not known to this version of CMake'.
# vcpkg keeps its own recent cmake around, so fall back to that one.
CMAKE_MIN=3.30
cmake_ok() {
    local v
    v="$("$1" --version 2>/dev/null | head -1 | awk '{print $3}')"
    [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$CMAKE_MIN" "$v" | sort -V | head -1)" = "$CMAKE_MIN" ]
}

CMAKE=cmake
if ! cmake_ok "$CMAKE"; then
    CMAKE=""
    for candidate in "$VCPKG_ROOT"/downloads/tools/cmake-*/*/bin/cmake; do
        if cmake_ok "$candidate"; then CMAKE="$candidate"; break; fi
    done
    # Nothing downloaded yet (fresh vcpkg) -- ask vcpkg to fetch one.
    if [ -z "$CMAKE" ]; then
        candidate="$("$VCPKG_ROOT/vcpkg" fetch cmake 2>/dev/null | tail -1)"
        if [ -n "$candidate" ] && cmake_ok "$candidate"; then CMAKE="$candidate"; fi
    fi
    if [ -z "$CMAKE" ]; then
        echo "Need CMake >= $CMAKE_MIN (system cmake is $(cmake --version 2>/dev/null | head -1))."
        echo "Install a newer one, e.g. 'pip install --break-system-packages cmake' or the Kitware apt repo."
        exit 1
    fi
    echo "System cmake is too old, using $CMAKE ($("$CMAKE" --version | head -1))"
fi

if [ "$OS" = "Linux" ]; then
    SRC=~/disk/osrm-backend
elif [ "$OS" = "Darwin" ]; then
    SRC=~/Dropbox/prog/osrm-backend
else
    echo "Unsupported OS: $OS"
    exit 1
fi

if [ "$FULL" = true ]; then
    # Start from a pristine checkout -- anything in $SRC is wiped.
    rm -rf "$SRC"
    git clone https://github.com/Charmik/osrm-backend.git "$SRC"
    cd "$SRC"
#    git checkout fix-segfaults-asserts-hacks
    git checkout master_fresh_with_compact_fix
fi

cd $SRC
git pull

rm -rf "$SRC/build"
mkdir -p "$SRC/build"
cd "$SRC/build"

# The first configure builds every dependency from source and takes a while.
# Later runs reuse vcpkg's binary cache even though we wipe build/ above.
"$CMAKE" .. \
    -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-Wno-error -w" \
    -DCMAKE_CXX_FLAGS="-Wno-error -w"

"$CMAKE" --build . -j"$NPROC"
"$CMAKE" --build . --target install -j"$NPROC"
