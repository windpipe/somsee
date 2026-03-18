package main

import "vendor:sdl3"
import "core:fmt"
import "core:c"

// Renderer: 파이프라인 보유 + 렌더 패스 헬퍼
Renderer :: struct {
	compute_pipeline:  ^sdl3.GPUComputePipeline,
	graphics_pipeline: ^sdl3.GPUGraphicsPipeline,
}

load_file :: proc(path: cstring) -> []u8 {
	size: c.size_t
	data := sdl3.LoadFile(path, &size)
	if data == nil {
		fmt.printf("Failed to load: %s — %s\n", path, sdl3.GetError())
		return nil
	}
	return ([^]u8)(data)[:size]
}

renderer_init :: proc(
	device: ^sdl3.GPUDevice,
	swapchain_format: sdl3.GPUTextureFormat,
) -> (
	r: Renderer,
	ok: bool,
) {
	comp_code := load_file("shaders/particle.comp.spv")
	vert_code := load_file("shaders/particle.vert.spv")
	frag_code := load_file("shaders/particle.frag.spv")
	if comp_code == nil || vert_code == nil || frag_code == nil { return }

	// Compute pipeline: pos(binding=0) + vel(binding=1) RW, uniform(set=1)
	r.compute_pipeline = sdl3.CreateGPUComputePipeline(device, sdl3.GPUComputePipelineCreateInfo{
		code_size                     = len(comp_code),
		code                          = raw_data(comp_code),
		entrypoint                    = "main",
		format                        = {.SPIRV},
		num_readwrite_storage_buffers = 2,
		num_uniform_buffers           = 1,
		threadcount_x                 = COMPUTE_GROUP_SIZE,
		threadcount_y                 = 1,
		threadcount_z                 = 1,
	})
	if r.compute_pipeline == nil {
		fmt.printf("CreateGPUComputePipeline failed: %s\n", sdl3.GetError())
		return
	}

	// Vertex shader: storage(pos, color, size) + uniform(screen)
	vert_shader := sdl3.CreateGPUShader(device, sdl3.GPUShaderCreateInfo{
		code_size           = len(vert_code),
		code                = raw_data(vert_code),
		entrypoint          = "main",
		format              = {.SPIRV},
		stage               = .VERTEX,
		num_storage_buffers = 3,
		num_uniform_buffers = 1,
	})
	if vert_shader == nil {
		fmt.printf("CreateGPUShader (vert) failed: %s\n", sdl3.GetError())
		return
	}
	defer sdl3.ReleaseGPUShader(device, vert_shader)

	frag_shader := sdl3.CreateGPUShader(device, sdl3.GPUShaderCreateInfo{
		code_size  = len(frag_code),
		code       = raw_data(frag_code),
		entrypoint = "main",
		format     = {.SPIRV},
		stage      = .FRAGMENT,
	})
	if frag_shader == nil {
		fmt.printf("CreateGPUShader (frag) failed: %s\n", sdl3.GetError())
		return
	}
	defer sdl3.ReleaseGPUShader(device, frag_shader)

	// Alpha blending
	color_target := sdl3.GPUColorTargetDescription{
		format = swapchain_format,
		blend_state = sdl3.GPUColorTargetBlendState{
			enable_blend          = true,
			src_color_blendfactor = .SRC_ALPHA,
			dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
			color_blend_op        = .ADD,
			src_alpha_blendfactor = .ONE,
			dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
			alpha_blend_op        = .ADD,
		},
	}

	// Graphics pipeline: 정점 입력 없음, POINTLIST, storage에서 직접 읽음
	r.graphics_pipeline = sdl3.CreateGPUGraphicsPipeline(device, sdl3.GPUGraphicsPipelineCreateInfo{
		vertex_shader  = vert_shader,
		fragment_shader = frag_shader,
		primitive_type  = .POINTLIST,
		rasterizer_state = sdl3.GPURasterizerState{fill_mode = .FILL, cull_mode = .NONE},
		target_info = sdl3.GPUGraphicsPipelineTargetInfo{
			color_target_descriptions = &color_target,
			num_color_targets         = 1,
		},
	})
	if r.graphics_pipeline == nil {
		fmt.printf("CreateGPUGraphicsPipeline failed: %s\n", sdl3.GetError())
		return
	}

	ok = true
	return
}

renderer_destroy :: proc(device: ^sdl3.GPUDevice, r: ^Renderer) {
	if r.compute_pipeline  != nil { sdl3.ReleaseGPUComputePipeline(device, r.compute_pipeline) }
	if r.graphics_pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(device, r.graphics_pipeline) }
}

// 단일 윈도우에 파티클 렌더. cmd는 호출자가 관리.
renderer_draw_window :: proc(
	cmd: ^sdl3.GPUCommandBuffer,
	window: ^sdl3.Window,
	r: ^Renderer,
	ps: ^Particle_System,
	screen_w, screen_h: f32,
) {
	swapchain_tex: ^sdl3.GPUTexture
	sw_w, sw_h: sdl3.Uint32
	if !sdl3.AcquireGPUSwapchainTexture(cmd, window, &swapchain_tex, &sw_w, &sw_h) ||
	   swapchain_tex == nil {
		return
	}

	ubo := Screen_UBO{w = screen_w, h = screen_h}
	sdl3.PushGPUVertexUniformData(cmd, 0, &ubo, size_of(Screen_UBO))

	color_info := sdl3.GPUColorTargetInfo{
		texture     = swapchain_tex,
		clear_color = sdl3.FColor{0.04, 0.04, 0.08, 1.0},
		load_op     = .CLEAR,
		store_op    = .STORE,
	}
	pass := sdl3.BeginGPURenderPass(cmd, &color_info, 1, nil)
	sdl3.BindGPUGraphicsPipeline(pass, r.graphics_pipeline)

	// storage: pos(0), color(1), size(2) — gl_VertexIndex로 인덱싱
	bufs := [3]^sdl3.GPUBuffer{ps.pos, ps.color, ps.size}
	sdl3.BindGPUVertexStorageBuffers(pass, 0, raw_data(&bufs), 3)
	sdl3.DrawGPUPrimitives(pass, u32(ps.active), 1, 0, 0)

	sdl3.EndGPURenderPass(pass)
}
