const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const vec3 = @import("math.zig").Vec3;
const mat4 = @import("math.zig").Mat4;
const math = std.math;
const shd = @import("shaders/triangle.glsl.zig");

const Camera = @import("camera.zig");

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};
    var vs_params: shd.VsParams = undefined;
    var rx: f32 = 0.0;
    var ry: f32 = 0.0;
    //const view: mat4 = mat4.lookat(.{ .x = 0.0, .y = 0, .z = 5 }, vec3.zero(), vec3.up());
    var cam: Camera = Camera.init();
    var mouse_captured: bool = false;
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
            // positions        colors
            -1.0, -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
            1.0,  -1.0, -1.0, 1.0, 0.0, 0.0, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,
            -1.0, 1.0,  -1.0, 1.0, 0.0, 0.0, 1.0,

            -1.0, -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
            1.0,  -1.0, 1.0,  0.0, 1.0, 0.0, 1.0,
            1.0,  1.0,  1.0,  0.0, 1.0, 0.0, 1.0,
            -1.0, 1.0,  1.0,  0.0, 1.0, 0.0, 1.0,

            -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0,
            -1.0, 1.0,  -1.0, 0.0, 0.0, 1.0, 1.0,
            -1.0, 1.0,  1.0,  0.0, 0.0, 1.0, 1.0,
            -1.0, -1.0, 1.0,  0.0, 0.0, 1.0, 1.0,

            1.0,  -1.0, -1.0, 1.0, 0.5, 0.0, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.5, 0.0, 1.0,
            1.0,  1.0,  1.0,  1.0, 0.5, 0.0, 1.0,
            1.0,  -1.0, 1.0,  1.0, 0.5, 0.0, 1.0,

            -1.0, -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,
            -1.0, -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
            1.0,  -1.0, 1.0,  0.0, 0.5, 1.0, 1.0,
            1.0,  -1.0, -1.0, 0.0, 0.5, 1.0, 1.0,

            -1.0, 1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
            -1.0, 1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
            1.0,  1.0,  1.0,  1.0, 0.0, 0.5, 1.0,
            1.0,  1.0,  -1.0, 1.0, 0.0, 0.5, 1.0,
        }),
    });

    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            0,  1,  2,  0,  2,  3,
            6,  5,  4,  7,  6,  4,
            8,  9,  10, 8,  10, 11,
            14, 13, 12, 15, 14, 12,
            16, 17, 18, 16, 18, 19,
            22, 21, 20, 23, 22, 20,
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
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .cull_mode = .BACK,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.5, .b = 0.75, .a = 1 },
    };
}

export fn frame() void {
    const dt: f32 = @floatCast(sapp.frameDuration() * 60);

    if (state.mouse_captured == false) {
        state.cam.input = vec3.zero();
    }
    //state.cam.update_camera(dt);
    state.cam.update_matricies(sapp.widthf(), sapp.heightf());

    const view_proj = mat4.mul(state.cam.proj, state.cam.view);

    state.rx += 1.0 * dt;
    state.ry += 1.0 * dt;

    const rxm = mat4.rotate(state.rx, .{ .x = 1, .y = 0, .z = 0 });
    const rym = mat4.rotate(state.ry, .{ .x = 0, .y = 1, .z = 0 });
    const rm = mat4.mul(rxm, rym);
    state.vs_params.mvp = mat4.mul(view_proj, rm);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(0, sg.asRange(&state.vs_params));
    sg.draw(0, 36, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    if (ev.*.type == .MOUSE_DOWN) {
        if (ev.*.mouse_button == .LEFT) {
            state.mouse_captured = true;
            sapp.lockMouse(true);
        }
    } else if (ev.*.type == .MOUSE_UP) {
        if (ev.*.mouse_button == .LEFT) {
            state.mouse_captured = false;
            sapp.lockMouse(false);
        }
    } else if (ev.*.type == .MOUSE_MOVE) {
        if (state.mouse_captured == false) {
            return;
        }

        const dx = ev.*.mouse_dx;
        const dy = ev.*.mouse_dy;
        const sens = 0.004;

        state.cam.rotation.x -= dx * sens;
        state.cam.rotation.y += dy * sens;

        state.cam.rotation.y = @max(-math.tau / 4.0, @min(math.tau / 4.0, state.cam.rotation.y));
    } else if (ev.*.type == .KEY_DOWN) {
        switch (ev.*.key_code) {
            .D => state.cam.input.x += 1,
            .A => state.cam.input.x -= 1,
            .W => state.cam.input.z -= 1,
            .S => state.cam.input.z += 1,

            .Q => state.cam.input.y += 1,
            .E => state.cam.input.y -= 1,

            else => {},
        }
    } else if (ev.*.type == .KEY_UP) {
        switch (ev.*.key_code) {
            .D => state.cam.input.x -= 1,
            .A => state.cam.input.x += 1,
            .W => state.cam.input.z += 1,
            .S => state.cam.input.z -= 1,

            .Q => state.cam.input.y -= 1,
            .E => state.cam.input.y += 1,

            else => {},
        }
    }
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "sokol-zig... but it's a rectangle (spinning :D)!",
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
