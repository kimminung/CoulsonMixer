# 콜슨믹서 (ColsonMixer) 테크 PRD

- 작성일: 2026-10-13
- 상태: 설계 문서 단계 (구현 착수 전)
- 플랫폼: macOS (SwiftUI, 메뉴바 상주 앱)

## 1. 배경 및 문제 정의

macOS는 샌드박스/개인정보 보호 정책상 앱이 **다른 앱이나 시스템 전체가 재생 중인 내부 오디오를 임의로 녹음하는 것을 기본적으로 차단**한다. 그래서 BlackHole, Soundflower 같은 서드파티 도구들은 CoreAudio **HAL 플러그인(가상 오디오 드라이버)**을 `/Library/Audio/Plug-Ins/HAL`에 설치하고, 사용자가 시스템 출력 장치를 그 가상 장치로 수동 전환하게 하는 방식으로 우회해왔다.

이 방식은 동작은 하지만 마찰이 크다: 관리자 암호, `coreaudiod` 재시작 또는 재부팅, 서명/공증되지 않은 드라이버 설치 경고, macOS 업데이트마다 재승인 필요. 목표는 **이런 마찰 없이, 내 컴퓨터에서 재생 중인 소리를 캡처해 Safari로 실시간 웹방송처럼 들을 수 있는 나만의 경량 시스템, "콜슨믹서"**를 만드는 것이다.

## 2. 조사한 해결 방법 비교

| 방법 | 설치 마찰 | 포착 범위 | 채택 여부 |
|---|---|---|---|
| **A. Core Audio Process Tap** (`CATapDescription` + `AudioHardwareCreateProcessTap` + Aggregate Device, macOS 14.4+) | 없음 — 드라이버 설치·재부팅 불필요, 최초 1회 권한 승인만 | 지정한 프로세스(들) 또는 시스템 전체 출력 | **1차 채택** |
| B. ScreenCaptureKit (`SCStream`, `capturesAudio = true`) | 화면 기록 권한 필요 | 화면 공유 모델에 오디오가 포함된 형태라 오디오 전용 목적엔 다소 무거움 | 보조 대안으로만 기록 |
| C. 전통적 Audio Server Plug-in (HAL 드라이버, BlackHole 방식) | 큼 — 서명/공증, 설치 패키지, 관리자 권한, 재부팅 | 시스템 알림음 등 모든 오디오 포함, macOS 전 버전 호환 | **Phase 2 폴백(향후 과제)** |

> 근거: Apple 공식 문서 "Capturing system audio with Core Audio taps"에 따르면 `CATapDescription`을 `AudioHardwareCreateProcessTap(_:_:)`에 전달해 탭을 만들고, `AudioHardwareCreateAggregateDevice(_:_:)`로 애그리게이트 장치를 구성해 그 탭을 소스로 오디오를 수신한다. 드라이버 번들 설치나 재부팅 단계가 없다.

### 왜 A를 1차로 채택했는가
- 사용자가 겪는 "내부 소리 녹음이 막혀 있다"는 문제의 본질은 *권한*이지 *하드웨어 경로 부재*가 아니다. Process Tap API는 Apple이 바로 이 시나리오를 위해 제공하는 공식 경로다.
- 설치가 가역적이다(앱 삭제 = 흔적 없이 제거). 기존 출력 장치를 바꾸지 않아 사용자의 기존 오디오 경험을 방해하지 않는다.
- BlackHole 방식(C)은 시스템 알림음까지 전부 잡아야 하는 경우에 더 유리하지만, 이는 Phase 2 과제로 남긴다.

![가상 오디오 드라이버 방식 vs 콜슨믹서 방식](images/comparison.svg)

## 3. 채택 아키텍처

내부 오디오(캡처) → 인코딩 → 로컬 HTTP 방송 서버 → Safari `<audio>` 재생, 네 단계로 구성된 파이프라인이다.

![콜슨믹서 아키텍처](images/architecture.svg)

### 3.1 AudioCaptureEngine
- `CATapDescription`으로 탭 대상(특정 프로세스 배열 또는 시스템 전체), 모노/스테레오 믹스다운, 뮤트 동작을 구성한다.
- `AudioHardwareCreateProcessTap(_:_:)`으로 탭을 만들고, `AudioHardwareCreateAggregateDevice(_:_:)`로 그 탭을 포함하는 애그리게이트 장치를 구성한다.
- 애그리게이트 장치에 `AudioDeviceIOProc`을 등록해 PCM 버퍼를 실시간으로 수신한다.
- 캡처 대상 앱 목록은 `NSRunningApplication` 기반으로 UI에 노출한다.

### 3.2 AudioEncoder
- 수신한 Linear PCM 버퍼를 `AVAudioConverter`로 AAC(기본) 또는 MP3로 실시간 인코딩한다.
- 소스가 일시적으로 끊기면(캡처 대상 앱 종료 등) 무음 프레임으로 패딩해 스트림 연속성을 유지한다.

