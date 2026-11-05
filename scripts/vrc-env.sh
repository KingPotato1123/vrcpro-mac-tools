# VRC Pro용 Wine 환경 변수. 터미널에서 `source scripts/vrc-env.sh` 후 wine 명령을 쓰면 된다.
# 경로는 docs/SETUP.md의 기본 배치를 따른다. 다르게 설치했다면 아래 세 줄만 고치면 된다.
WINE_ENGINE="${WINE_ENGINE:-$HOME/Applications/Wine/cx24/wswine.bundle}"   # Sikarugir WineCX 24.0.7
WINE_LIBDIR="${WINE_LIBDIR:-$HOME/Applications/Wine/cx24}"                  # 엔진이 찾는 dylib 위치
export WINEPREFIX="${WINEPREFIX:-$HOME/Games/VRCPro-cx24}"

export PATH="$WINE_ENGINE/bin:$PATH"
export WINE="$WINE_ENGINE/bin/wine"
export WINESERVER="$WINE_ENGINE/bin/wineserver"
# 주의: nohup, caffeinate, timeout 같은 /usr/bin 도구로 wine을 감싸면 SIP가 DYLD_* 변수를 지운다.
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_LIBDIR:/usr/lib"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export WINEDEBUG="${WINEDEBUG:--all}"

VRC_DIR="$WINEPREFIX/drive_c/Virtual RC Pro"
