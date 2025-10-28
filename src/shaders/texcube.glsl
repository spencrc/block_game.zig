#pragma sokol @header const m = @import("../math.zig")
#pragma sokol @ctype mat4 m.Mat4

#pragma sokol @vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
};

in vec4 pos;
in vec2 texcoord0;
in vec4 instance_pos;

out vec2 uv;

void main() {
    gl_Position = mvp * (pos + instance_pos);
    uv = texcoord0;
}
#pragma sokol @end

#pragma sokol @fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(tex, smp), uv);
}
#pragma sokol @end

#pragma sokol @program texcube vs fs