### 3.3 BroadcastServer
- `Network` 프레임워크의 `NWListener`로 로컬 전용(기본값: loopback, 옵션으로 사설망 인터페이스) HTTP 서버를 띄운다.
- `GET /stream.aac`에 대해 `Transfer-Encoding: chunked`로 응답하며, 연결이 유지되는 동안 인코딩된 오디오 프레임을 지속적으로 흘려보낸다(Shoutcast/Icecast와 동일한 발상). 여러 클라이언트(여러 Safari 탭/기기)가 동시에 접속하면 인코더 출력을 각 연결에 팬아웃한다.
- `GET /`에는 `<audio controls autoplay src="/stream.aac">`를 담은 최소 플레이어 페이지를 서빙한다.

### 3.4 Safari
- 별도 플러그인·확장 없이 표준 `<audio>` 태그의 진행형(progressive) 스트리밍 재생만으로 동작한다. 인터넷 라디오 사이트들이 쓰는 것과 같은 기법이라 Safari 호환성 리스크가 낮다.

### 3.5 시퀀스
![송출 시작 시퀀스](images/dataflow.svg)

## 4. 컴포넌트 구조

```
ColsonMixer (Xcode 프로젝트)
├── ColsonMixerKit (Swift Package, 로직 전담)
│   ├── AudioCaptureEngine   — CATapDescription / 애그리게이트 장치 / IOProc
│   ├── AudioEncoder         — PCM → AAC 실시간 인코딩
│   ├── BroadcastServer      — NWListener 기반 HTTP 청크 스트리밍
│   └── MixerModel           — 소스 선택, 볼륨/뮤트, 송출 상태(@Observable)
└── ColsonMixer (App, SwiftUI)
    ├── MenuBarExtra         — 메뉴바 상주, 송출 On/Off 토글
    └── MixerWindow          — 소스 선택 목록, 레벨 미터, URL 표시/복사, "Safari에서 열기"
```

## 5. 권한 및 보안 고려사항

- **시스템 오디오 캡처 권한 (확정)**: Apple 공식 샘플 문서("Capturing system audio with Core Audio taps")로 재검증 완료 — `Info.plist`에 `NSAudioCaptureUsageDescription` 키와 안내 문구가 반드시 있어야 하며, 없으면 탭 생성 시도 시 시스템이 앱을 강제 종료한다. 이 키가 있으면 애그리게이트 장치에서 최초로 IO를 시작할 때 macOS가 시스템 오디오 녹음 권한 프롬프트를 자동으로 띄운다. 구현에 반영 완료.
- **네트워크 노출 범위**: `BroadcastServer`는 `127.0.0.1`에만 바인딩한다(구현 완료). 같은 네트워크의 다른 기기에서 듣는 "사설망 공개" 옵션은 Phase 2 과제로 보류했다. 외부 인터넷 노출은 지원하지 않는다.
- **샌드박스 호환성 (결정 완료)**: 기본 Xcode 템플릿은 `ENABLE_APP_SANDBOX = YES`였다. Core Audio Process Tap의 샌드박스 호환 여부에 대한 공식 보증을 찾지 못해, MVP는 **App Sandbox를 비활성화**하기로 결정했다(리스크 회피). 샌드박스 상태에서의 동작은 실기 미검증이며, 배포 전 재검토 과제로 남긴다(App Sandbox 캡슐화 시 `com.apple.security.device.audio-input` 엔타이틀먼트 추가가 필요할 수 있음).
- **동의 없는 녹음 방지**: 콜슨믹서는 "내 컴퓨터의 소리를 내 Safari로 보내는" 로컬 전용 도구이며 녹음 파일을 디스크에 저장하거나 외부로 전송하지 않는다(저장 기능은 범위 밖, 구현에서도 디스크 쓰기 없음).

## 6. 비기능 요구사항

| 항목 | 목표 |
|---|---|
| 종단 간 지연시간 | 1~3초 이내 (HTTP 청크 버퍼링 특성상 불가피한 지연 허용) |
| 안정성 | 소스 앱 종료/전환 중에도 스트림 비연결 없이 유지 |
| 유휴 리소스 사용량 | CPU 5% 미만 (송출 비활성 상태) |
| 동시 접속 | 로컬 네트워크 내 다중 클라이언트(수 대) 동시 수신 |

## 7. MVP 범위

**포함**
- 실행 중인 앱 1개 또는 시스템 전체를 캡처 대상으로 선택
- AAC 인코딩 + 로컬 HTTP 청크 스트리밍
- Safari에서 재생 가능한 플레이어 페이지 + "Safari에서 열기" 버튼
- 메뉴바 상주, 송출 On/Off, 로컬 URL 복사

**제외 (Phase 2 이후)**
- HAL 드라이버(BlackHole 스타일) 폴백 경로
- 다중 소스 동시 믹싱
- ICY 메타데이터(지금 재생 중 트랙 정보)
- WebRTC 등 저지연 스트리밍 프로토콜
- iOS 동반 앱

## 8. 향후 과제 (Phase 2+)

1. 구버전 macOS·시스템 알림음까지 필요한 경우를 위한 전통적 Audio Server Plug-in 폴백
2. 저지연이 중요한 경우를 위한 WebRTC 경로 검토
3. ICY 스타일 메타데이터로 "지금 송출 중인 앱/트랙" 표시
4. 여러 앱을 동시에 믹싱해 하나의 스트림으로 합성
