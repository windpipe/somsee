#version 450

layout(local_size_x = 256) in;

// set=0: RW storage (BeginGPUComputePass bindings)
layout(set = 0, binding = 0) buffer Positions  { vec2 pos[]; };
layout(set = 0, binding = 1) buffer Velocities { vec2 vel[]; };

// set=1: uniform (PushGPUComputeUniformData slot=0)
layout(set = 1, binding = 0) uniform UBO {
    float bounds_x;
    float bounds_y;
    uint  count;
    float dt;
};

void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= count) return;

    vec2 p = pos[i];
    vec2 v = vel[i];

    p += v * dt;

    // 경계 반사
    if (p.x < 0.0)       { p.x = 0.0;       v.x =  abs(v.x); }
    if (p.x > bounds_x)  { p.x = bounds_x;  v.x = -abs(v.x); }
    if (p.y < 0.0)       { p.y = 0.0;       v.y =  abs(v.y); }
    if (p.y > bounds_y)  { p.y = bounds_y;  v.y = -abs(v.y); }

    pos[i] = p;
    vel[i] = v;
}
