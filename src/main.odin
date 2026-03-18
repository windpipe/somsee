package main

import "vendor:sdl3"
import "core:fmt"

WINDOW_W          :: 1280
WINDOW_H          ::  720
INITIAL_PARTICLES :: 100_000
PARTICLE_STEP     ::  50_000

main :: proc() {
	// Platform 초기화: GPU device + 2개 윈도우
	plat, ok := platform_init([]Window_Config{
		{title = "somsee [main]", w = WINDOW_W, h = WINDOW_H, flags = {}},
		{title = "somsee [sub]",  w = WINDOW_W, h = WINDOW_H, flags = {}},
	}, debug_mode = true)
	if !ok { return }
	defer platform_destroy(&plat)

	device := plat.device

	// Renderer 초기화 (첫 윈도우의 스와프체인 포맷 기준)
	swapchain_fmt := sdl3.GetGPUSwapchainTextureFormat(device, plat.windows[0])
	rend, ok2 := renderer_init(device, swapchain_fmt)
	if !ok2 { return }
	defer renderer_destroy(device, &rend)

	// Particle system 초기화: 1M 파티클 SSBO 할당, INITIAL_PARTICLES 활성화
	ps, ok3 := particle_system_create(device, INITIAL_PARTICLES, WINDOW_W, WINDOW_H)
	if !ok3 { return }
	defer particle_system_destroy(device, &ps)

	fmt.printf("Ready. Particles: %d / %d\n", ps.active, MAX_PARTICLES)
	fmt.printf("UP/DOWN or +/-: 파티클 수 조절  SPACE: 리셋  ESC: 종료\n")

	// Timing
	last    := sdl3.GetPerformanceCounter()
	freq    := f64(sdl3.GetPerformanceFrequency())
	fps_acc  : f64
	fps_cnt  : int
	fps      : int
	dbg_tick : int

	running := true
	for running {
		now := sdl3.GetPerformanceCounter()
		dt  := f32(f64(now - last) / freq)
		last = now
		dt   = min(dt, 0.05) // 20fps 이하 클램프

		fps_acc += f64(dt)
		fps_cnt += 1
		dbg_tick += 1
		if fps_acc >= 1.0 {
			fps     = fps_cnt
			fps_cnt = 0
			fps_acc -= 1.0
			fmt.printf("FPS: %d  dt: %.4f  active: %d\n", fps, dt, ps.active)
		}

		// 이벤트 처리
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				if event.key.key == sdl3.K_ESCAPE { running = false }
			}
		}

		// 키보드 입력 (파티클 수 실시간 조절)
		kb := sdl3.GetKeyboardState(nil)
		if kb[sdl3.Scancode.UP] || kb[sdl3.Scancode.EQUALS] {
			ps.active = min(ps.active + PARTICLE_STEP, MAX_PARTICLES)
		}
		if kb[sdl3.Scancode.DOWN] || kb[sdl3.Scancode.MINUS] {
			ps.active = max(ps.active - PARTICLE_STEP, 1000)
		}
		if kb[sdl3.Scancode.SPACE] {
			ps.active = INITIAL_PARTICLES
		}

		// 타이틀 업데이트
		title := fmt.ctprintf("somsee | %d particles | %d FPS", ps.active, fps)
		_ = sdl3.SetWindowTitle(plat.windows[0], title)

		// GPU 프레임
		cmd := sdl3.AcquireGPUCommandBuffer(device)
		if cmd == nil { continue }

		// 1. Compute: 물리 업데이트
		particle_compute(cmd, &ps, rend.compute_pipeline, dt, WINDOW_W, WINDOW_H)

		// 2. Render: 모든 윈도우에 동일한 파티클 출력
		for i in 0 ..< plat.window_count {
			renderer_draw_window(cmd, plat.windows[i], &rend, &ps, WINDOW_W, WINDOW_H)
		}

		_ = sdl3.SubmitGPUCommandBuffer(cmd)
	}
}
