# Build a portable Windows release ZIP for waytty.
# Requires Flutter 3.47.2+, Visual Studio 2022 C++ workload, and CMake.
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FlutterBin = if ($env:WAYTTY_FLUTTER) { $env:WAYTTY_FLUTTER } else { (Get-Command flutter).Source }
$Version = (Select-String -Path (Join-Path $ProjectRoot 'crossplatform\app\pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
if (-not $Version) { throw 'Could not read version from pubspec.yaml' }

$CloudUrl = if ($null -ne $env:WAYTTY_CLOUD_URL) { $env:WAYTTY_CLOUD_URL } else { '' }

# Native QuickJS bridge used by the script/plugin engine.
& (Join-Path $ProjectRoot 'crossplatform\packages\yourssh_script_engine\native\build_windows.ps1')
if ($LASTEXITCODE -ne 0 -and -not $?) { throw 'qjsbridge Windows build failed' }

Push-Location (Join-Path $ProjectRoot 'crossplatform\app')
try {
    & $FlutterBin pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    & $FlutterBin build windows --release "--dart-define=WAYTTY_CLOUD_URL=$CloudUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }

    $ReleaseDir = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
    if (-not (Test-Path (Join-Path $ReleaseDir 'waytty.exe'))) {
        throw "Missing waytty.exe under $ReleaseDir"
    }

    # Bundle script-engine native library next to the executable.
    $QjsDll = Join-Path $ProjectRoot 'crossplatform\packages\yourssh_script_engine\assets\native\windows\qjsbridge.dll'
    Copy-Item -Force $QjsDll (Join-Path $ReleaseDir 'qjsbridge.dll')

    # License / notices next to the portable build.
    Copy-Item -Force (Join-Path $ProjectRoot 'LICENSE') (Join-Path $ReleaseDir 'LICENSE.txt')
    Copy-Item -Force (Join-Path $ProjectRoot 'THIRD_PARTY_NOTICES.md') (Join-Path $ReleaseDir 'THIRD_PARTY_NOTICES.md')
    $LicenseDir = Join-Path $ReleaseDir 'third-party-licenses'
    New-Item -ItemType Directory -Force $LicenseDir | Out-Null
    Copy-Item -Force (Join-Path $ProjectRoot 'crossplatform\packages\yourssh_script_engine\native\QUICKJS-LICENSE.txt') (Join-Path $LicenseDir 'QUICKJS-LICENSE.txt')
    if (Test-Path (Join-Path (Get-Location) 'assets\serial-licenses')) {
        Copy-Item -Recurse -Force (Join-Path (Get-Location) 'assets\serial-licenses') (Join-Path $LicenseDir 'serial')
    }
    if (Test-Path (Join-Path (Get-Location) 'assets\fonts\licenses')) {
        Copy-Item -Recurse -Force (Join-Path (Get-Location) 'assets\fonts\licenses') (Join-Path $LicenseDir 'fonts')
    }

    $DistRoot = Join-Path $ProjectRoot 'dist'
    $OutDir = Join-Path $DistRoot "release\$Version"
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $ZipName = "waytty-$Version-windows-x64.zip"
    $ZipPath = Join-Path $OutDir $ZipName
    if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }

    # Stage under a versioned folder so unzip creates a clear top-level directory.
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

    # Convenience copy at dist/ root for local scripts / older docs.
    Copy-Item -Force $ZipPath (Join-Path $DistRoot 'waytty-windows.zip')
    Write-Output "Built: $ZipPath"
    Write-Output "SHA256: $Hash"
} finally { Pop-Location }
