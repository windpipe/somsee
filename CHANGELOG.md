# Changelog

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
