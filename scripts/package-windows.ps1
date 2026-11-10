[CmdletBinding()]
param([string] $OutputDirectory = '')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'artifacts' }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $repoRoot $OutputDirectory }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)(?:\+[0-9A-Za-z.-]+)?\s*$') {
    throw 'pubspec.yaml must contain a semantic application version.'
}
$version = $Matches[1]
$releaseRoot = Join-Path $repoRoot 'build/windows/x64/runner/Release'
foreach ($required in @('Dix.exe', 'flutter_windows.dll', 'data/app.so', 'core/DixCore.exe', 'core/wintun.dll', 'core/GeoSite.dat', 'core/geoip.metadb')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $required) -PathType Leaf)) { throw "Missing Windows runtime file: $required" }
}
foreach ($required in @('LICENSE', 'THIRD_PARTY_NOTICES.md', 'core/LICENSE', 'core/Clash.Meta/LICENSE')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $required) -PathType Leaf)) { throw "Missing redistribution notice: $required" }
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$stage = Join-Path $OutputDirectory ('staging-' + [Guid]::NewGuid().ToString('N'))
$bundle = Join-Path $stage 'Dix'
New-Item -ItemType Directory -Path $bundle | Out-Null
Get-ChildItem -LiteralPath $releaseRoot -Force | Copy-Item -Destination $bundle -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $repoRoot 'licenses') -Destination $bundle -Recurse -Force
$licenses = Join-Path $bundle 'licenses'
New-Item -ItemType Directory -Force -Path $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'core/LICENSE') -Destination (Join-Path $licenses 'DixCore-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $repoRoot 'core/Clash.Meta/LICENSE') -Destination (Join-Path $licenses 'Mihomo-LICENSE.txt')
@"
Dix $version for Windows x64

Extract this entire archive and run Dix.exe. Keep the core and data folders.
TUN mode requires administrator rights; system proxy mode does not.
Source: https://github.com/boutlyfe/dix-client
License and third-party notices are included alongside this file.
"@ | Set-Content -LiteralPath (Join-Path $bundle 'README.txt') -Encoding utf8NoBOM
$zip = Join-Path $OutputDirectory "Dix-Windows-$version.zip"
Compress-Archive -LiteralPath $bundle -DestinationPath $zip -CompressionLevel Optimal -Force
$digest = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS') -Encoding ascii
Write-Host "Packaged $zip"
