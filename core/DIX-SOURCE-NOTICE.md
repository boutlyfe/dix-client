# DixCore source

This directory contains the corresponding source snapshot used to build DixCore.

The RPC wrapper comes from the local FlClashZ checkout:
https://github.com/f4ckthislife/FlClashZ
Its main branch reference was d9907eb5afbd29946e9929f4de4ded6bcc547c75.

The `Clash.Meta` dependency comes from the local xHomo checkout:
https://github.com/pluralplay/xHomo
Its checked-out HEAD was b64d7d11580154979aec38b17fd1475393c4135f.
Local source changes may already have existed in both checkouts. The copied
files, rather than those commit identifiers alone, define this source snapshot.

The original GPL version 3 license texts are preserved in `LICENSE` and
`Clash.Meta/LICENSE`. Existing copyright and attribution notices are preserved.
The only branding change in this snapshot is `constant.MihomoName` from
`FlClashX` to `Dix`. Compiler paths are removed using Go's `-trimpath` option.

Build from this directory with Go 1.26.1, using PowerShell:

```powershell
$env:CGO_ENABLED = '0'
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'
$env:GOAMD64 = 'v1'
go build -mod=readonly -trimpath -buildvcs=false -ldflags '-s -w -buildid=' -o ../windows/core/DixCore.exe .
```

Pinned module requirements and checksums are present in `go.mod` and `go.sum`.
Use the same compiler version, source snapshot, module files, environment and
build flags when comparing reproducible build hashes.
