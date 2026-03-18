#version 450

// set=0: readonly storage (BindGPUVertexStorageBuffers)
layout(set = 0, binding = 0) readonly buffer Positions { vec2 pos[];   };
layout(set = 0, binding = 1) readonly buffer Colors    { vec4 color[]; };
layout(set = 0, binding = 2) readonly buffer Sizes     { float sz[];   };

// set=1: uniform (PushGPUVertexUniformData slot=0)
layout(set = 1, binding = 0) uniform Screen {
    float w;
    float h;
};

layout(location = 0) out vec4 frag_color;

void main() {
    uint  i   = gl_VertexIndex;
    vec2  p   = pos[i];

    // [0, screen] → NDC [-1, 1]
    vec2 ndc = (p / vec2(w, h)) * 2.0 - 1.0;

    gl_Position  = vec4(ndc, 0.0, 1.0);
    gl_PointSize = sz[i];
    frag_color   = color[i];
}
