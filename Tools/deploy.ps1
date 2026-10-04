<#
    deploy.ps1 - Copy GlassChat (and optionally ChatProbe) into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

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

function Deploy-Addon {
    $dest = Join-Path $AddOnsPath "GlassChat"
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

    $media = Join-Path $dest "Media"
    New-Item -ItemType Directory -Force -Path $media | Out-Null
    $tex = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Media") -File | Where-Object { $_.Extension -eq ".tga" }
    foreach ($t in $tex) { Copy-Item -LiteralPath $t.FullName -Destination (Join-Path $media $t.Name) -Force }
    Write-Host "  Media\  ($($tex.Count) files)"

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
