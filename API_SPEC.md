# somsee API Specification v0.01

> 언어: Odin | 백엔드: SDL3 GPU (Vulkan/SPIR-V) | 버전: 0.01 (Phase 1)

---

## 모듈 구조

```
src/
├── main.odin       — 진입점, 메인 루프
├── platform.odin   — Hardware_Manager: SDL3 초기화, GPU device, 멀티 윈도우
├── particle.odin   — Particle_Controller: SSBO 생성/업로드, compute dispatch
└── renderer.odin   — 파이프라인 생성, 렌더 패스 헬퍼
```

모든 파일은 `package main` 단일 패키지.

---

## platform.odin

### 상수

| 이름 | 값 | 설명 |
|------|----|------|
| `MAX_WINDOWS` | `4` | 동시 관리 가능한 최대 윈도우 수 |

### 타입

```odin
Window_Config :: struct {
    title: cstring,
    w, h:  c.int,
    flags: sdl3.WindowFlags,
}

Platform :: struct {
    device:       ^sdl3.GPUDevice,
    windows:      [MAX_WINDOWS]^sdl3.Window,
    window_count: int,
}
```

### 함수

#### `platform_init`
```odin
platform_init(window_configs: []Window_Config, debug_mode := false) -> (Platform, bool)
```
- SDL3 초기화 (`{.VIDEO}`)
- Vulkan 백엔드 GPUDevice 생성 (`{.SPIRV}`)
- 각 Window_Config마다 윈도우 생성 후 GPUDevice에 claim
- 반환: `(Platform, ok)` — 실패 시 ok=false, 정리 후 반환

#### `platform_destroy`
```odin
platform_destroy(p: ^Platform)
```
- 모든 윈도우 release + destroy
- GPUDevice destroy
- SDL3 Quit

---

## particle.odin

### 상수

| 이름 | 값 | 설명 |
|------|----|------|
| `MAX_PARTICLES` | `1_000_000` | SSBO 최대 파티클 수 (사전 할당) |
| `COMPUTE_GROUP_SIZE` | `256` | Compute shader local_size_x |

### 타입

```odin
Particle_System :: struct {
    pos:    ^sdl3.GPUBuffer,  // [MAX_PARTICLES][2]f32  — compute RW + graphics R
    vel:    ^sdl3.GPUBuffer,  // [MAX_PARTICLES][2]f32  — compute RW
    color:  ^sdl3.GPUBuffer,  // [MAX_PARTICLES][4]f32  — graphics R (정적)
    size:   ^sdl3.GPUBuffer,  // [MAX_PARTICLES]f32     — graphics R (정적)
    active: int,              // 현재 활성화된 파티클 수
}
```

**GPU 버퍼 사용 플래그**

| 버퍼 | usage flags |
|------|-------------|
| pos  | `COMPUTE_STORAGE_READ \| COMPUTE_STORAGE_WRITE \| GRAPHICS_STORAGE_READ` |
| vel  | `COMPUTE_STORAGE_READ \| COMPUTE_STORAGE_WRITE` |
| color | `GRAPHICS_STORAGE_READ` |
| size | `GRAPHICS_STORAGE_READ` |

```odin
Compute_UBO :: struct {
    bounds_x: f32,
    bounds_y: f32,
    count:    u32,
    dt:       f32,
}
// 총 16 bytes, std140 호환

Screen_UBO :: struct {
    w: f32,
    h: f32,
}
// 총 8 bytes
```

### 함수

#### `particle_system_create`
```odin
particle_system_create(
    device:   ^sdl3.GPUDevice,
    active:   int,
    bounds_x: f32,
    bounds_y: f32,
) -> (Particle_System, bool)
```
- 4개 GPU 버퍼 생성 (MAX_PARTICLES 기준)
- Transfer buffer를 통해 초기 데이터 업로드 (copy pass + submit)
- 초기값: pos=랜덤, vel=±300px/s, color=랜덤 밝은 색, size=1~4px

#### `particle_system_destroy`
```odin
particle_system_destroy(device: ^sdl3.GPUDevice, ps: ^Particle_System)
```
- 4개 GPU 버퍼 release

#### `particle_compute`
```odin
particle_compute(
    cmd:      ^sdl3.GPUCommandBuffer,
    ps:       ^Particle_System,
    pipeline: ^sdl3.GPUComputePipeline,
    dt:       f32,
    bounds_x: f32,
    bounds_y: f32,
)
```
- `PushGPUComputeUniformData(cmd, 0, Compute_UBO)` — slot 0
- `BeginGPUComputePass` with pos(binding=0), vel(binding=1)
- `DispatchGPUCompute(ceil(active / 256), 1, 1)`
- **주의**: cmd는 반드시 active compute pass가 없는 상태여야 함

