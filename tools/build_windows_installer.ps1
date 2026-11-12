# Builds the Windows release and the Inno Setup installer.
# Run from the project root or anywhere:
#   .\tools\build_windows_installer.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$' |
    Select-Object -First 1
if (-not $versionLine) {
    throw 'Could not read version from pubspec.yaml'
}
$version = $versionLine.Matches[0].Groups[1].Value.Trim().Split('+')[0]

Write-Host "LM Chat ${version}: building Windows release..."
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    throw 'flutter build windows failed'
}

$candidates = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw 'ISCC.exe not found. Install Inno Setup 6.'
}

Write-Host "Inno Setup: $iscc"
& $iscc "/DMyAppVersion=$version" 'installer\lm_chat.iss'
if ($LASTEXITCODE -ne 0) {
    throw 'Installer build failed'
}

Write-Host "Done: dist\lm-chat-setup-$version.exe"
