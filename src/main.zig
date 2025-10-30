const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const vec3 = @import("math.zig").Vec3;
const mat4 = @import("math.zig").Mat4;
const shd = @import("shaders/chunk.glsl.zig");
const zstbi = @import("zstbi");
const constants = @import("constants.zig");

const Image = zstbi.Image;
const Camera = @import("camera.zig");
const World = @import("worldgen/world.zig");

var view: sg.View = undefined;
var sampler: sg.Sampler = undefined;
var pip: sg.Pipeline = .{};
var pass_action: sg.PassAction = .{};
var cam: Camera = Camera.init();
var world: World = undefined;
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
const allocator: std.mem.Allocator = allocator: {
    break :allocator switch (builtin.mode) {
        .Debug, .ReleaseSafe => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };
};
const is_debug: bool = allocator: {
    break :allocator switch (builtin.mode) {
        .Debug, .ReleaseSafe => true,
        .ReleaseFast, .ReleaseSmall => false,
    };
};

const RENDER_DISTANCE_LIMIT = constants.RENDER_DISTANCE_LIMIT;
const CHUNK_SIZE = constants.CHUNK_SIZE;

export fn init() void {
    // initialize sokol-gfx
    sg.setup(.{
        .buffer_pool_size = RENDER_DISTANCE_LIMIT * RENDER_DISTANCE_LIMIT,
        .view_pool_size = RENDER_DISTANCE_LIMIT * RENDER_DISTANCE_LIMIT + 1,
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    //make the world!
    world = World.init(allocator);
    for (0..RENDER_DISTANCE_LIMIT) |i| {
        for (0..RENDER_DISTANCE_LIMIT) |j| {
            const chunk = world.generate_chunk(@intCast(i), 0, @intCast(j)) catch @panic("chunk generation fail!");
            chunk.greedy_mesh(allocator);
        }
    }

    //initialize ztbi
    zstbi.init(allocator);
    defer zstbi.deinit();

    var img: Image = Image.loadFromFile("textures/dirt.png", 4) catch @panic("failed to load image!");
    defer img.deinit();

    //TODO: make views a global somewhere and transition to using a texture atlas. current implementation only supports one texture (which is bad)
    view = sg.makeView(.{
        .texture = .{
            .image = sg.makeImage(.{
                .width = 16,
                .height = 16,
                .pixel_format = .RGBA8,
                .data = init: {
                    var data = sg.ImageData{};
                    data.mip_levels[0] = sg.asRange(img.data);
                    break :init data;
                },
            }),
        },
    });

    //TODO: make samplers a global somewhere!
    sampler = sg.makeSampler(.{});

    pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.chunkShaderDesc(sg.queryBackend())),
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .cull_mode = .BACK,
    });

    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.5, .b = 0.75, .a = 1 },
    };
}

var frame_count: f32 = 0;
var time_elapsed: f32 = 0.0;
export fn frame() void {
    const dt: f32 = @floatCast(sapp.frameDuration());

    if (!sapp.mouseLocked()) {
        cam.input = vec3.zero();
    }
    cam.update_camera(dt);
    cam.update_matricies(sapp.widthf(), sapp.heightf());

    const view_proj = mat4.mul(cam.proj, cam.view);

    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(pip);

    var bind: sg.Bindings = .{};
    bind.views[shd.VIEW_tex] = view;
    bind.samplers[shd.SMP_smp] = sampler;

    //TODO: there is a hard cap on number of chunks due to buffer pool being finite. need to change how buffers work. looking into sg_buffer_append
    for (0..RENDER_DISTANCE_LIMIT) |i| {
        for (0..RENDER_DISTANCE_LIMIT) |j| {
            const chunk = world.get_chunk(@intCast(i), 0, @intCast(j));
            if (chunk == null)
                continue;
            bind.views[shd.VIEW_ssbo] = chunk.?.ssbo_view; //includes vertices via ssbo
            sg.applyBindings(bind);
            sg.applyUniforms(shd.UB_vs_params, sg.asRange(&shd.VsParams{
                .mvp = view_proj,
                .chunk_pos = .{
                    @floatFromInt(chunk.?.pos[0] * CHUNK_SIZE),
                    @floatFromInt(chunk.?.pos[1] * CHUNK_SIZE),
                    @floatFromInt(chunk.?.pos[2] * CHUNK_SIZE),
                    1.0,
                },
            }));
            sg.draw(0, chunk.?.vertex_count, 1);
        }
    }
    sg.endPass();
    sg.commit();

    time_elapsed += dt;
    frame_count += 1.0;
    if (time_elapsed >= 1) {
        const fps = frame_count / time_elapsed;
        std.debug.print("FPS: {d}\n", .{fps});
        time_elapsed = 0.0;
        frame_count = 0.0;
    }
}

export fn cleanup() void {
    sg.shutdown();
    world.deinit();
    if (is_debug)
        _ = debug_allocator.deinit();
}

export fn event(ev: [*c]const sapp.Event) void {
    if (ev.*.type == .MOUSE_DOWN) {
        if (ev.*.mouse_button == .RIGHT)
            sapp.lockMouse(true);
    } else if (ev.*.type == .MOUSE_UP) {
        if (ev.*.mouse_button == .RIGHT)
            sapp.lockMouse(false);
    } else if (ev.*.type == .MOUSE_MOVE) {
        cam.handle_mouse_movement(sapp.mouseLocked(), ev.*.mouse_dx, ev.*.mouse_dy);
    } else if (ev.*.type == .KEY_DOWN) {
        switch (ev.*.key_code) {
            .D => cam.input.x = 1,
            .A => cam.input.x = -1,
            .W => cam.input.y = 1,
            .S => cam.input.y = -1,

            else => {},
        }
    } else if (ev.*.type == .KEY_UP) {
        switch (ev.*.key_code) {
            .D => cam.input.x = 0,
            .A => cam.input.x = 0,
            .W => cam.input.y = 0,
            .S => cam.input.y = 0,

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
        .window_title = "sokol-zig... but it's a cube chunk!",
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
