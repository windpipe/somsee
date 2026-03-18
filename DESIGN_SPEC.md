---

# 📑 Project: Unified GPU Particle Engine (UGPE)
**Technical Design Specification v1.0 (2026-03-18)**

## 1. 프로젝트 비전 (Vision)
* **목표**: 범용 엔진의 오버헤드를 제거하고 RTX 3090의 성능을 극한으로 활용하는 초고성능 미디어 엔진 구축.
* **핵심 가치**: 24/7 가동 안정성, 백만 단위 파티클 실시간 제어, 물리 기반 통합 시뮬레이션.
* **기술 스택**: Odin Language, SDL3 GPU API, SPIR-V, Multi-threaded I/O.

---

## 2. 시스템 아키텍처 (Architecture)

### 2.1 하드웨어 제어 계층 (Hardware_Manager)
* **Multi-Window/Monitor**: SDL3를 통한 전역 좌표계 관리 및 독립적 창 제어.
* **Resource Sharing**: 단일 `GPUDevice` 기반 멀티 스위프체인(Swapchain) 렌더링.
* **Health Monitor**: GPU 온도 및 VRAM 상태 감시를 통한 하드웨어 보호.

### 2.2 파티클 콘트롤러 (Particle_Controller)
* **Unified SSBO**: 모든 파티클 데이터를 SoA(Structure of Arrays)로 패킹하여 GPU 캐시 효율 최대화.
* **Modular Pipeline**: 컴퓨트 셰이더를 통해 3가지 핵심 효과(PBD, Strand, Fluid)를 통합 처리.
* **Per-Particle Lifecycle**: 파티클마다 독립적인 수명, 나이, 상태 플래그를 부여하여 효과별 다른 물리/렌더 적용.

### 2.3 파티클 데이터 모델 (Particle Data Model)

**SoA GPU 버퍼 구성 (목표)**

| 버퍼 | 타입 | 용도 | 현재 |
|------|------|------|------|
| `pos` | `vec3` | 위치 (3D) | vec2 (Phase 1) |
| `vel` | `vec3` | 속도 (3D) | vec2 (Phase 1) |
| `color` | `vec4` | RGBA | 구현됨 |
| `size` | `f32` | 크기 | 구현됨 |
| `lifetime` | `f32` | 최대 수명 | 미구현 |
| `age` | `f32` | 현재 나이 (매 프레임 += dt) | 미구현 |
| `flags` | `u32` | 파티클 타입 / 상태 비트 | 미구현 |
| `user` | `vec4` | 효과별 자유 데이터 | 미구현 |

**flags 비트 레이아웃 (안)**

```
bits [7:0]   — 파티클 타입 (TYPE_POINT, TYPE_CUBE, TYPE_RIBBON, ...)
bits [15:8]  — 상태 (ALIVE, DYING, DEAD, SPAWNING)
bits [16]    — FLAG_COLLIDE (충돌 감지 대상 여부)
bits [31:17] — 효과별 서브타입 / 예약
```

compute shader에서 `flags`를 읽어 파티클마다 다른 물리를 분기 처리:

```glsl
uint type = flags[i] & 0xFF;
if      (type == TYPE_DISSOLVE) { /* 수명 기반 크기 축소 */ }
else if (type == TYPE_DANCING)  { /* 위상 기반 진동 */     }
else if (type == TYPE_STRAND)   { /* 체인 제약 조건 */     }

// 충돌 플래그가 있는 파티클만 Spatial Hash 조회
if ((flags[i] & FLAG_COLLIDE) != 0) {
    // spatial hash 기반 이웃 탐색 + 충돌 해소 (PBD)
}
```

### 2.4 파티클 충돌 시스템 (Collision)

나이브한 충돌 감지는 O(N²) — 1M 파티클이면 1조 번 비교로 불가능.
**Spatial Hash** 로 O(N)으로 줄인다.

**원리**

공간을 격자 셀로 분할하고, 각 파티클은 같은 셀 + 인접 셀 파티클하고만 비교:

```
셀 크기 = 파티클 반지름 × 2
1M 파티클 × 평균 50 이웃 = 5000만 비교 / 프레임  (RTX 3090 처리 가능)
```

**GPU 멀티 패스 구현 (Phase 3)**

```
Compute Pass 1 — 각 파티클을 격자 셀 인덱스에 배정
Compute Pass 2 — 셀 기준 정렬 (GPU Radix Sort)
Compute Pass 3 — 인접 셀 조회 → 거리 기반 충돌 해소 (PBD distance constraint)
```

**효과별 충돌 필요 여부**

| 효과 | 충돌 필요 | 이유 |
|------|-----------|------|
| 디졸브/댄싱 | 불필요 | 시각적 흐름 목적, 겹쳐도 무방 |
| 헤어/스트링 | 선택적 | 체인 내부 제약은 필요, 체인 간 충돌은 고비용 |
| 유체 (SPH) | 필수 | 밀도/압력 기반 상호작용이 핵심 |
| PBD 물체 분해 | 필수 | 파편끼리 튕겨야 물질감 생김 |

