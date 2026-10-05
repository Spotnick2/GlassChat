<#
    run.ps1 - Syntax-check the addon and run every tests\test_*.lua under Lua 5.1.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Lua)) { Write-Error "Lua 5.1 not found at $Lua (pass -Lua <path>)"; exit 1 }
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    # The TOC is the list, so a new file cannot go unchecked.
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    $tocFiles = Get-Content "GlassChat.toc" | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" }
    if (-not (Test-Path $luac)) {
        Write-Host "luac -p SKIPPED: no luac.exe beside $Lua - syntax was NOT checked" -ForegroundColor Yellow
    } else {
        $pluginFiles = Get-ChildItem -Path "Plugins" -Recurse -Filter "*.lua" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        & $luac -p @tocFiles @pluginFiles "Tools\ChatProbe\ChatProbe.lua"
        if ($LASTEXITCODE -ne 0) { Write-Host "luac -p FAILED" -ForegroundColor Red; exit 1 }
        Remove-Item -LiteralPath "luac.out" -ErrorAction SilentlyContinue
        Write-Host "luac -p: ok ($($tocFiles.Count) addon files + probe)" -ForegroundColor DarkGray
    }

    # The tests load the LibGlass checkout as it is; CI loads the .pkgmeta pin.
    $libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
    . (Join-Path $RepoRoot "Tools\LibGlassPin.ps1")
    if (Test-Path -LiteralPath $libGlass) { Write-LibGlassPinStatus $RepoRoot $libGlass "CI tests the pin" }
    $libSync = if ($env:LIBACCOUNTSYNC) { $env:LIBACCOUNTSYNC } else { Join-Path (Split-Path -Parent $RepoRoot) "LibAccountSync" }
    if (Test-Path -LiteralPath $libSync) { Write-LibGlassPinStatus $RepoRoot $libSync "CI tests the pin" "Libs/LibAccountSync-1.0" }

    $failed = 0
    Get-ChildItem (Join-Path $PSScriptRoot "test_*.lua") | Sort-Object Name | ForEach-Object {
        Write-Host "-- $($_.Name) " -NoNewline -ForegroundColor Cyan
        & $Lua $_.FullName
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($failed -gt 0) { Write-Host "$failed test file(s) FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "All test files passed." -ForegroundColor Green
}
finally { Pop-Location }
