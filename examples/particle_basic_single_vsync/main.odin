package main

import sc "somsee:core"
import "vendor:sdl3"
import "core:fmt"

WINDOW_W          :: 1280
WINDOW_H          ::  720
INITIAL_PARTICLES :: 100_000
PARTICLE_STEP     ::  50_000

main :: proc() {
	plat, ok := sc.Platform_Init([]sc.Window_Config{
		{title = "somsee | particle basic single vsync", w = WINDOW_W, h = WINDOW_H, flags = {}},
	})
	if !ok { return }
	defer sc.Platform_Destroy(&plat)

	device := plat.device
	window := plat.windows[0]

	// Vsync 지원 여부 확인 후 적용
	if sdl3.WindowSupportsGPUPresentMode(device, window, .VSYNC) {
		_ = sdl3.SetGPUSwapchainParameters(device, window, .SDR, .VSYNC)
		fmt.printf("Vsync: ON\n")
	} else {
		fmt.printf("Vsync: not supported on this device, running uncapped\n")
	}

	swapchain_fmt := sdl3.GetGPUSwapchainTextureFormat(device, window)
	rend, ok2 := renderer_init(device, swapchain_fmt)
	if !ok2 { return }
	defer renderer_destroy(device, &rend)

	ps, ok3 := sc.Particle_System_Create(device, INITIAL_PARTICLES, WINDOW_W, WINDOW_H)
	if !ok3 { return }
	defer sc.Particle_System_Destroy(device, &ps)

	fmt.printf("Ready. Particles: %d / %d\n", ps.active, sc.MAX_PARTICLES)
	fmt.printf("UP/DOWN or +/-: 파티클 수 조절  SPACE: 리셋  ESC: 종료\n")

	last    := sdl3.GetPerformanceCounter()
	freq    := f64(sdl3.GetPerformanceFrequency())
	fps_acc : f64
	fps_cnt : int
	fps     : int

	running := true
	for running {
		now := sdl3.GetPerformanceCounter()
		dt  := f32(f64(now - last) / freq)
		last = now
		dt   = min(dt, 0.05)

		fps_acc += f64(dt)
		fps_cnt += 1
		if fps_acc >= 1.0 {
			fps     = fps_cnt
			fps_cnt = 0
			fps_acc -= 1.0
		}

		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				#partial switch event.key.scancode {
				case .ESCAPE:
					running = false
				case .UP, .EQUALS:
					ps.active = min(ps.active + PARTICLE_STEP, sc.MAX_PARTICLES)
				case .DOWN, .MINUS:
					ps.active = max(ps.active - PARTICLE_STEP, 1000)
				case .SPACE:
					ps.active = INITIAL_PARTICLES
				}
			}
		}

		title := fmt.ctprintf("somsee | %d particles | %d FPS", ps.active, fps)
		_ = sdl3.SetWindowTitle(window, title)

		cmd := sdl3.AcquireGPUCommandBuffer(device)
		if cmd == nil { continue }

		sc.Particle_Compute(cmd, &ps, rend.compute_pipeline, dt, WINDOW_W, WINDOW_H)
		renderer_draw_window(cmd, window, &rend, &ps, WINDOW_W, WINDOW_H)

		_ = sdl3.SubmitGPUCommandBuffer(cmd)
	}
}