**`flags`와의 연계**

`FLAG_COLLIDE` 비트가 설정된 파티클만 Spatial Hash에 등록/조회.
전체 1M 중 충돌이 필요한 파티클만 선택적으로 처리하여 성능 낭비 최소화.

### 2.5 렌더 형태 설계 (Render Shape)

효과 목적에 따라 파티클 렌더 형태가 달라진다:

| 효과 타입 | 렌더 형태 | 이유 |
|-----------|-----------|------|
| 디졸브/분해 | 큐브 (인스턴싱) | 물질감. 원거리에서 쿼드로 LOD 전환 |
| 댄싱 파티클 | 포인트/쿼드 | 전체 흐름이 중요. 가장 가벼운 선택 |
| 헤어/스트링 | 리본 Strip | 실린더 대비 폴리곤 최소화, 털 질감 표현 |

**구현 선행 조건:**

| 형태 | 선행 작업 |
|------|-----------|
| 포인트/쿼드 | 이미 구현됨 |
| 큐브 (기본) | 3D 위치(vec3), MVP 행렬, 깊이 버퍼 |
| 큐브 + LOD | 카메라 시스템 (거리 계산 기반 전환) |
| 리본/스트링 | 체인 데이터 구조 (파티클 간 순서 정보) |

---

## 3. 핵심 기술 및 물리 엔진 (Core Tech)

### 3.1 통합 PBD/XPBD 솔버
모든 물체를 입자로 간주하고 제약 조건(Constraints)에 따라 위치를 수정하는 통합 아키텍처.
* **PBD 충돌**: 입자 간 거리 기반 반발력.
* **Strand/Fur**: 거리(Distance) 및 굽힘(Bending) 제약을 통한 실시간 체인 물리.
* **Fluid**: 밀도(Density) 제약을 통한 비압축성 유체 시뮬레이션.

### 3.2 수식 및 로직
파티클 $i$의 위치 수정량 $\Delta p_i$는 다음과 같이 계산됩니다:
$$\Delta p_i = - \frac{w_i}{\sum w_j} C(p) \nabla C(p)$$
(단, $C(p)$는 제약 조건 함수, $w$는 질량의 역수)

---

## 4. 24/7 가동 안정성 설계 (Reliability)

### 4.1 Odin 컨텍스트(Context) 활용
* **Zero-Leak Memory**: 프레임마다 초기화되는 `Arena Allocator`를 `context.allocator`에 할당하여 누수 원천 차단.
* **Watchdog Integration**: `context.logger`를 활용한 실시간 에러 트래킹 및 자동 복구 시스템.

### 4.2 멀티스레딩 전략
* **I/O Thread**: MediaPipe(Pose), Audio(FFT), OSC 데이터를 Lock-free 방식으로 수신.
* **Worker Threads**: 에셋 로딩 및 CPU 기반 고속 정렬(Sort) 작업 수행.
* **Async Compute**: 그래픽 렌더링과 물리 연산을 분리하여 GPU 하드웨어 큐 최적화.

---

## 5. 확장성 및 플러그인 시스템 (Extensibility)

* **Module Isolation**: 그래픽, 오디오, I/O 모듈의 완전 분리.
* **Dynamic Loading**: Odin의 `dynlib`을 활용한 런타임 효과(Shader/Logic) 교체 가능성.
* **Blackboard Pattern**: 중앙 공유 데이터 풀을 통한 모듈 간 아토믹 데이터 교환.

---

## 6. 개발 로드맵 (Roadmap)

| 단계 | 목표 | 핵심 마일스톤 |
| :--- | :--- | :--- |
| **Phase 1** | 인프라 구축 | SDL3 GPU 초기화, 멀티 모니터 윈도우 생성, 기초 컴퓨트 패스 |
| **Phase 2** | 파티클 고도화 | Per-particle lifecycle(lifetime/age/flags), 3D 위치(vec3), MVP/카메라, 깊이 버퍼, 큐브 인스턴싱 |
| **Phase 3** | 물리 + 충돌 | PBD/XPBD 솔버, Spatial Hash 충돌 감지 (GPU Radix Sort), FLAG_COLLIDE 선택적 처리, 메시 표면 샘플링(Barycentric) |
| **Phase 4** | 고급 효과 | Strand(Hair/Ribbon), Fluid 모듈, Audio Reactive 엔진 통합, LOD 시스템 |
| **Phase 5** | 안정화 | 24시간 스트레스 테스트, 하드웨어 스로틀링 튜닝 |

---

### 💡 다음 단계 (Action Item)


**"Odin에서 SDL3 GPU를 초기화하고, 두 개의 창을 띄운 뒤, 100만 개 파티클을 위한 SSBO를 할당하는 초기화 모듈"**의 전체 소스 코드를 지금 바로 작성