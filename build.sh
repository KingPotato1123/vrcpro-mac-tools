#!/bin/zsh
# VRC HUD.app, VRCPro.app을 빌드해서 ~/Applications 에 넣는다. (Xcode 명령줄 도구 필요)
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-$HOME/Applications}"
mkdir -p build "$DEST"

bundle() {  # $1 앱 이름, $2 실행 파일 이름, $3 소스 폴더, $4.. 프레임워크
    local app="$DEST/$1.app" exe="$2" src="$3"; shift 3
    local fw=(); for f in "$@"; do fw+=(-framework "$f"); done
    swiftc -O "$src/main.swift" -o "build/$exe" "${fw[@]}"
    mkdir -p "$app/Contents/MacOS"
    cp "build/$exe" "$app/Contents/MacOS/$exe"
    cp "$src/Info.plist" "$app/Contents/Info.plist"
    codesign -s - --force "$app" >/dev/null
    echo "built $app"
}

bundle "VRC HUD" vrc-hud hud Cocoa IOKit
bundle "VRCPro" VRCPro launcher Cocoa Carbon IOKit
