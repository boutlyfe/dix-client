[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$coreRoot = Join-Path $repoRoot 'core'
$output = Join-Path $repoRoot 'windows/core/DixCore.exe'
if (-not (Test-Path -LiteralPath (Join-Path $coreRoot 'Clash.Meta/go.mod'))) {
    throw 'Missing core/Clash.Meta sources. Use a complete source checkout.'
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
$names = @('CGO_ENABLED', 'GOOS', 'GOARCH', 'GOAMD64')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
Push-Location $coreRoot
try {
    $env:CGO_ENABLED = '0'
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    $env:GOAMD64 = 'v1'
    & go build -trimpath -buildvcs=false -ldflags '-s -w -buildid=' -o $output .
    if ($LASTEXITCODE -ne 0) { throw "Core build failed ($LASTEXITCODE)" }
    Write-Host "Built $output"
} finally {
    Pop-Location
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
