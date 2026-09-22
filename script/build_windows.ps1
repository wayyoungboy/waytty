$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FlutterBin = if ($env:WAYTTY_FLUTTER) { $env:WAYTTY_FLUTTER } else { (Get-Command flutter).Source }
Push-Location (Join-Path $ProjectRoot 'crossplatform/app')
try {
    & $FlutterBin pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    & $FlutterBin build windows --release --no-pub "--dart-define=WAYTTY_CLOUD_URL=$env:WAYTTY_CLOUD_URL"
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    $Output = Join-Path $ProjectRoot 'dist/waytty-windows.zip'
    New-Item -ItemType Directory -Force (Split-Path -Parent $Output) | Out-Null
    Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath $Output -Force
    Write-Output "Built: $Output"
} finally { Pop-Location }
