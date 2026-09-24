# Build qjsbridge.dll for Windows with MinGW GCC.
# Plain MSVC rejects QuickJS JSValue casts / libbf; plain clang without a
# Windows/POSIX sysroot lacks sys/time.h. MinGW provides a working toolchain.
$ErrorActionPreference = 'Stop'
$NativeDir = $PSScriptRoot
$OutDir = Join-Path $NativeDir '..\assets\native\windows'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDll = Join-Path $OutDir 'qjsbridge.dll'

function Find-MingwGcc {
    foreach ($name in @('gcc', 'x86_64-w64-mingw32-gcc')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($path in @(
        'C:\ProgramData\mingw64\mingw64\bin\gcc.exe',
        'C:\mingw64\bin\gcc.exe',
        'C:\Program Files\mingw-w64\*\mingw64\bin\gcc.exe'
    )) {
        $resolved = Get-Item $path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) { return $resolved.FullName }
    }
    return $null
}

$Gcc = Find-MingwGcc
if (-not $Gcc) {
    Write-Host 'MinGW gcc not found; installing via choco...'
    choco install mingw -y --no-progress
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
    # Common chocolatey mingw location
    $chocoMingw = 'C:\ProgramData\mingw64\mingw64\bin'
    if (Test-Path $chocoMingw) { $env:Path = "$chocoMingw;$env:Path" }
    $Gcc = Find-MingwGcc
}
if (-not $Gcc) { throw 'MinGW gcc is required to build qjsbridge.dll on Windows' }

$Sources = @(
    (Join-Path $NativeDir 'quickjs\quickjs.c'),
    (Join-Path $NativeDir 'quickjs\libunicode.c'),
    (Join-Path $NativeDir 'quickjs\libregexp.c'),
    (Join-Path $NativeDir 'quickjs\cutils.c'),
    (Join-Path $NativeDir 'quickjs\libbf.c'),
    (Join-Path $NativeDir 'bridge\qjs_bridge.c')
)
$IncludeQuickjs = Join-Path $NativeDir 'quickjs'
$IncludeBridge = Join-Path $NativeDir 'bridge'

& $Gcc -shared -O2 -std=gnu11 `
    "-DCONFIG_VERSION=`"2024-01-13`"" `
    '-DCONFIG_BIGNUM' `
    "-I$IncludeQuickjs" `
    "-I$IncludeBridge" `
    @Sources `
    -o $OutDll `
    -lpthread
if ($LASTEXITCODE -ne 0) { throw "gcc failed to build qjsbridge.dll (exit $LASTEXITCODE)" }
if (-not (Test-Path $OutDll)) { throw "qjsbridge.dll not produced at $OutDll" }
Write-Output "Built: $OutDll with $Gcc"
