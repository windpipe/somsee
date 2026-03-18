# particle_basic_dual

SDL3 GPU API 기반 파티클 시스템 — 듀얼 윈도우 예제.
단일 `GPUDevice`와 단일 Compute pass로 두 윈도우에 동일한 파티클을 렌더링합니다.

## 조작

| 키 | 동작 |
|----|------|
| `↑` / `=` | 파티클 +50,000 |
| `↓` / `-` | 파티클 -50,000 |
| `SPACE` | 100,000으로 리셋 |
| `ESC` | 종료 |

## 빌드

```bat
build.bat
```

셰이더 컴파일(glslc) + Odin 빌드를 순서대로 수행합니다.
반드시 **CMD**에서 실행하세요 (PowerShell은 MSVC 환경 미지원).

## 알려진 사항

### 프레임 상한 없음 / GPU 과부하

현재 메인 루프는 아무 제한 없이 최대 속도로 동작합니다.

```
루프 1회 = AcquireCommandBuffer → Compute pass → Render pass → Submit
```

100k 파티클 기준 약 7000 FPS가 나오는데, 모니터가 표시할 수 있는 건
60~144 Hz이므로 나머지 프레임은 모두 버려집니다.

**문제점**
- GPU 드라이버 큐에 command buffer가 쌓이며 CPU/GPU 동기화 비용 발생
- CPU가 `PollEvent`, `SetWindowTitle`, `Submit`을 7000회/초 반복
- 불필요한 전력 소모

**해결 방향 (미적용)**
- **Vsync**: SDL3 swapchain present mode를 vsync로 설정 → 모니터 주사율에 자동 동기화
- **프레임 타겟**: 목표 FPS를 정하고 남은 시간을 `SDL_DelayNS`로 대기

파티클 시뮬레이션 용도에서는 Vsync가 가장 단순하고 적합한 선택입니다.