---

## renderer.odin

### 타입

```odin
Renderer :: struct {
    compute_pipeline:  ^sdl3.GPUComputePipeline,
    graphics_pipeline: ^sdl3.GPUGraphicsPipeline,
}
```

### 함수

#### `load_file`
```odin
load_file(path: cstring) -> []u8
```
- `sdl3.LoadFile` 래퍼
- 실패 시 nil 반환 + 에러 출력

#### `renderer_init`
```odin
renderer_init(
    device:           ^sdl3.GPUDevice,
    swapchain_format: sdl3.GPUTextureFormat,
) -> (Renderer, bool)
```
- `shaders/particle.comp.spv` → compute pipeline
- `shaders/particle.vert.spv` + `shaders/particle.frag.spv` → graphics pipeline
- Graphics pipeline: `POINTLIST`, alpha blending 활성화, 정점 입력 없음

**파이프라인 셰이더 바인딩 요약**

| 파이프라인 | 종류 | 바인딩 |
|-----------|------|--------|
| compute | RW storage | 2개 (pos, vel) |
| compute | uniform | 1개 |
| graphics vert | storage (RO) | 3개 (pos, color, size) |
| graphics vert | uniform | 1개 |
| graphics frag | — | 없음 |

#### `renderer_destroy`
```odin
renderer_destroy(device: ^sdl3.GPUDevice, r: ^Renderer)
```

#### `renderer_draw_window`
```odin
renderer_draw_window(
    cmd:      ^sdl3.GPUCommandBuffer,
    window:   ^sdl3.Window,
    r:        ^Renderer,
    ps:       ^Particle_System,
    screen_w: f32,
    screen_h: f32,
)
```
- `AcquireGPUSwapchainTexture` — 실패 시 early return
- `PushGPUVertexUniformData(cmd, 0, Screen_UBO)`
- Render pass: clear(0.04, 0.04, 0.08, 1.0), BindVertexStorageBuffers(pos, color, size), DrawGPUPrimitives(active, 1, 0, 0)

---

## Shader Interface

### particle.comp.glsl

**SPIR-V Compute 바인딩 (SDL3 dev-2026-03)**

```glsl
layout(set = 1, binding = 0) buffer Positions  { vec2 pos[]; };  // RW
layout(set = 1, binding = 1) buffer Velocities { vec2 vel[]; };  // RW
layout(set = 2, binding = 0) uniform UBO {                        // Uniform
    float bounds_x;
    float bounds_y;
    uint  count;
    float dt;
};
layout(local_size_x = 256) in;
```

로직: `p += v * dt` → 경계 반사 → write back

### particle.vert.glsl

**SPIR-V Vertex 바인딩**

```glsl
layout(set = 0, binding = 0) readonly buffer Positions { vec2 pos[];   };
layout(set = 0, binding = 1) readonly buffer Colors    { vec4 color[]; };
layout(set = 0, binding = 2) readonly buffer Sizes     { float sz[];   };
layout(set = 1, binding = 0) uniform Screen { float w; float h; };
```

로직: `gl_VertexIndex`로 인덱싱 → NDC 변환 `(p/screen)*2-1` → `gl_PointSize = sz[i]`

### particle.frag.glsl

입력: `vec4 frag_color`
로직: `gl_PointCoord` 기반 원형 clip + 중심→가장자리 alpha fade

---

## 메인 루프 프레임 순서

```
1. GetPerformanceCounter → dt 계산
2. PollEvent (QUIT, ESC)
3. GetKeyboardState (UP/DOWN/+/-/SPACE) → ps.active 조절
4. SetWindowTitle (FPS, active count)
5. AcquireGPUCommandBuffer
6. particle_compute(cmd, ...)       ← Compute pass
7. for each window:
     renderer_draw_window(cmd, ...) ← Render pass
8. SubmitGPUCommandBuffer
```

---

## 빌드

```cmd
build.bat          :: 셰이더 컴파일 + Odin 빌드
somsee.exe         :: 실행 (CMD에서. PowerShell 불가)
```

**의존성**
- Odin dev-2026-03 (`C:\tools\Odin`)
- Vulkan SDK 1.3.216.0 (`C:\VulkanSDK\1.3.216.0`)
- SDL3.dll (Odin vendor 포함)
