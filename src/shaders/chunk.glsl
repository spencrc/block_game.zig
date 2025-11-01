@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
    vec3 chunk_pos;
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
    vec3 base_pos = vec3(vtx[gl_VertexIndex].x, vtx[gl_VertexIndex].y, vtx[gl_VertexIndex].z);
    vec3 world_pos = base_pos + chunk_pos;
    gl_Position = mvp * vec4(world_pos, 1.0);
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
    vec2 dudx = dFdx(uv.xy);
    vec2 dudy = dFdy(uv.xy);

    float rho = max(
        length(dudx) * 16,
        length(dudy) * 16
    );

    float mip = max(log2(rho), 0.0);
    float levelsize = 16 / exp2(mip);
    vec2 uv_texspace = uv.xy * levelsize;
    vec2 seam = floor(uv_texspace + 0.5);
    uv_texspace = (uv_texspace-seam)/fwidth(uv_texspace)+seam;
    uv_texspace = clamp(uv_texspace, seam - 0.5, seam + 0.5);
    frag_color = texture(sampler2DArray(tex, smp), vec3(uv_texspace/levelsize, uv.z));
}
@end

@program chunk vs fs