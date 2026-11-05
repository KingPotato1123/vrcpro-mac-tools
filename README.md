# vrcpro-mac-tools

Apple Silicon 맥에서 무료 Wine으로 **VRC Pro**(Windows 전용 RC 레이싱 시뮬레이터)를 실행하면서 만든 도구와 기록입니다. M1 MacBook Pro 8GB, macOS 27에서 로그인, 온라인 접속, 싱글 주행, Futaba T10PX 조종기 입력까지 확인했습니다.

> Virtual Racing Industries와 관계없는 개인 프로젝트입니다. 게임 파일·에셋은 들어 있지 않고, 게임 실행 파일을 고치지도 않습니다. 게임은 공식 사이트에서 직접 받아야 합니다.

## 들어 있는 것

| 폴더 | 내용 |
|---|---|
| `launcher/` | **VRCPro.app**. 더블클릭 한 번으로 입력 소스를 ABC로 바꾸고, HUD를 띄우고, 잠자기를 막은 채 게임을 실행합니다. 게임을 끄면 입력 소스와 잠자기 설정을 원래대로 돌려놓습니다 |
| `hud/` | **VRC HUD.app**. 화면 오른쪽 위에 CPU·GPU·메모리·스왑, 게임 프로세스 CPU, 조종기 입력 Hz와 축 값을 보여 주는 오버레이. 시스템 라이트/다크 모드를 따릅니다 |
| `wine-patches/` | WMI(`wbemprox`) 패치. Wine에서 비어 있던 하드웨어 정보를 Windows처럼 채웁니다 |
| `scripts/` | Wine 환경 변수(`vrc-env.sh`), 스레드별 CPU 기록 도구(`thread-sampler.sh`) |
| `tools/` | 원인을 찾을 때 쓴 32비트 테스트 프로그램(WMI 쿼리, 키보드 배열, 화면 모드, Vulkan) |
| `docs/` | 설치 순서와 문제 해결 기록 |

## 빠른 시작

1. [`docs/SETUP.md`](docs/SETUP.md) 순서대로 Wine 엔진과 게임을 설치합니다.
2. 앱을 빌드합니다.
   ```bash
   ./build.sh
   ```
3. `~/Applications/VRCPro.app`을 실행합니다.

## 꼭 알아야 할 것

- **로그인 화면의 `Abort`는 게임 종료 버튼입니다.** 기존 계정은 왼쪽 `accounts` 메뉴에서 로그인하세요.
- **해상도와 창 크기는 게임 안에서 바꾸지 마세요.** Wine에서 화면 버퍼를 다시 만들다 멈추거나 꺼집니다. 게임이 꺼진 상태에서 레지스트리로 바꾸세요(SETUP.md 참고).
- **한국어 입력기 상태로 실행하지 마세요.** Wine 9은 사용자 로캘과 언어가 다른 키보드 배열로 전환하지 못합니다. 런처가 ABC로 자동 전환합니다.
- **`nohup`, `caffeinate`, `timeout`으로 wine을 감싸지 마세요.** macOS SIP가 `DYLD_*` 변수를 지워서 글꼴·암호화 라이브러리를 못 불러옵니다.

## 성능에 대해

로딩이 느립니다(트랙·차 변경에 몇 분). 측정해 보면 로딩 중 일하는 스레드는 게임 메인 스레드 하나이고, 그 시간의 약 2/3를 Rosetta가 x86 코드를 실시간 번역(JIT)하는 데 씁니다. Wine의 Vulkan 경로는 MoltenVK에 없는 기능이 필요해서 쓸 수 없었습니다. 자세한 측정은 [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)에 있습니다.

## 라이선스

- 이 저장소의 코드: MIT ([LICENSE](LICENSE))
- `wine-patches/`: LGPL-2.1-or-later (Wine과 동일)
