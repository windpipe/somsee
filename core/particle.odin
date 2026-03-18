package somsee

import "vendor:sdl3"
import "core:fmt"
import "core:math/rand"

MAX_PARTICLES      :: 1_000_000
COMPUTE_GROUP_SIZE :: 256

// SoA 레이아웃: 접근 패턴별 분리 → GPU 캐시 효율 최대화
Particle_System :: struct {
	pos:    ^sdl3.GPUBuffer, // [MAX_PARTICLES][2]f32 — compute RW + render R
	vel:    ^sdl3.GPUBuffer, // [MAX_PARTICLES][2]f32 — compute RW
	color:  ^sdl3.GPUBuffer, // [MAX_PARTICLES][4]f32 — render R (정적)
	size:   ^sdl3.GPUBuffer, // [MAX_PARTICLES]f32    — render R (정적)
	active: int,
}

// Compute shader uniform  (set=2, binding=0)
Compute_UBO :: struct {
	bounds_x: f32,
	bounds_y: f32,
	count:    u32,
	dt:       f32,
}

// Vertex shader uniform (set=1, binding=0)
Screen_UBO :: struct {
	w: f32,
	h: f32,
}

Particle_System_Create :: proc(
	device:   ^sdl3.GPUDevice,
	active:   int,
	bounds_x: f32,
	bounds_y: f32,
) -> (ps: Particle_System, ok: bool) {
	pos_size   := u32(MAX_PARTICLES * size_of([2]f32))
	vel_size   := u32(MAX_PARTICLES * size_of([2]f32))
	color_size := u32(MAX_PARTICLES * size_of([4]f32))
	sz_size    := u32(MAX_PARTICLES * size_of(f32))
	total_size := pos_size + vel_size + color_size + sz_size

	ps.pos = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage = {.COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE, .GRAPHICS_STORAGE_READ},
		size  = pos_size,
	})
	ps.vel = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage = {.COMPUTE_STORAGE_READ, .COMPUTE_STORAGE_WRITE},
		size  = vel_size,
	})
	ps.color = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage = {.GRAPHICS_STORAGE_READ},
		size  = color_size,
	})
	ps.size = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage = {.GRAPHICS_STORAGE_READ},
		size  = sz_size,
	})
	if ps.pos == nil || ps.vel == nil || ps.color == nil || ps.size == nil {
		fmt.printf("CreateGPUBuffer failed: %s\n", sdl3.GetError())
		Particle_System_Destroy(device, &ps)
		return
	}

	transfer := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{
		usage = .UPLOAD,
		size  = total_size,
	})
	if transfer == nil {
		fmt.printf("CreateGPUTransferBuffer failed: %s\n", sdl3.GetError())
		Particle_System_Destroy(device, &ps)
		return
	}
	defer sdl3.ReleaseGPUTransferBuffer(device, transfer)

	base       := uintptr(sdl3.MapGPUTransferBuffer(device, transfer, false))
	positions  := ([^][2]f32)(rawptr(base))
	velocities := ([^][2]f32)(rawptr(base + uintptr(pos_size)))
	colors     := ([^][4]f32)(rawptr(base + uintptr(pos_size + vel_size)))
	sizes      := ([^]f32)(rawptr(base + uintptr(pos_size + vel_size + color_size)))

	for i in 0 ..< MAX_PARTICLES {
		positions[i]  = {rand.float32() * bounds_x, rand.float32() * bounds_y}
		velocities[i] = {(rand.float32() - 0.5) * 600.0, (rand.float32() - 0.5) * 600.0}
		colors[i]     = {rand.float32() * 0.6 + 0.4, rand.float32() * 0.6 + 0.4, rand.float32() * 0.6 + 0.4, 0.85}
		sizes[i]      = rand.float32() * 3.0 + 1.0
	}
	sdl3.UnmapGPUTransferBuffer(device, transfer)

	cmd := sdl3.AcquireGPUCommandBuffer(device)
	cp  := sdl3.BeginGPUCopyPass(cmd)

	offset: u32 = 0
	sdl3.UploadToGPUBuffer(cp,
		sdl3.GPUTransferBufferLocation{transfer_buffer = transfer, offset = offset},
		sdl3.GPUBufferRegion{buffer = ps.pos, offset = 0, size = pos_size}, false)
	offset += pos_size
	sdl3.UploadToGPUBuffer(cp,
		sdl3.GPUTransferBufferLocation{transfer_buffer = transfer, offset = offset},
		sdl3.GPUBufferRegion{buffer = ps.vel, offset = 0, size = vel_size}, false)
	offset += vel_size
	sdl3.UploadToGPUBuffer(cp,
		sdl3.GPUTransferBufferLocation{transfer_buffer = transfer, offset = offset},
		sdl3.GPUBufferRegion{buffer = ps.color, offset = 0, size = color_size}, false)
	offset += color_size
	sdl3.UploadToGPUBuffer(cp,
		sdl3.GPUTransferBufferLocation{transfer_buffer = transfer, offset = offset},
		sdl3.GPUBufferRegion{buffer = ps.size, offset = 0, size = sz_size}, false)

	sdl3.EndGPUCopyPass(cp)
	_ = sdl3.SubmitGPUCommandBuffer(cmd)

	ps.active = active
	ok = true
	return
}

Particle_System_Destroy :: proc(device: ^sdl3.GPUDevice, ps: ^Particle_System) {
	if ps.pos   != nil { sdl3.ReleaseGPUBuffer(device, ps.pos);   ps.pos   = nil }
	if ps.vel   != nil { sdl3.ReleaseGPUBuffer(device, ps.vel);   ps.vel   = nil }
	if ps.color != nil { sdl3.ReleaseGPUBuffer(device, ps.color); ps.color = nil }
	if ps.size  != nil { sdl3.ReleaseGPUBuffer(device, ps.size);  ps.size  = nil }
}

// Compute pass: GPU에서 파티클 물리 업데이트
Particle_Compute :: proc(
	cmd:      ^sdl3.GPUCommandBuffer,
	ps:       ^Particle_System,
	pipeline: ^sdl3.GPUComputePipeline,
	dt:       f32,
	bounds_x: f32,
	bounds_y: f32,
) {
	ubo := Compute_UBO{
		bounds_x = bounds_x,
		bounds_y = bounds_y,
		count    = u32(ps.active),
		dt       = dt,
	}
	sdl3.PushGPUComputeUniformData(cmd, 0, &ubo, size_of(Compute_UBO))

	bindings := [2]sdl3.GPUStorageBufferReadWriteBinding{
		{buffer = ps.pos},
		{buffer = ps.vel},
	}
	pass   := sdl3.BeginGPUComputePass(cmd, nil, 0, raw_data(&bindings), 2)
	groups := u32((ps.active + COMPUTE_GROUP_SIZE - 1) / COMPUTE_GROUP_SIZE)
	sdl3.BindGPUComputePipeline(pass, pipeline)
	sdl3.DispatchGPUCompute(pass, groups, 1, 1)
	sdl3.EndGPUComputePass(pass)
}
