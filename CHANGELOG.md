# Changelog

## [Unreleased]

### 구조 변경
- `particle_demo` → `particle_basic_dual` 로 이름 변경
- `particle_basic_single` 예제 추가 (단일 윈도우)
- 키 입력 방식 변경: `GetKeyboardState` 폴링 → `KEY_DOWN` 이벤트 (1회 누름 = 정확히 1 스텝)

### 수정
- **load_file 메모리 리크 해결**: `sdl3.LoadFile` 결과를 파이프라인 생성 후 `sdl3.free`로 해제
  - `defer if X != nil { sdl3.free(raw_data(X)) }` 패턴 적용
  - early return / 로드 실패 케이스에서도 이미 로드된 버퍼 안전하게 정리됨

### 알려진 최적화 필요 항목
- **renderer.odin 중복**: dual/single 예제에 동일 파일이 복사되어 있음. 각 예제가 렌더러를 독립적으로 커스터마이즈할 수 있으므로 의도된 구조이나, 공통 유틸(`load_file` 등)은 향후 core로 이동 고려
- **프레임 상한 없음**: vsync 또는 `SDL_DelayNS` 미적용으로 수천 FPS 동작 중. CPU/GPU 불필요한 부하 발생 가능

### Odin defer 패턴 메모

`defer`는 현재 스코프(함수) 종료 시 실행됩니다. 선언 순서와 **역순**으로 실행됩니다.

```odin
// sdl3.LoadFile 결과 해제 패턴
data := load_file("file.spv")
defer if data != nil { sdl3.free(raw_data(data)) }

// 이후 어느 경로로 return 해도 (정상 / 에러 / early return)
// defer가 항상 free를 보장
```

`sdl3.LoadFile`이 반환하는 메모리는 SDL 내부 힙에서 할당되므로
반드시 `sdl3.free`로 해제해야 합니다 (Odin의 `free`와 혼용 불가).

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
