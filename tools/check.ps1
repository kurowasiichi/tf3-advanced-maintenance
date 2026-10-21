# Type-checks all Teal files of the mod against the game's definitions (see tlconfig.lua).
# Usage: powershell -ExecutionPolicy Bypass -File tools\check.ps1
$project = Split-Path -Parent $PSScriptRoot
Push-Location $project
try {
    $files = Get-ChildItem content -Recurse -Filter *.tl | ForEach-Object { $_.FullName.Substring($project.Length + 1) }
    & tl check @files
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
