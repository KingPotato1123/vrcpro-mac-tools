# Wine 패치: wbemprox (WMI)

`0001-wbemprox-vrcpro-hardware-id.patch`는 Wine 9.0의 `dlls/wbemprox`를 고쳐서, Windows 프로그램이 WMI로 하드웨어 정보를 읽을 때 Windows와 같은 결과를 받게 합니다. VRC Pro는 로그인할 때 이 정보로 기기 식별값을 만드는데, 원래 Wine에서는 값이 비어서 만들 수 없었어요.

라이선스: Wine과 같은 **LGPL-2.1-or-later**.

## 바뀌는 것

| 문제 (Wine 9.0 원본) | 수정 |
|---|---|
| `Win32_NetworkAdapter.NetConnectionID`가 항상 NULL. `WHERE NetConnectionID LIKE "%"`가 0행 | 물리 어댑터 중 macOS 하드웨어 포트(`en*`)에 이름을 채움. `awdl0`·`llw0`·`ap1`·`nan0`처럼 MAC이 자주 바뀌는 가상 장치는 제외 |
| `Win32_PnPDevice` 클래스가 없음 | 각 `Win32_DiskDrive`를 같은 PNPDeviceID의 `Win32_PnPEntity`와 잇는 연관 클래스를 추가 |
| 속성 이름이 `DeviceId` | Windows 표기 `DeviceID`로 통일. 이름 조회는 원래 대소문자를 구분하지 않지만, `__PATH` 문자열에서 `DeviceID="`를 대소문자 구분으로 찾는 프로그램이 있음 |
| WQL 문자열 리터럴의 백슬래시 이스케이프를 풀지 않음 (`"IDE\\Disk"`가 그대로 비교됨) | Windows처럼 `\\` → `\`, `\"` → `"` 로 해석. 내부에서 만드는 `ASSOCIATORS OF` 쿼리도 경로를 이스케이프하도록 맞춤 |
| `Win32_DiskDrive.Caption` 없음 | `Model`과 같은 값으로 추가 |

## 빌드 (32비트 DLL만, M1 기준 약 20초)

```bash
brew install mingw-w64 bison flex
curl -LO https://dl.winehq.org/wine/source/9.0/wine-9.0.tar.xz
tar xf wine-9.0.tar.xz && cd wine-9.0 && git init -q . && git apply ../0001-wbemprox-vrcpro-hardware-id.patch && cd ..
mkdir build && cd build
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
arch -x86_64 ../wine-9.0/configure CC="clang -arch x86_64" --enable-archs=i386,x86_64 --without-x --without-freetype --without-gnutls
arch -x86_64 make -j4 dlls/wbemprox/i386-windows/wbemprox.dll
```

만든 `wbemprox.dll`을 엔진의 `lib/wine/i386-windows/`에 넣습니다. 원본은 `.orig`로 백업해 두세요.

```bash
E=~/Applications/Wine/cx24/wswine.bundle/lib/wine/i386-windows
cp -p "$E/wbemprox.dll" "$E/wbemprox.dll.orig"
cp dlls/wbemprox/i386-windows/wbemprox.dll "$E/"
```

확인은 `tools/wmitest.c`로 합니다(`../docs/SETUP.md` 참고).

## 알려진 한계
- 디스크 일련번호는 Wine 기본값(`WINEHDISK`)이고, 디스크 5개가 모두 같은 PNPDeviceID를 가집니다.
- `IOCTL_SMART`/`IOCTL_STORAGE_QUERY_PROPERTY`로 직접 디스크를 읽는 방식(IDE/SCSI identify)은 여전히 실패합니다. VRC Pro는 이 경우 WMI 경로로 넘어갑니다.
- CrossOver 24 기반 엔진에 업스트림 9.0으로 빌드한 DLL을 넣어 시험했습니다. 다른 Wine 버전에서는 다시 빌드해야 합니다.
