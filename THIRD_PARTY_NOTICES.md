# Third-party notices

Dix is distributed under GNU GPL version 3. The root LICENSE applies to the
application and its GPL components; separately licensed data, fonts, SDKs and
libraries retain their own terms. Existing copyright notices are retained.

## DixCore
The RPC wrapper is derived from [FlClashZ](https://github.com/f4ckthislife/FlClashZ),
with the [xHomo/Mihomo](https://github.com/pluralplay/xHomo) engine snapshot.
Corresponding source is included in `core/`, including both original GPLv3
licenses. See `core/DIX-SOURCE-NOTICE.md` for provenance and build flags.
Go module dependencies and checksums are recorded in both go.mod/go.sum files;
each dependency retains its upstream license.

## Wintun 0.14.1
Copyright 2018–2021 WireGuard LLC. The unmodified signed AMD64 DLL is from the
official [Wintun 0.14.1 archive](https://www.wintun.net/builds/wintun-0.14.1.zip).
Archive SHA-256: 07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51.
Its Prebuilt Binaries License is included at `licenses/Wintun-Prebuilt-LICENSE.txt`.
This separate license applies to the signed DLL; it is not relicensed as GPLv3.

## Geographic routing data
GeoSite.dat and geoip.metadb are routing datasets for the engine. The upstream
source configured by the engine is [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat).
The bundled snapshots originate from the previously installed client; exact
upstream build provenance for those snapshots is not asserted. Domain names
inside routing data are third-party data, not Dix branding.

## Flutter and interface assets
Flutter and Dart: BSD-style licenses, https://github.com/flutter/flutter and
https://github.com/dart-lang/sdk. Dependency versions are locked in pubspec.lock;
Flutter's built-in license registry includes package notices.
Inter font: SIL Open Font License, included at `assets/fonts/OFL.txt`.
Cobe land mask: MIT, included at `assets/LAND_MASK_LICENSE.md`.
Dix icon: provided by the project owner.
