#!/usr/bin/env bash
# Builds the pureglass tweak and injects it into an IPA.
#
#   scripts/pipeline.sh <ipa> [-o out.ipa] [--install]   (or: make release / make install)
#
# The IPA is yours to supply: drop it in ipa/ and the Makefile finds it. It can be a plain decrypted Spotify
# IPA or one that already has other tweaks injected; pureglass.dylib is added beside them and nothing of
# theirs is touched.
#
# Needs: Theos in $THEOS (default ~/theos), an iPhoneOS 26+ SDK from the selected Xcode or in $THEOS/sdks,
# gmake, ldid, dpkg-deb (brew) and cyan (uv tool install "cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw").
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
mkdir -p "$ROOT/out"

IN="" OUT="" INSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
[ -n "$IN" ] || { echo "no IPA: put one in ipa/, or pass one (make release IPA=path.ipa)" >&2; exit 1; }
[ -f "$IN" ] || { echo "no such file: $IN" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing $1 -> $2" >&2; exit 1; }; }
need gmake "brew install make"
need ldid "brew install ldid"
need dpkg-deb "brew install dpkg"
need cyan "uv tool install 'cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw'"
{ ls -d "$THEOS"/sdks/iPhoneOS*.sdk "$(xcode-select -p 2>/dev/null)"/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk 2>/dev/null || true; } \
  | grep -qE 'iPhoneOS(2[6-9]|[3-9][0-9])\.' \
  || { echo "no iPhoneOS 26+ SDK: xcode-select an Xcode 26 or newer, or put the SDK in $THEOS/sdks" >&2; exit 1; }

VERSION="$(cat "$ROOT/version.txt" 2>/dev/null || true)"
: "${VERSION:=0.0.0}"
OUT="${OUT:-$ROOT/out/pureglass-$VERSION.ipa}"
echo "==> pureglass $VERSION -> $OUT"

echo "==> building tweak"
export THEOS
# Theos resolves its toolchain through `xcrun -sdk iphoneos`, which needs full Xcode. With only the
# Command Line Tools installed, name the tools directly instead.
if ! xcrun -sdk iphoneos --find clang >/dev/null 2>&1; then
  export TARGET_CC=clang TARGET_CXX=clang++ TARGET_LD=clang++ \
         TARGET_STRIP=strip TARGET_LIPO=lipo TARGET_CODESIGN_ALLOCATE=codesign_allocate TARGET_LIBTOOL=libtool
fi
# Theos builds its Swift support tools only at MAKELEVEL 0, and `make release` hands this script MAKELEVEL 1.
env -u MAKELEVEL gmake -C "$ROOT/tweak" clean package >/dev/null
TWEAK_DEB="$(ls -t "$ROOT"/tweak/packages/*.deb | head -1)"
echo "    $TWEAK_DEB"

echo "==> injecting"
# -w drops the Watch app: its companion-app key would still name com.spotify.client and block the install.
cyan -i "$IN" -o "$OUT" -f "$TWEAK_DEB" -w -s --overwrite

echo "==> done: $OUT"
[ "$INSTALL" = 1 ] && exec "$ROOT/scripts/install.sh" "$OUT"
exit 0
