@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
    vec4 chunk_pos;
};

struct sb_vertex {
    float x;
    float y;
    float z;
    float u;
    float v;
};

layout(binding=0) readonly buffer ssbo {
    sb_vertex vtx[];
};

out vec2 uv;

void main() {
    vec4 base_pos = vec4(vtx[gl_VertexIndex].x, vtx[gl_VertexIndex].y, vtx[gl_VertexIndex].z,  1.0);
    gl_Position = mvp * (base_pos + chunk_pos);
    uv = vec2(vtx[gl_VertexIndex].u, vtx[gl_VertexIndex].v);
}
@end

@fs fs
layout(binding=1) uniform texture2D tex;
layout(binding=1) uniform sampler smp;

in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(tex, smp), uv);
}
@end

@program chunk vs fs