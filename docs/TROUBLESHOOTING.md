# 문제 해결 기록

실제로 겪은 순서대로 적었습니다. 증상, 로그에 찍힌 것, 원인, 조치 순서입니다.

## 설치 프로그램이 창을 띄우기 전에 꺼짐
- 로그: `err:virtual:allocate_virtual_memory out of memory for allocation, base 0x0 size 82001000`, `virtual_setup_exception stack overflow`
- 원인: Wine 11(staging, devel 모두)의 32비트 처리와 Inno Setup 5.5가 맞지 않음. 다른 32비트 프로그램은 정상
- 조치: CrossOver 소스 기반 엔진(CX24)으로 바꾸니 정상 설치

## Start VRC 직후 "Application has encountered problem" 후 종료 (Wine 11)
- 로그: `EXCEPTION_ACCESS_VIOLATION` at `0x7BF41239`, `Exception frame is not in stack limits`
- 원인: Wine 11 계열에서 게임이 Direct3D 장치를 만들 때 충돌. `csmt`, `VideoMemorySize`로는 해결 안 됨
- 조치: CX24 엔진

## 실행기(.NET)가 글꼴 오류로 꺼짐
- 로그: `System.ArgumentException: The requested FontFamily could not be found`, `failed to load libgnutls`
- 원인: `caffeinate wine ...`처럼 `/usr/bin` 도구로 감싸면 SIP가 `DYLD_FALLBACK_LIBRARY_PATH`를 지움
- 조치: wine을 직접 실행. 잠자기 방지는 별도 프로세스나 IOKit 전원 관리로 처리(런처가 이렇게 함)

## 실행기가 파일 검사 중 NullReferenceException
- 원인: 새 환경에서 업데이터가 8천여 개 파일을 여러 스레드로 검사하다 Dictionary 경합
- 조치: 기존 환경의 `AppData/Local/Virtual RC Pro/Updater/config.dat`를 복사해서 전체 검사를 건너뜀

## 로그인 직전 기기 식별 실패
- 게임 디버그 메시지: `Failed to prepare MAC address`, `Failed to prepare harddrive ID`, `Query failed. Error 0x80041017`
- 원인과 조치: `wine-patches/README.md` 참고

## 로그인 후 게임이 바로 꺼짐
- 원인: **로그인 화면의 `Abort` 버튼(또는 Enter)이 게임 종료**. 처음 화면은 새 계정 등록(Register user) 탭
- 조치: 왼쪽 `accounts` 메뉴에서 기존 계정으로 로그인

## 입력창이 먹통, 키보드 배열 전환 실패
- 로그: `NtUserActivateKeyboardLayout Changing user locale is not supported` (layout `0xe0000412`)
- 원인: 맥 입력 소스가 한국어일 때 Wine이 한국어 배열로 바꾸려 하지만, 사용자 로캘(en_US)과 언어가 달라 실패
- 조치: 실행 전에 입력 소스를 ABC로. 런처가 자동으로 함

## 해상도를 바꾸면 멈추거나 꺼짐
- 로그: `wined3d_swapchain_resize_buffers Something's still holding back buffer 0`
- 조치: 게임이 꺼진 상태에서 레지스트리로 표준 해상도 지정. 전체 화면(1680×1050)도 교착 상태로 멈춰서 창 모드 사용

## 로딩이 몇 분씩 걸림 (측정)
`scripts/thread-sampler.sh`로 로딩 중 20초마다 스레드별 CPU를 기록한 결과:

| 항목 | 값 |
|---|---|
| 로딩 중 일한 스레드 | 1개 (게임 메인 스레드 "Main loop"), 약 100% = 코어 1개 |
| 나머지 약 20개 스레드 | 거의 0% |
| 메인 스레드 시간 중 Rosetta JIT | 약 2/3 |
| 공유 자원 대기 (`RtlpWaitForCriticalSection ... blocked by <메인 스레드>`) | 1분 단위로 13~15번 |

해 본 것:
- 배경음악 모듈(`winegstreamer`) 끄기: 효과 없음
- `csmt` 끄기/켜기: 뚜렷한 차이 없음
- Vulkan 렌더러(`renderer=vulkan`, MoltenVK): `VK_ERROR_FEATURE_NOT_PRESENT`, `vkCreateBufferView` 실패로 사용 불가
- 그래픽 옵션 낮추기, 다른 앱 닫기(메모리 확보): 체감상 약간 나아짐

결론: 병목은 메인 스레드 하나가 Rosetta 번역을 거쳐 실행되는 것. ARM64 네이티브 Wine(FEX 사용)이 나오면 다시 시험할 가치가 있음.
