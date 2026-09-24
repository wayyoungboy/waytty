# Build qjsbridge.dll for Windows. Prefer Clang: MSVC rejects QuickJS's
# JSValue casts and libbf GCC builtins. Falls back to clang-cl if needed.
$ErrorActionPreference = 'Stop'
$NativeDir = $PSScriptRoot
$OutDir = Join-Path $NativeDir '..\assets\native\windows'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDll = Join-Path $OutDir 'qjsbridge.dll'

function Find-Clang {
    foreach ($name in @('clang', 'clang-cl')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $candidates = @(
        'C:\Program Files\LLVM\bin\clang.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\Llvm\x64\bin\clang.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\Llvm\x64\bin\clang.exe',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\Llvm\x64\bin\clang.exe'
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

$Clang = Find-Clang
if (-not $Clang) {
    Write-Host 'Clang not found; installing LLVM via winget/choco if available...'
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install llvm -y --no-progress
    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id LLVM.LLVM -e --accept-source-agreements --accept-package-agreements
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $Clang = Find-Clang
}
if (-not $Clang) { throw 'Clang is required to build qjsbridge.dll on Windows' }

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

# Mirror build_macos.sh flags; produce a MinGW/MSVC-compatible DLL via clang -shared.
& $Clang -shared -O2 `
    "-DCONFIG_VERSION=`"2024-01-13`"" `
    '-DCONFIG_BIGNUM' `
    "-I$IncludeQuickjs" `
    "-I$IncludeBridge" `
    @Sources `
    -o $OutDll
if ($LASTEXITCODE -ne 0) { throw "clang failed to build qjsbridge.dll (exit $LASTEXITCODE)" }
if (-not (Test-Path $OutDll)) { throw "qjsbridge.dll not produced at $OutDll" }
Write-Output "Built: $OutDll"
