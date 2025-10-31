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
    int width;
    int height;
    int tex_id;
};

layout(binding=0) readonly buffer ssbo {
    sb_vertex vtx[];
};

out vec3 uv;

void main() {
    vec4 base_pos = vec4(vtx[gl_VertexIndex].x, vtx[gl_VertexIndex].y, vtx[gl_VertexIndex].z,  1.0);
    gl_Position = mvp * (base_pos + chunk_pos);
    vec2 texcoord0 = vec2(vtx[gl_VertexIndex].u * vtx[gl_VertexIndex].width, vtx[gl_VertexIndex].v * vtx[gl_VertexIndex].height);
    uv = vec3(texcoord0, float(vtx[gl_VertexIndex].tex_id));
}
@end

@fs fs
layout(binding=1) uniform texture2DArray tex;
layout(binding=1) uniform sampler smp;

in vec3 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2DArray(tex, smp), uv);
}
@end

@program chunk vs fs