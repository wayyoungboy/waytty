# Build qjsbridge.dll for Windows desktop packaging.
$ErrorActionPreference = 'Stop'
$NativeDir = $PSScriptRoot
$OutDir = Join-Path $NativeDir '..\assets\native\windows'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$BuildDir = Join-Path $NativeDir 'build-windows'
if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
New-Item -ItemType Directory -Force $BuildDir | Out-Null

# Let CMake pick the installed VS generator; pin architecture to x64.
cmake -S $NativeDir -B $BuildDir -A x64
if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed for qjsbridge' }
cmake --build $BuildDir --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw 'cmake build failed for qjsbridge' }

$Dll = Get-ChildItem -Path $BuildDir -Recurse -Filter 'qjsbridge.dll' |
    Where-Object { $_.FullName -match '\\Release\\' -or $_.DirectoryName -match 'Release' } |
    Select-Object -First 1
if (-not $Dll) {
    $Dll = Get-ChildItem -Path $BuildDir -Recurse -Filter 'qjsbridge.dll' | Select-Object -First 1
}
if (-not $Dll) { throw 'qjsbridge.dll not produced' }
Copy-Item -Force $Dll.FullName (Join-Path $OutDir 'qjsbridge.dll')
Write-Output "Built: $(Join-Path $OutDir 'qjsbridge.dll')"
