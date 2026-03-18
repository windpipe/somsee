#version 450

layout(location = 0) in  vec4 frag_color;
layout(location = 0) out vec4 out_color;

void main() {
    // gl_PointCoord: [0,1]^2, 중심=(0.5, 0.5)
    vec2  coord = gl_PointCoord - vec2(0.5);
    float dist  = length(coord);
    if (dist > 0.5) discard;

    // 중심→가장자리 부드러운 페이드
    float alpha = frag_color.a * (1.0 - dist * 2.0);
    out_color   = vec4(frag_color.rgb, alpha);
}
