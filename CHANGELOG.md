# Changelog

## [Unreleased]

### 구조 변경
- `particle_demo` → `particle_basic_dual` 로 이름 변경
- `particle_basic_single` 예제 추가 (단일 윈도우)
- 키 입력 방식 변경: `GetKeyboardState` 폴링 → `KEY_DOWN` 이벤트 (1회 누름 = 정확히 1 스텝)

### 알려진 최적화 필요 항목
- **renderer.odin 중복**: dual/single 예제에 동일 파일이 복사되어 있음. 예제 수 증가 시 유지보수 부담 누적
- **load_file 메모리 리크**: `sdl3.LoadFile` 결과를 파이프라인 생성 후 해제하지 않음. 스타트업 1회 발생, 실질 영향 없으나 미정리 상태
- **프레임 상한 없음**: vsync 또는 `SDL_DelayNS` 미적용으로 수천 FPS 동작 중. CPU/GPU 불필요한 부하 발생 가능

---

## [0.01] - 2026-03-18

### Phase 1 — 인프라 구축

**달성 항목**
- SDL3 GPU device 초기화 (Vulkan / SPIR-V 백엔드)
- 단일 `GPUDevice` 기반 멀티 윈도우 스왑체인 공유
- SoA(Structure of Arrays) 레이아웃 SSBO: pos / vel / color / size 분리
- GPU Compute shader로 파티클 물리 연산 (bounce)
- GPU Render pass — POINTLIST + gl_VertexIndex 직접 읽기, soft-circle 렌더
- 실시간 파티클 수 조절 (UP/DOWN/+/-/SPACE)
- 빌드 스크립트 (build.bat)

**확인된 성능**
- 100k 파티클 @ ~7000 FPS (RTX 3090, Vulkan)
- 1M 파티클 SSBO 사전 할당

**SDL3 SPIR-V Compute 바인딩 (이 버전에서 확인)**
- set=1 : RW storage buffers
- set=2 : Uniform buffers
- (Vertex shader는 set=0 storage, set=1 uniform — 기존과 동일)

**미구현 (Phase 2~5 예정)**
- SDL_GetDisplays() 기반 실제 모니터 좌표 배치
- Indirect Draw
- Arena allocator / Zero-Leak 메모리 관리
- 멀티스레드 I/O (MediaPipe, Audio FFT, OSC)
- PBD/XPBD Constraint 구조
- Particle State 플래그 (PBD / Strand / Fluid 분기)
