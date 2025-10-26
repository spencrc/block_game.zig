const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const vec3 = @import("math.zig").Vec3;
const mat4 = @import("math.zig").Mat4;
const shd = @import("shaders/triangle.glsl.zig");

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var vs_params: shd.VsParams = undefined;
    var rx: f32 = 0.0;
    var ry: f32 = 0.0;
    const view: mat4 = mat4.lookat(.{ .x = 0.0, .y = 1.5, .z = 6.0 }, vec3.zero(), vec3.up());
};

export fn init() void {
    // initialize sokol-gfx
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // create vertex buffer with triangle vertices
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            // positions         colors
            -0.5, 0.5,  0, 1.0, 0.0, 0.0, 1.0,
            0.5,  0.5,  0, 0.0, 0.0, 0.0, 1.0,
            -0.5, -0.5, 0, 0.0, 0.0, 1.0, 1.0,
            0.5,  -0.5, 0, 0.0, 1.0, 0.0, 1.0,
        }),
    });

    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            0, 1, 2,
            2, 1, 3,
        }),
    });

    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.triangleShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_triangle_position].format = .FLOAT3; //3 coordinates used in position vectors
            l.attrs[shd.ATTR_triangle_color0].format = .FLOAT4; //4 coordinates used in colour vectors
            break :init l;
        },
        .index_type = .UINT16,
    });
}

export fn frame() void {
    const proj = mat4.persp(90.0, sapp.widthf() / sapp.heightf(), 0.1, 500);
    const view_proj = mat4.mul(proj, state.view);

    const dt: f32 = @floatCast(sapp.frameDuration() * 60);

    state.rx += 1.0 * dt;
    state.ry += 1.0 * dt;

    const rxm = mat4.rotate(state.rx, .{ .x = 1, .y = 0, .z = 0 });
    const rym = mat4.rotate(state.ry, .{ .x = 0, .y = 1, .z = 0 });
    const rm = mat4.mul(rxm, rym);
    state.vs_params.mvp = mat4.mul(view_proj, rm);

    sg.beginPass(.{ .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(0, sg.asRange(&state.vs_params));
    sg.draw(0, 6, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .window_title = "sokol-zig... but it's a rectangle (spinning :D)!",
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
