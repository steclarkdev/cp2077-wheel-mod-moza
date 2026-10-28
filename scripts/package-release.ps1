# Package a release ZIP that extracts directly into the Cyberpunk 2077 folder.
#
# Usage:
#   pwsh scripts/package-release.ps1 -Dll build/direct_wheel/Release/direct_wheel.dll `
#        -Version 3.3.1 [-Commit abc1234] [-OutDir dist]
#
# Output (deterministic: sorted entries, fixed timestamps):
#   dist/direct_wheel-<Version>[+<Commit>].zip
#   dist/direct_wheel_flight_bridge-<Version>[+<Commit>].zip   (optional addon)
#   dist/SHA256SUMS.txt

param(
  [Parameter(Mandatory)][string]$Dll,
  [string]$Version,
  [string]$Commit,
  [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not $Version) { $Version = (Get-Content -Raw "mod_info.json" | ConvertFrom-Json).version }
$Version = $Version -replace '^v', ''
$suffix = if ($Commit) { "$Version+$Commit" } else { $Version }

if (-not (Test-Path $Dll)) { throw "DLL not found: $Dll" }

$flightBridge = "direct_wheel_flight_bridge.reds"
$redsFiles = Get-ChildItem "direct_wheel_reds" -Filter *.reds -File |
  Where-Object { $_.Name -ne $flightBridge } | Sort-Object Name

# zip entry path -> source file
function New-Zip([string]$ZipPath, [System.Collections.Specialized.OrderedDictionary]$Entries) {
  if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
  $fixedTime = [DateTimeOffset]::new(2020, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
  $zip = [System.IO.Compression.ZipFile]::Open([IO.Path]::GetFullPath($ZipPath, (Get-Location).Path), 'Create')
  try {
    foreach ($name in ($Entries.Keys | Sort-Object { $_ }  -CaseSensitive)) {
      $entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = $fixedTime
      $in = [System.IO.File]::OpenRead((Resolve-Path $Entries[$name]).Path)
      $out = $entry.Open()
      try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
    }
  } finally { $zip.Dispose() }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$main = [ordered]@{}
$main["red4ext/plugins/direct_wheel/direct_wheel.dll"] = $Dll
foreach ($r in $redsFiles) { $main["r6/scripts/direct_wheel/$($r.Name)"] = $r.FullName }
foreach ($d in "README.md", "CHANGELOG.md", "LICENSE") { $main["red4ext/plugins/direct_wheel/$d"] = $d }

$mainZip = Join-Path $OutDir "direct_wheel-$suffix.zip"
New-Zip $mainZip $main
Write-Host "Created $mainZip"

$bridgePath = Join-Path "direct_wheel_reds" $flightBridge
if (Test-Path $bridgePath) {
  $bridge = [ordered]@{ "r6/scripts/direct_wheel/$flightBridge" = $bridgePath }
  $bridgeZip = Join-Path $OutDir "direct_wheel_flight_bridge-$suffix.zip"
  New-Zip $bridgeZip $bridge
  Write-Host "Created $bridgeZip"
}

$sums = Get-ChildItem $OutDir -Filter *.zip | Sort-Object Name | ForEach-Object {
  "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
}
$sums | Set-Content -Encoding ascii (Join-Path $OutDir "SHA256SUMS.txt")
$sums | ForEach-Object { Write-Host $_ }
