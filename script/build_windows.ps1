# Build a portable Windows release ZIP for waytty.
# Requires Flutter 3.47.2+, Visual Studio C++ workload, and MinGW (for qjsbridge.dll).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FlutterBin = if ($env:WAYTTY_FLUTTER) { $env:WAYTTY_FLUTTER } else { (Get-Command flutter).Source }
# On Windows prefer flutter.bat when a unix-style flutter shim was configured.
if ($IsWindows -or $env:OS -match 'Windows') {
    if ($FlutterBin -match '[\\/]flutter$' -and (Test-Path ($FlutterBin + '.bat'))) {
        $FlutterBin = $FlutterBin + '.bat'
    }
}
$Version = (Select-String -Path (Join-Path $ProjectRoot 'crossplatform\app\pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
if (-not $Version) { throw 'Could not read version from pubspec.yaml' }

$CloudUrl = if ($null -ne $env:WAYTTY_CLOUD_URL) { $env:WAYTTY_CLOUD_URL } else { '' }

function Invoke-Native {
    param([ScriptBlock]$Command, [string]$FailureMessage)
    $global:LASTEXITCODE = 0
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$FailureMessage (exit $LASTEXITCODE)" }
}

# Build Flutter app first (uses MSVC). MinGW is only needed for qjsbridge.dll.
Push-Location (Join-Path $ProjectRoot 'crossplatform\app')
try {
    Invoke-Native { & $FlutterBin pub get } 'flutter pub get failed'
    Invoke-Native {
        & $FlutterBin build windows --release "--dart-define=WAYTTY_CLOUD_URL=$CloudUrl"
    } 'Windows Flutter build failed'

    $ReleaseDir = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
    if (-not (Test-Path (Join-Path $ReleaseDir 'waytty.exe'))) {
        $found = Get-ChildItem -Path (Join-Path (Get-Location) 'build\windows') -Recurse -Filter 'waytty.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 5 -ExpandProperty FullName
        throw "Missing waytty.exe under $ReleaseDir. Found: $($found -join ', ')"
    }
} finally { Pop-Location }

# Native QuickJS bridge used by the script/plugin engine (MinGW).
Invoke-Native {
    & (Join-Path $ProjectRoot 'crossplatform\packages\yourssh_script_engine\native\build_windows.ps1')
} 'qjsbridge Windows build failed'

$ReleaseDir = Join-Path $ProjectRoot 'crossplatform\app\build\windows\x64\runner\Release'
$QjsDll = Join-Path $ProjectRoot 'crossplatform\packages\yourssh_script_engine\assets\native\windows\qjsbridge.dll'
Copy-Item -Force $QjsDll (Join-Path $ReleaseDir 'qjsbridge.dll')

Copy-Item -Force (Join-Path $ProjectRoot 'LICENSE') (Join-Path $ReleaseDir 'LICENSE.txt')
Copy-Item -Force (Join-Path $ProjectRoot 'THIRD_PARTY_NOTICES.md') (Join-Path $ReleaseDir 'THIRD_PARTY_NOTICES.md')
$LicenseDir = Join-Path $ReleaseDir 'third-party-licenses'
New-Item -ItemType Directory -Force $LicenseDir | Out-Null
Copy-Item -Force (Join-Path $ProjectRoot 'crossplatform\packages\yourssh_script_engine\native\QUICKJS-LICENSE.txt') (Join-Path $LicenseDir 'QUICKJS-LICENSE.txt')
$AppDir = Join-Path $ProjectRoot 'crossplatform\app'
if (Test-Path (Join-Path $AppDir 'assets\serial-licenses')) {
    Copy-Item -Recurse -Force (Join-Path $AppDir 'assets\serial-licenses') (Join-Path $LicenseDir 'serial')
}
if (Test-Path (Join-Path $AppDir 'assets\fonts\licenses')) {
    Copy-Item -Recurse -Force (Join-Path $AppDir 'assets\fonts\licenses') (Join-Path $LicenseDir 'fonts')
}

$DistRoot = Join-Path $ProjectRoot 'dist'
$OutDir = Join-Path $DistRoot "release\$Version"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$ZipName = "waytty-$Version-windows-x64.zip"
$ZipPath = Join-Path $OutDir $ZipName
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }

$Stage = Join-Path $DistRoot "windows-stage\waytty-$Version-windows-x64"
if (Test-Path (Split-Path -Parent $Stage)) { Remove-Item -Recurse -Force (Split-Path -Parent $Stage) }
New-Item -ItemType Directory -Force $Stage | Out-Null
Copy-Item -Recurse -Force (Join-Path $ReleaseDir '*') $Stage
Compress-Archive -Path $Stage -DestinationPath $ZipPath -Force

$Hash = (Get-FileHash -Algorithm SHA256 $ZipPath).Hash.ToLower()
$Sums = Join-Path $OutDir 'SHA256SUMS-windows.txt'
"${Hash}  ${ZipName}" | Set-Content -Encoding ascii $Sums

$Info = Join-Path $OutDir 'BUILD_INFO-windows.txt'
@(
    "product=waytty"
    "version=$Version"
    "platform=windows-x64"
    "artifact=$ZipName"
    "sha256=$Hash"
    "flutter=$(& $FlutterBin --version --machine 2>$null)"
    "built_at_utc=$((Get-Date).ToUniversalTime().ToString('o'))"
    "note=Portable ZIP. Not an installer. Target-device acceptance is separate from CI packaging."
) | Set-Content -Encoding utf8 $Info

Copy-Item -Force $ZipPath (Join-Path $DistRoot 'waytty-windows.zip')
Write-Output "Built: $ZipPath"
Write-Output "SHA256: $Hash"
