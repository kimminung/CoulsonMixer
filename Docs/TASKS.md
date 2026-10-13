# 콜슨믹서 (ColsonMixer) 태스크 문서

관련 설계 문서: [PRD.md](./PRD.md)

## Phase 0 — 프로젝트 셋업
- [ ] T0.1 Xcode 앱 타깃을 "ColsonMixer"로 구성 (번들 ID, 메뉴바 상주 설정)
- [ ] T0.2 `ColsonMixerKit` 로컬 Swift Package 생성 및 앱 타깃에 연결
- [ ] T0.3 필요 엔타이틀먼트/`Info.plist` 키 조사 및 추가 (시스템 오디오 캡처 권한 — Xcode 최신 문서로 재검증)

## Phase 1 — 오디오 캡처 코어 (스파이크 우선)
- [ ] T1.1 **스파이크**: 샌드박스 On/Off 각각에서 `AudioHardwareCreateProcessTap` 동작 여부 검증 → 결과에 따라 샌드박스 전략 확정
- [ ] T1.2 `CATapDescription` 구성 (대상 프로세스 배열 vs 시스템 전체, 모노/스테레오, 뮤트 동작)
- [ ] T1.3 `AudioHardwareCreateAggregateDevice`로 탭을 포함한 애그리게이트 장치 생성
- [ ] T1.4 `AudioDeviceIOProc` 등록 후 PCM 버퍼 수신 → 콘솔에 레벨(RMS) 로그로 1차 검증
- [ ] T1.5 탭/애그리게이트 장치 해제(`AudioHardwareDestroyProcessTap`/`DestroyAggregateDevice`) 및 앱 종료 시 정리 루틴
- [ ] T1.6 `NSRunningApplication` 기반 "캡처 가능한 앱 목록" 조회 유틸리티

## Phase 2 — 인코더
- [ ] T2.1 `AVAudioConverter`로 PCM → AAC 실시간 인코딩 파이프라인
- [ ] T2.2 소스 중단 시 무음 프레임 패딩 처리 (스트림 연속성 유지)
- [ ] T2.3 인코딩 지연/프레임 드랍 측정용 간단한 계측 로그

## Phase 3 — 브로드캐스트 서버
- [ ] T3.1 `NWListener` 기반 최소 HTTP 서버 (loopback 바인딩)
- [ ] T3.2 `GET /stream.aac` → `Transfer-Encoding: chunked` 지속 스트리밍 응답
- [ ] T3.3 다중 클라이언트 팬아웃 (연결마다 독립 버퍼 큐)
- [ ] T3.4 `GET /` 최소 플레이어 페이지(`<audio controls autoplay>`) 서빙
- [ ] T3.5 사설망 공개 옵션 (바인딩 인터페이스 전환 토글)

## Phase 4 — SwiftUI UI
- [ ] T4.1 `MenuBarExtra` — 송출 On/Off 토글, 상태 아이콘
- [ ] T4.2 소스 선택 목록 (실행 중인 앱 / 시스템 전체)
- [ ] T4.3 레벨 미터 뷰
- [ ] T4.4 로컬 URL 표시 + 복사 버튼 + "Safari에서 열기" 버튼
- [ ] T4.5 접속 중인 클라이언트 수 표시

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
