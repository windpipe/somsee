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
* **Unified SSBO**: 모든 파티클 데이터를 단일 구조체(AoS/SoA)로 패킹하여 GPU 전송 최적화.
* **Modular Pipeline**: 컴퓨트 셰이더를 통해 3가지 핵심 효과(PBD, Strand, Fluid)를 통합 처리.

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
| **Phase 2** | 샘플러 구현 | 메시 표면 샘플링(Barycentric), 애니메이션 본 트래킹 |
| **Phase 3** | 물리 통합 | PBD/XPBD 솔버 구현, Spatial Hash 충돌 최적화 |
| **Phase 4** | 고급 효과 | Strand(Hair), Fluid 모듈 및 Audio Reactive 엔진 통합 |
| **Phase 5** | 안정화 | 24시간 스트레스 테스트, 하드웨어 스로틀링 튜닝 |

---

### 💡 다음 단계 (Action Item)


**"Odin에서 SDL3 GPU를 초기화하고, 두 개의 창을 띄운 뒤, 100만 개 파티클을 위한 SSBO를 할당하는 초기화 모듈"**의 전체 소스 코드를 지금 바로 작성