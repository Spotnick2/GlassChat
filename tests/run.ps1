<#
    run.ps1 - Syntax-check the addon and run every tests\test_*.lua under Lua 5.1,
    through WowTestKit's runner at the commit tests\kit.pin names (its README).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev        # the ..\WowTestKit working copy instead of the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# The tests load the LibGlass checkout as it is; CI loads the .pkgmeta pin.
$libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
. (Join-Path $RepoRoot "Tools\LibGlassPin.ps1")
if (Test-Path -LiteralPath $libGlass) { Write-LibGlassPinStatus $RepoRoot $libGlass "CI tests the pin" }
$libSync = if ($env:LIBACCOUNTSYNC) { $env:LIBACCOUNTSYNC } else { Join-Path (Split-Path -Parent $RepoRoot) "LibAccountSync" }
if (Test-Path -LiteralPath $libSync) { Write-LibGlassPinStatus $RepoRoot $libSync "CI tests the pin" "Libs/LibAccountSync-1.0" }

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev

# The TOC's files are syntax-checked by the kit; these are the rest of ours.
$extra = @(Get-ChildItem -Path (Join-Path $RepoRoot "Plugins") -Recurse -Filter "*.lua" -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName })
$extra += "Tools\ChatProbe\ChatProbe.lua", "Tools\ChatProbe\Audit.lua"
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassChat.toc" -Extra $extra -Lua $Lua
exit $LASTEXITCODE
