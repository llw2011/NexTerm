# build_android_libs.ps1
# 在 Windows PowerShell 中运行，编译 OpenSSL + FreeRDP for Android arm64-v8a
# 用法: powershell -ExecutionPolicy Bypass -File D:\NexTerm\scripts\build_android_libs.ps1

$ErrorActionPreference = "Stop"

$NDK     = "C:\Users\Administrator\AppData\Local\Android\Sdk\ndk\27.1.12297006"
$CMAKE   = "C:\Users\Administrator\AppData\Local\Android\Sdk\cmake\3.22.1\bin\cmake.exe"
$NINJA   = "C:\Users\Administrator\AppData\Local\Android\Sdk\cmake\3.22.1\bin\ninja.exe"
$PROJECT = "D:\NexTerm"
$OPENSSL_SRC  = "$PROJECT\openssl-3.3.2"
$FREERDP_SRC  = "$PROJECT\freerdp_src"
$OPENSSL_OUT  = "$PROJECT\openssl_android"
$FREERDP_BUILD = "$PROJECT\freerdp_build"
$JNILIBS = "$PROJECT\android\app\src\main\jniLibs"

$TOOLCHAIN = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin"
$SYSROOT   = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\sysroot"
$API       = "26"

$ABIS = @(
    @{ abi="arm64-v8a";  triple="aarch64-linux-android";  cc="aarch64-linux-android${API}-clang.cmd" },
    @{ abi="x86_64";     triple="x86_64-linux-android";   cc="x86_64-linux-android${API}-clang.cmd"  }
)

# ── Step 1: Build OpenSSL ──────────────────────────────────────────────────────
Write-Host "`n=== Building OpenSSL for Android ===" -ForegroundColor Cyan

if (-not (Test-Path $OPENSSL_SRC)) {
    Write-Error "OpenSSL source not found at $OPENSSL_SRC. Please extract openssl-3.3.2.tar.gz first."
}

foreach ($a in $ABIS) {
    $ABI    = $a.abi
    $TRIPLE = $a.triple
    $CC_CMD = $a.cc
    $OUT    = "$OPENSSL_OUT\$ABI"

    if (Test-Path "$OUT\lib\libssl.a") {
        Write-Host "OpenSSL $ABI already built, skipping." -ForegroundColor Yellow
        continue
    }

    Write-Host "Building OpenSSL for $ABI ..."
    New-Item -ItemType Directory -Force -Path $OUT | Out-Null

    $env:PATH = "$TOOLCHAIN;$env:PATH"
    $env:CC   = "$TOOLCHAIN\$CC_CMD"
    $env:AR   = "$TOOLCHAIN\llvm-ar.exe"
    $env:RANLIB = "$TOOLCHAIN\llvm-ranlib.exe"

    $opensslTarget = if ($ABI -eq "arm64-v8a") { "android-arm64" } else { "android-x86_64" }

    Push-Location $OPENSSL_SRC
    & perl Configure $opensslTarget `
        -D__ANDROID_API__=$API `
        --prefix=$OUT `
        --openssldir=$OUT `
        no-shared no-tests no-ui-console `
        "-I$SYSROOT\usr\include" `
        "-I$SYSROOT\usr\include\$TRIPLE"

    & nmake clean 2>$null
    & nmake build_libs
    & nmake install_dev
    Pop-Location

    Write-Host "OpenSSL $ABI done." -ForegroundColor Green
}

# ── Step 2: Build FreeRDP ──────────────────────────────────────────────────────
Write-Host "`n=== Building FreeRDP for Android ===" -ForegroundColor Cyan

foreach ($a in $ABIS) {
    $ABI = $a.abi
    $BUILD = "$FREERDP_BUILD\$ABI"
    $OPENSSL_ABI = "$OPENSSL_OUT\$ABI"

    Write-Host "Building FreeRDP for $ABI ..."
    New-Item -ItemType Directory -Force -Path $BUILD | Out-Null

    & $CMAKE `
        -G Ninja `
        "-DCMAKE_MAKE_PROGRAM=$NINJA" `
        "-DCMAKE_TOOLCHAIN_FILE=$NDK\build\cmake\android.toolchain.cmake" `
        "-DANDROID_ABI=$ABI" `
        "-DANDROID_PLATFORM=android-$API" `
        "-DANDROID_NDK=$NDK" `
        -DCMAKE_BUILD_TYPE=Release `
        "-DOPENSSL_ROOT_DIR=$OPENSSL_ABI" `
        "-DOPENSSL_INCLUDE_DIR=$OPENSSL_ABI\include" `
        "-DOPENSSL_CRYPTO_LIBRARY=$OPENSSL_ABI\lib\libcrypto.a" `
        "-DOPENSSL_SSL_LIBRARY=$OPENSSL_ABI\lib\libssl.a" `
        -DWITH_CLIENT_COMMON=ON `
        -DWITH_CLIENT=OFF `
        -DWITH_SERVER=OFF `
        -DWITH_SAMPLE=OFF `
        -DWITH_CHANNELS=ON `
        -DWITH_JPEG=OFF `
        -DWITH_WINPR_TOOLS=OFF `
        -DBUILD_TESTING=OFF `
        "-S=$FREERDP_SRC" `
        "-B=$BUILD"

    & $CMAKE --build $BUILD --parallel 4

    # Copy .so to jniLibs
    $OUT_ABI = "$JNILIBS\$ABI"
    New-Item -ItemType Directory -Force -Path $OUT_ABI | Out-Null
    Get-ChildItem -Path $BUILD -Recurse -Filter "*.so" | Copy-Item -Destination $OUT_ABI -Force

    Write-Host "FreeRDP $ABI done. .so files -> $OUT_ABI" -ForegroundColor Green
}

Write-Host "`n=== All done! ===" -ForegroundColor Cyan
Write-Host "JNI libs at: $JNILIBS"
