# somsee API Specification v0.01

> 언어: Odin | 백엔드: SDL3 GPU (Vulkan/SPIR-V) | 버전: 0.01 (Phase 1)

---

## 프로젝트 구조

```
somsee/
├── core/                        — 라이브러리 (package somsee)
│   ├── platform.odin            — Platform: SDL3 초기화, GPU device, 멀티 윈도우
│   └── particle.odin            — Particle_System: SSBO 생성/업로드, compute dispatch
├── examples/
│   └── particle_demo/           — 데모 (package main)
│       ├── main.odin            — 진입점, 메인 루프
│       ├── renderer.odin        — 파이프라인 생성, 렌더 패스 헬퍼
│       ├── shaders/
│       │   ├── particle.comp.glsl
│       │   ├── particle.vert.glsl
│       │   ├── particle.frag.glsl
│       │   └── *.spv            — 컴파일된 SPIR-V (build.bat 생성)
│       └── build.bat
└── build.bat                    — 루트 빌드 (examples 위임)
```

**빌드 명령어 (예제)**
```bat
:: -collection:somsee=../.. 로 core/ 를 "somsee:core" 로 임포트
odin build . -collection:somsee=../.. -out:particle_demo.exe -o:speed
```

**임포트 (예제 코드)**
```odin
import sc "somsee:core"
```

---

## core/platform.odin  (package somsee)

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

#### `Platform_Init`
```odin
Platform_Init(window_configs: []Window_Config, debug_mode := false) -> (Platform, bool)
```
- SDL3 초기화 (`{.VIDEO}`)
- Vulkan 백엔드 GPUDevice 생성 (`{.SPIRV}`)
- 각 Window_Config마다 윈도우 생성 후 GPUDevice에 claim
- 반환: `(Platform, ok)` — 실패 시 ok=false, 정리 후 반환

#### `Platform_Destroy`
```odin
Platform_Destroy(p: ^Platform)
```
- 모든 윈도우 release + destroy
- GPUDevice destroy
- SDL3 Quit

---

## core/particle.odin  (package somsee)

### 상수

| 이름 | 값 | 설명 |
|------|----|------|
| `MAX_PARTICLES` | `1_000_000` | SSBO 최대 파티클 수 (사전 할당) |
| `COMPUTE_GROUP_SIZE` | `256` | Compute shader local_size_x |

### 타입

```odin
// SoA 레이아웃 — GPU 캐시 효율 최대화
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
// Compute shader uniform (set=2, binding=0)
Compute_UBO :: struct {
    bounds_x: f32,
    bounds_y: f32,
    count:    u32,
    dt:       f32,
}
// 총 16 bytes, std140 호환

// Vertex shader uniform (set=1, binding=0)
Screen_UBO :: struct {
    w: f32,
    h: f32,
}
// 총 8 bytes
```

### 함수

#### `Particle_System_Create`
```odin
Particle_System_Create(
    device:   ^sdl3.GPUDevice,
    active:   int,
    bounds_x: f32,
    bounds_y: f32,
) -> (Particle_System, bool)
```
- 4개 GPU 버퍼 생성 (MAX_PARTICLES 기준)
- Transfer buffer를 통해 초기 데이터 업로드 (copy pass + submit)
- 초기값: pos=랜덤, vel=±300px/s, color=랜덤 밝은 색, size=1~4px

#### `Particle_System_Destroy`
```odin
Particle_System_Destroy(device: ^sdl3.GPUDevice, ps: ^Particle_System)
```
- 4개 GPU 버퍼 release

#### `Particle_Compute`
```odin
Particle_Compute(
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

---

## examples/particle_demo/renderer.odin  (package main)

> 이 파일은 라이브러리가 아닌 예제 전용. `import sc "somsee:core"` 로 core 참조.

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
- `sdl3.LoadFile` 래퍼, 실패 시 nil + 에러 출력

#### `renderer_init`
```odin
renderer_init(
    device:           ^sdl3.GPUDevice,
    swapchain_format: sdl3.GPUTextureFormat,
) -> (Renderer, bool)
```
- `shaders/particle.comp.spv` → compute pipeline (RW storage 2 + uniform 1)
- `shaders/particle.vert.spv` + `shaders/particle.frag.spv` → graphics pipeline
- Graphics pipeline: `POINTLIST`, alpha blending, 정점 입력 없음

**파이프라인 셰이더 바인딩 요약**

| 파이프라인 | 종류 | 수 |
|-----------|------|-----|
| compute | RW storage buffers | 2 (pos, vel) |
| compute | uniform buffers | 1 |
| graphics vert | RO storage buffers | 3 (pos, color, size) |
| graphics vert | uniform buffers | 1 |
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
    ps:       ^sc.Particle_System,
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
layout(set = 1, binding = 0) buffer Positions  { vec2 pos[]; };  // RW storage
layout(set = 1, binding = 1) buffer Velocities { vec2 vel[]; };  // RW storage
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

### SDL3 SPIR-V Descriptor Set 규칙 (중요)

| Set | Compute | Vertex | Fragment |
|-----|---------|--------|----------|
| 0 | RO storage (sampled tex, RO buf) | RO storage buffers | sampled textures |
| 1 | **RW storage buffers/textures** | uniform buffers | RO storage buffers |
| 2 | **uniform buffers** | — | uniform buffers |
| 3 | — | — | RW storage |

> CLAUDE.md 등 일부 문서에 set=0이 RW라고 잘못 기재된 경우 있음. 실제 SDL_gpu.h 기준 set=1이 RW.

---

## 메인 루프 프레임 순서

```
1. GetPerformanceCounter → dt 계산 (max 50ms cap)
2. PollEvent (QUIT, ESC)
3. GetKeyboardState (UP/DOWN/+/-/SPACE) → ps.active 조절
4. SetWindowTitle (active count, FPS)
5. AcquireGPUCommandBuffer
6. Particle_Compute(cmd, ...)         ← Compute pass
7. for each window:
     renderer_draw_window(cmd, ...)   ← Render pass
8. SubmitGPUCommandBuffer
```

---

## 빌드

```bat
:: 루트에서
build.bat

:: 또는 예제 디렉토리에서 직접
examples\particle_demo\build.bat
```

**실행**: `examples\particle_demo\particle_demo.exe` (반드시 CMD에서, PowerShell 불가)

**의존성**
- Odin dev-2026-03 (`C:\tools\Odin`)
- Vulkan SDK 1.3.216.0 (`C:\VulkanSDK\1.3.216.0`)
- SDL3.dll (Odin vendor 포함)
