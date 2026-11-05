# 설치 순서

M1 MacBook Pro 8GB, macOS 27에서 확인한 순서입니다. 관리자 권한(sudo)은 쓰지 않습니다.

## 0. 준비물
- Homebrew, Xcode 명령줄 도구, Rosetta 2
- VRC Pro 설치 파일 (`VirtualRCPro4.x.exe`, 공식 사이트에서 받기)

```bash
brew install winetricks innoextract
```

## 1. Wine 엔진 두 개 받기

| 엔진 | 용도 |
|---|---|
| Sikarugir **WineCX 24.0.7** (`WS12WineCX24.0.7_7.tar.xz`) | 게임 실행. CrossOver 24 소스 기반 |
| Gcenx **wine-staging 11.21** | 위 엔진에 없는 공용 dylib(freetype, gnutls, MoltenVK, GStreamer 등) 제공 |

Wine 11 계열(staging·devel)만으로는 이 게임의 설치 프로그램이 2GB 메모리 할당 오류로 꺼지고, 게임이 Direct3D 장치를 만들 때 충돌합니다. 그래서 게임은 CX24로 돌립니다.

```bash
mkdir -p ~/Applications/Wine/cx24
curl -LO https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz
shasum -a 256 WS12WineCX24.0.7_7.tar.xz   # 203f9e9f...fd1c 인지 확인
tar -xJf WS12WineCX24.0.7_7.tar.xz -C ~/Applications/Wine/cx24
xattr -dr com.apple.quarantine ~/Applications/Wine/cx24

curl -LO https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-staging-11.21-osx64.tar.xz
tar -xJf wine-staging-11.21-osx64.tar.xz -C ~/Applications/Wine
xattr -dr com.apple.quarantine ~/Applications/Wine/"Wine Staging.app"
```

CX24 엔진은 `bin/../../` 위치에서 dylib을 찾으므로, staging 앱의 라이브러리를 그 자리에 링크합니다. (환경 변수로 넘기면 winetricks처럼 `/usr/bin/env`를 거치는 도구에서 SIP가 지웁니다.)

```bash
G=~/Applications/Wine/"Wine Staging.app"/Contents/Resources/wine/lib
for f in "$G"/*.dylib "$G"/GStreamer.framework/Versions/1.0/lib/*.dylib; do
  [ -e ~/Applications/Wine/cx24/"$(basename "$f")" ] || ln -s "$f" ~/Applications/Wine/cx24/
done
```

## 2. 게임 환경(prefix) 만들기

```bash
source scripts/vrc-env.sh
wineboot -i && wineserver -w
winetricks -q vcrun2010 vcrun2013 d3dx9
```

Wine의 '문서' 폴더는 맥 `~/Documents`에 연결되어 있습니다. 게임 파일이 섞이지 않게 분리합니다.

```bash
for u in "$WINEPREFIX"/drive_c/users/*/; do [ -L "$u/Documents" ] && rm "$u/Documents" && mkdir "$u/Documents"; done
```

## 3. 게임 설치와 첫 업데이트

```bash
wine ~/Downloads/VirtualRCPro4.1.4424.exe    # 기본 경로 C:\Virtual RC Pro
cd "$VRC_DIR" && wine vrcpro.exe              # 업데이터: 첫 실행 때 약 2GB, 8천여 개 파일
```

한국에서는 업데이트 서버(네덜란드, 약 237ms)와 멀고 파일을 하나씩 받아서 약 160kB/s, 2시간 정도 걸립니다.

## 4. WMI 패치 적용
[`../wine-patches/README.md`](../wine-patches/README.md) 순서대로 32비트 `wbemprox.dll`을 빌드해서 넣습니다. 확인:

```bash
i686-w64-mingw32-gcc -mconsole -O1 -o wmitest.exe tools/wmitest.c -lole32 -loleaut32 -lwbemuuid -luuid
wine wmitest.exe   # NetworkAdapter rows=5, PnPDevice rows=5 처럼 0이 아니면 성공
```

## 5. 런처·HUD 빌드

```bash
./build.sh
```

## 6. 설정 바꾸기 (게임이 꺼진 상태에서)

```bash
source scripts/vrc-env.sh
K='HKCU\Software\Virtual Racing Industries\Virtual RC Racing Pro\Settings'
wine reg add "$K" /v Windowed /t REG_DWORD /d 1 /f
wine reg add "$K" /v ScreenWidthWindowed /t REG_DWORD /d 1280 /f
wine reg add "$K" /v ScreenHeightWindowed /t REG_DWORD /d 800 /f
wine reg add "$K" /v ShowFPS /t REG_DWORD /d 1 /f
```

해상도는 Wine이 알려 주는 표준 모드(`tools/modes.c`로 확인: 1280×800, 1440×900, 1680×1050 등) 중에서 고르세요. 비표준 크기가 저장되면 게임이 시작하자마자 꺼집니다.

## 7. 조종기 (Futaba T10PX)
- USB HID 조이스틱으로 인식됩니다(X=스티어링, Y=스로틀, 0~4096).
- 게임의 `calibrate` 버튼은 Windows 제어판을 여는데 Wine에서는 반응이 없습니다. 축 확인은 `wine control joy.cpl`로 합니다.
- 실제로 쓰는 범위가 절반 정도라, 송신기의 EPA(엔드 포인트)를 늘려서 맞춥니다. 스로틀 방향은 게임의 `reverse throttle`로 바꿉니다.
