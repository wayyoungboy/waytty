# Build qjsbridge.dll for Windows using the ClangCL toolset (clang + MSVC
# headers/SDK). Plain clang without the Windows SDK lacks sys/time.h; plain
# MSVC rejects QuickJS JSValue casts / libbf GCC builtins.
$ErrorActionPreference = 'Stop'
$NativeDir = $PSScriptRoot
$OutDir = Join-Path $NativeDir '..\assets\native\windows'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDll = Join-Path $OutDir 'qjsbridge.dll'
$BuildDir = Join-Path $NativeDir 'build-windows'
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Force $BuildDir | Out-Null

# Ensure a CMakeLists that does NOT fatal-error on MSVC when using ClangCL
# (CMAKE_C_COMPILER_ID is Clang under -T ClangCL).
cmake -S $NativeDir -B $BuildDir -G 'Visual Studio 17 2022' -A x64 -T ClangCL
if ($LASTEXITCODE -ne 0) {
    # Fallback: let cmake pick the VS generator, still request ClangCL.
    cmake -S $NativeDir -B $BuildDir -A x64 -T ClangCL
    if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed for qjsbridge (ClangCL)' }
}
cmake --build $BuildDir --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw 'cmake build failed for qjsbridge (ClangCL)' }

$Dll = Get-ChildItem -Path $BuildDir -Recurse -Filter 'qjsbridge.dll' |
    Where-Object { $_.FullName -match '\\Release\\' } |
    Select-Object -First 1
if (-not $Dll) {
    $Dll = Get-ChildItem -Path $BuildDir -Recurse -Filter 'qjsbridge.dll' | Select-Object -First 1
}
if (-not $Dll) { throw 'qjsbridge.dll not produced' }
Copy-Item -Force $Dll.FullName $OutDll
Write-Output "Built: $OutDll"
