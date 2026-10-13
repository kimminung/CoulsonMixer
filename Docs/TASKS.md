# 콜슨믹서 (ColsonMixer) 태스크 문서

관련 설계 문서: [PRD.md](./PRD.md)

> 2026-10-13: Phase 0~4 MVP 구현 완료(코드는 `CoulsonMixer/CoulsonMixer/Capture/`), macOS·iOS 시뮬레이터 빌드 통과, 앱 정상 기동 확인. Core Audio 권한 승인 플로우·실제 Safari 재생은 사람이 직접 권한 프롬프트를 승인해야 해서 미검증 — Phase 6 QA에서 실기 확인 필요.

## Phase 0 — 프로젝트 셋업
- [x] T0.1 Xcode 앱 타깃을 "CoulsonMixer"로 구성 (멀티플랫폼 템플릿에서 macOS 경로만 구현, `#if os(macOS)`로 iOS/visionOS 분리)
- [x] T0.2 ~~`ColsonMixerKit` 별도 Swift Package~~ → MVP에서는 앱 타깃 내 `Capture/` 그룹으로 단순화 (패키지 분리는 보류)
- [x] T0.3 `NSAudioCaptureUsageDescription` Info.plist 키 추가 확인·적용 (Apple 문서로 재검증 완료: 최초 탭 생성 시 시스템이 권한 프롬프트를 띄움)

## Phase 1 — 오디오 캡처 코어 (스파이크 우선)
- [x] T1.1 **스파이크 결론**: 기본 템플릿이 `ENABLE_APP_SANDBOX = YES`였음을 발견 → MVP는 **샌드박스 비활성화**로 결정(관련 레퍼런스가 샌드박스 환경에서의 동작을 보장하지 않아 리스크 회피). 실제 사용자 환경에서 샌드박스 On 상태의 동작 여부는 미검증 — 재활성화 시 가장 먼저 재검증할 것
- [x] T1.2 `CATapDescription` 구성 (`stereoMixdownOfProcesses`/`stereoGlobalTapButExcludeProcesses`) — `AudioCaptureEngine.swift`
- [x] T1.3 `AudioHardwareCreateAggregateDevice`로 탭을 포함한 애그리게이트 장치 생성 — `AudioCaptureEngine.swift`
- [x] T1.4 `AudioDeviceCreateIOProcIDWithBlock`으로 PCM 버퍼 수신 (RMS 콘솔 로그는 생략 — 실기 미검증 항목, Phase 6에서 보강)
- [x] T1.5 탭/애그리게이트 장치/IOProc 해제 루틴 (`stop()`)
- [x] T1.6 `NSWorkspace.runningApplications` 기반 "캡처 가능한 앱 목록" 조회 — `MixerModel.refreshAvailableApps()`

## Phase 2 — 인코더
- [x] T2.1 `AVAudioConverter`로 PCM → ADTS/AAC 실시간 인코딩 파이프라인 — `AudioEncoder.swift`
- [ ] T2.2 소스 중단 시 무음 프레임 패딩 처리 (스트림 연속성 유지) — 미구현, Phase 6 QA에서 체감 영향 확인 후 필요하면 추가
- [ ] T2.3 인코딩 지연/프레임 드랍 측정용 간단한 계측 로그 — 미구현

## Phase 3 — 브로드캐스트 서버
- [x] T3.1 `NWListener` 기반 최소 HTTP 서버 (loopback 바인딩, 포트 충돌 시 17320~17329 순차 재시도) — `BroadcastServer.swift`
- [x] T3.2 `GET /stream.aac` → `Transfer-Encoding: chunked` 지속 스트리밍 응답
- [x] T3.3 다중 클라이언트 팬아웃 (연결마다 등록된 `NWConnection` 딕셔너리에 브로드캐스트)
- [x] T3.4 `GET /` 최소 플레이어 페이지(`<audio controls autoplay>`) 서빙
- [ ] T3.5 사설망 공개 옵션 (바인딩 인터페이스 전환 토글) — MVP는 loopback 전용, 보류

## Phase 4 — SwiftUI UI
- [ ] T4.1 ~~`MenuBarExtra`~~ → MVP는 일반 윈도우(`MixerView`)로 구현, 메뉴바 상주는 보류
- [x] T4.2 소스 선택 목록 (실행 중인 앱 / 시스템 전체) — `Picker`
- [ ] T4.3 레벨 미터 뷰 — 미구현
- [x] T4.4 로컬 URL 표시 + 복사 버튼 + "Safari에서 열기" 버튼
- [x] T4.5 접속 중인 클라이언트 수 표시

## Phase 5 — 권한/패키징
- [ ] T5.1 최초 실행 시 권한 안내 온보딩 화면
- [ ] T5.2 권한 거부/철회 상태에 대한 에러 UI
- [ ] T5.3 앱 서명 및 공증 (배포용)

## Phase 6 — QA
- [ ] T6.1 소스 앱 강제 종료 시 스트림 유지 여부 실기 검증
- [ ] T6.2 Safari 다중 탭/다중 기기 동시 접속 테스트
- [ ] T6.3 장시간(1시간+) 송출 안정성 및 메모리 누수 점검
- [ ] T6.4 유휴 상태 CPU 사용량 측정

## Phase 7 — 향후 과제 (스트레치 골)
- [ ] T7.1 HAL Audio Server Plug-in 폴백 경로 (BlackHole 스타일, 구버전 호환)
- [ ] T7.2 ICY 스타일 "지금 재생 중" 메타데이터
- [ ] T7.3 다중 소스 동시 믹싱
- [ ] T7.4 WebRTC 저지연 스트리밍 검토
