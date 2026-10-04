<#
    deploy.ps1 - Copy GlassChat (and optionally ChatProbe) into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    The glass material is the embedded LibGlass-1.0. The packager fetches it
    into Libs\LibGlass-1.0 (.pkgmeta externals); for a dev copy this script
    hands that job to the LibGlass checkout's own deploy.ps1, which checks the
    checkout, copies only the shipped files and prints its commit. The checkout
    is $env:LIBGLASS, else ..\LibGlass (GlassUnitFrames' pattern, #64).

    Usage:
        pwsh Tools/deploy.ps1               # GlassChat
        pwsh Tools/deploy.ps1 -Probe        # ...and ChatProbe
        pwsh Tools/deploy.ps1 -ProbeOnly    # just ChatProbe
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns",
    [switch]$Probe,
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }

. (Join-Path $PSScriptRoot "LibGlassPin.ps1")
$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }

function Deploy-Addon {
    $dest = Join-Path $AddOnsPath "GlassChat"
    # Only the addon needs the library: -ProbeOnly works without a checkout (review of #30).
    if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
        Write-Error "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)"
        exit 1
    }
    Write-LibGlassPinStatus $RepoRoot $LibGlass "this deploy tests a library the release won't ship"
    # The library first: its deploy checks the checkout and may refuse, and a
    # refusal must leave the deployed addon as it was (a new TOC naming a
    # library that never arrived loads no frames at all).
    & pwsh -NoProfile -File (Join-Path $LibGlass "Tools\deploy.ps1") -Addon GlassChat -AddOnsPath $AddOnsPath
    if ($LASTEXITCODE -ne 0) { Write-Error "LibGlass deploy refused; GlassChat was not touched"; exit 1 }
    Write-Host "Deploying GlassChat -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $files = @("GlassChat.toc") + (Get-ChildItem -LiteralPath $RepoRoot -Filter "*.lua" | Select-Object -ExpandProperty Name)
    foreach ($f in $files) {
        $src = Join-Path $RepoRoot $f
        if ($f -like "*.toc") {
            (Get-Content -LiteralPath $src -Raw) -replace '## Version: @project-version@', '## Version: dev' |
                Set-Content -LiteralPath (Join-Path $dest $f) -NoNewline
        } else {
            Copy-Item -LiteralPath $src -Destination (Join-Path $dest $f) -Force
        }
        Write-Host "  $f"
    }
    # A Lua file removed from the repo must not linger where the client finds it.
    Get-ChildItem -LiteralPath $dest -File | Where-Object { $files -notcontains $_.Name } | ForEach-Object {
        Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $_.FullName -Force
    }

    # The textures now ship inside Libs\LibGlass-1.0\Media; the old folder is dead weight.
    $oldMedia = Join-Path $dest "Media"
    if (Test-Path -LiteralPath $oldMedia) {
        Write-Host "  removing stale Media\ (textures now come from LibGlass)" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $oldMedia -Recurse -Force
    }

    # Each plugin is its own addon, deployed under its TOC's name (the
    # packager's move-folders does the same for releases).
    $pluginRoot = Join-Path $RepoRoot "Plugins"
    if (Test-Path $pluginRoot) {
        foreach ($dir in Get-ChildItem -LiteralPath $pluginRoot -Directory) {
            $toc = Get-ChildItem -LiteralPath $dir.FullName -Filter "*.toc" | Select-Object -First 1
            if (-not $toc) { Write-Host "  skipping Plugins\$($dir.Name): no .toc" -ForegroundColor DarkYellow; continue }
            $pdest = Join-Path $AddOnsPath $toc.BaseName
            New-Item -ItemType Directory -Force -Path $pdest | Out-Null
            foreach ($f in Get-ChildItem -LiteralPath $dir.FullName -File) {
                if ($f.Extension -eq ".toc") {
                    (Get-Content -LiteralPath $f.FullName -Raw) -replace '## Version: @project-version@', '## Version: dev' |
                        Set-Content -LiteralPath (Join-Path $pdest $f.Name) -NoNewline
                } else {
                    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $pdest $f.Name) -Force
                }
            }
            Write-Host "  plugin $($toc.BaseName)"
        }
    }
}

function Deploy-Probe {
    $dest = Join-Path $AddOnsPath "ChatProbe"
    Write-Host "Deploying ChatProbe -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Tools\ChatProbe") -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
        Write-Host "  $($_.Name)"
    }
}

if (-not $ProbeOnly) { Deploy-Addon }
if ($Probe -or $ProbeOnly) { Deploy-Probe }

Write-Host ""
Write-Host "Changed or new files: /reload is enough (measured on 70009). A brand-new addon folder needs a client restart." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /gchat help   (probe: /cprobe help)" -ForegroundColor Green
