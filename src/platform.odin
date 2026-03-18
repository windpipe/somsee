package main

import "vendor:sdl3"
import "core:fmt"
import "core:c"

MAX_WINDOWS :: 4

Window_Config :: struct {
	title: cstring,
	w, h:  c.int,
	flags: sdl3.WindowFlags,
}

// Hardware_Manager: SDL3 + GPU device + multi-window
Platform :: struct {
	device:       ^sdl3.GPUDevice,
	windows:      [MAX_WINDOWS]^sdl3.Window,
	window_count: int,
}

platform_init :: proc(window_configs: []Window_Config, debug_mode := false) -> (p: Platform, ok: bool) {
	if !sdl3.Init({.VIDEO}) {
		fmt.printf("SDL_Init failed: %s\n", sdl3.GetError())
		return
	}

	p.device = sdl3.CreateGPUDevice({.SPIRV}, debug_mode, nil)
	if p.device == nil {
		fmt.printf("CreateGPUDevice failed: %s\n", sdl3.GetError())
		sdl3.Quit()
		return
	}

	fmt.printf("GPU: %s\n", sdl3.GetGPUDeviceDriver(p.device))

	count := min(len(window_configs), MAX_WINDOWS)
	for i in 0 ..< count {
		wc := window_configs[i]
		win := sdl3.CreateWindow(wc.title, wc.w, wc.h, wc.flags)
		if win == nil {
			fmt.printf("CreateWindow[%d] failed: %s\n", i, sdl3.GetError())
			platform_destroy(&p)
			return
		}
		if !sdl3.ClaimWindowForGPUDevice(p.device, win) {
			fmt.printf("ClaimWindow[%d] failed: %s\n", i, sdl3.GetError())
			sdl3.DestroyWindow(win)
			platform_destroy(&p)
			return
		}
		p.windows[i] = win
		p.window_count += 1
	}

	ok = true
	return
}

platform_destroy :: proc(p: ^Platform) {
	for i in 0 ..< p.window_count {
		if p.windows[i] != nil {
			sdl3.ReleaseWindowFromGPUDevice(p.device, p.windows[i])
			sdl3.DestroyWindow(p.windows[i])
			p.windows[i] = nil
		}
	}
	if p.device != nil {
		sdl3.DestroyGPUDevice(p.device)
		p.device = nil
	}
	sdl3.Quit()
}
