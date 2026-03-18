# particle_basic_single_vsync

`particle_basic_single`에 Vsync를 적용한 예제.
GPU 로직은 동일하며, 모니터 주사율에 프레임을 동기화합니다.

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

반드시 **CMD**에서 실행하세요 (PowerShell은 MSVC 환경 미지원).

---

## Vsync 설명

### 무엇인가

Vsync(수직동기화)는 GPU가 프레임을 모니터의 **수직 귀선 신호(vblank)** 에 맞춰 제출하도록
강제하는 동기화 메커니즘입니다. Vulkan에서는 `VK_PRESENT_MODE_FIFO_KHR`에 해당합니다.

### 왜 필요한가

Vsync 없이 루프를 무제한으로 돌리면:

```
루프 1회 = AcquireCommandBuffer → Compute → Render → Submit
```

100k 파티클 기준 ~7000 FPS가 나오는데, 모니터가 보여줄 수 있는 건 60~144Hz뿐입니다.
나머지 수천 프레임은 버려지며 CPU/GPU가 불필요한 작업을 반복합니다.

Vsync를 켜면 `AcquireGPUSwapchainTexture`가 다음 vblank까지 블로킹하여
루프가 자동으로 모니터 주사율에 맞춰집니다.

### SDL3에서의 적용 방법

```odin
// 지원 여부 확인 후 적용
if sdl3.WindowSupportsGPUPresentMode(device, window, .VSYNC) {
    _ = sdl3.SetGPUSwapchainParameters(device, window, .SDR, .VSYNC)
}
```

`SetGPUSwapchainParameters`는 **윈도우(swapchain) 단위**로 설정됩니다.
`ClaimWindowForGPUDevice` 이후, 첫 프레임 전에 호출해야 합니다.

### Present Mode 비교

| Mode | 동작 | Tearing |
|------|------|---------|
| `.VSYNC` | vblank 대기 (FIFO) | 없음 |
| `.IMMEDIATE` | 즉시 제출 | 있음 |
| `.MAILBOX` | 큐에 최신 프레임만 유지 | 없음, 지연 최소 |

### 듀얼 모니터에서의 한계

Vsync는 swapchain(윈도우) 단위로 설정되므로, 이론상 각 윈도우가
해당 모니터의 주사율에 독립적으로 동기화됩니다.

그러나 현재 `somsee`의 구조는 **단일 command buffer**로 모든 윈도우를 처리합니다:

```
AcquireCommandBuffer
  └─ AcquireGPUSwapchainTexture(window[0])  ← 60Hz 모니터 vblank 대기
  └─ AcquireGPUSwapchainTexture(window[1])  ← 144Hz 모니터 vblank 대기
SubmitGPUCommandBuffer
```

두 acquire가 순차 실행되므로 전체 루프는 **느린 모니터(60Hz)에 묶입니다.**
진정한 독립 vsync를 위해서는 윈도우별 command buffer 분리가 필요합니다.
(Phase 2 이후, 윈도우별 독립 콘텐츠가 필요해지는 시점에 분리 예정)

### Vsync vs 프레임 타겟 비교

| | Vsync | 프레임 타겟 |
|--|-------|------------|
| 동기화 기준 | 모니터 vblank (하드웨어) | 경과 시간 (소프트웨어) |
| Tearing 방지 | O | X |
| 임의 FPS 설정 | X (모니터 주사율 고정) | O |
| 구현 방식 | `SetGPUSwapchainParameters` | `SDL_DelayNS` |
| 적합한 용도 | 렌더링 품질, 전력 절감 | 시뮬레이션 스텝 고정, 배터리 절약 |
