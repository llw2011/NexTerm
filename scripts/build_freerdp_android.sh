#!/bin/bash
# Build FreeRDP for Android arm64-v8a
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FREERDP_SRC="$PROJECT_DIR/freerdp_src"
BUILD_DIR="$PROJECT_DIR/freerdp_build"
OUTPUT_DIR="$PROJECT_DIR/android/app/src/main/jniLibs"

NDK_PATH="/mnt/c/Users/Administrator/AppData/Local/Android/Sdk/ndk/27.1.12297006"
CMAKE_EXE="/mnt/c/Users/Administrator/AppData/Local/Android/Sdk/cmake/3.22.1/bin/cmake.exe"
NINJA_EXE="/mnt/c/Users/Administrator/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe"

ABIS=("arm64-v8a" "x86_64")

for ABI in "${ABIS[@]}"; do
    echo "=== Building FreeRDP for $ABI ==="
    BUILD_ABI_DIR="$BUILD_DIR/$ABI"
    mkdir -p "$BUILD_ABI_DIR"

    # Convert paths to Windows format for cmake.exe
    FREERDP_WIN=$(wslpath -w "$FREERDP_SRC")
    BUILD_WIN=$(wslpath -w "$BUILD_ABI_DIR")
    NDK_WIN=$(wslpath -w "$NDK_PATH")
    TOOLCHAIN_WIN="$NDK_WIN\\build\\cmake\\android.toolchain.cmake"

    "$CMAKE_EXE" \
        -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$(wslpath -w "$NINJA_EXE")" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_WIN" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-26 \
        -DANDROID_NDK="$NDK_WIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DWITH_CLIENT_COMMON=ON \
        -DWITH_CLIENT=OFF \
        -DWITH_SERVER=OFF \
        -DWITH_SAMPLE=OFF \
        -DWITH_CHANNELS=ON \
        -DWITH_JPEG=OFF \
        -DWITH_OPENSSL=OFF \
        -DWITH_MBEDTLS=OFF \
        -DWITH_WINPR_TOOLS=OFF \
        -DBUILD_TESTING=OFF \
        -S "$FREERDP_WIN" \
        -B "$BUILD_WIN"

    "$CMAKE_EXE" --build "$BUILD_WIN" --parallel 4

    # Copy .so files to jniLibs
    OUT_ABI="$OUTPUT_DIR/$ABI"
    mkdir -p "$OUT_ABI"
    find "$BUILD_ABI_DIR" -name "*.so" -exec cp {} "$OUT_ABI/" \;
    echo "=== $ABI done, .so files in $OUT_ABI ==="
done

echo "=== All builds complete ==="
