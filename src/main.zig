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
const Chunk = @import("chunk.zig");

var vertex_buffer: sg.Buffer = undefined;
var instance_buffer: sg.Buffer = undefined;
var index_buffer: sg.Buffer = undefined;
var view: sg.View = undefined;
var sampler: sg.Sampler = undefined;
var pip: sg.Pipeline = .{};
var pass_action: sg.PassAction = .{};
var cam: Camera = Camera.init();
var chunk: Chunk = undefined;

export fn init() void {
    // initialize sokol-gfx
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    //initialize appropiate allocator (TODO: move this to somewhere better T-T)
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator: std.mem.Allocator = allocator: {
        if (builtin.os.tag == .wasi) break :allocator std.heap.wasm_allocator;
        break :allocator switch (builtin.mode) {
            .Debug, .ReleaseSafe => debug_allocator.allocator(),
            .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
        };
    };
    const is_debug: bool = allocator: {
        if (builtin.os.tag == .wasi) break :allocator false;
        break :allocator switch (builtin.mode) {
            .Debug, .ReleaseSafe => true,
            .ReleaseFast, .ReleaseSmall => false,
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    //make the chunk!
    chunk = Chunk.create();
    chunk.greedy_mesh();

    //TODO: make instance buffer be per chunk, and then set the binds in the frame loop so we can render multiple different chunks
    // instance_buffer = sg.makeBuffer(.{
    //     .data = sg.asRange(&chunk.instances),
    // });

    //initialize ztbi
    zstbi.init(allocator);
    defer zstbi.deinit();

    var img: Image = Image.loadFromFile("src/dirt.png", 4) catch @panic("failed to load image!");
    defer img.deinit();

    //need width to be i32, and for it to be clamped within [0, 16384] (16384 was picked as a reasonable max size, maybe overkill though)
    //const width: i32 = @intCast(@max(0, @min(img.width, 16384)));
    //const height: i32 = @intCast(@max(0, @min(img.height, 16384)));

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
        .layout = init: {
            var l = sg.VertexLayoutState{};

            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[shd.ATTR_chunk_pos] = .{ .format = .FLOAT3, .buffer_index = 0 };
            l.attrs[shd.ATTR_chunk_texcoord0] = .{ .format = .FLOAT2, .buffer_index = 0 };

            // l.buffers[1].stride = @sizeOf(InstanceData);
            // l.buffers[1].step_func = .PER_INSTANCE;
            // l.attrs[shd.ATTR_chunk_instance_pos] = .{ .format = .FLOAT3, .buffer_index = 1 };

            break :init l;
        },
        .index_type = .UINT16,
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
    const dt: f32 = @floatCast(sapp.frameDuration() * 60);

    if (!sapp.mouseLocked()) {
        cam.input = vec3.zero();
    }
    cam.update_camera(dt);
    cam.update_matricies(sapp.widthf(), sapp.heightf());

    const view_proj = mat4.mul(cam.proj, cam.view);

    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(pip);

    var bind: sg.Bindings = .{};
    bind.vertex_buffers[0] = chunk.vertex_buffer;
    //bind.vertex_buffers[1] = chunk.instance_buffer;
    bind.index_buffer = chunk.index_buffer;
    bind.views[shd.VIEW_tex] = view;
    bind.samplers[shd.SMP_smp] = sampler;

    sg.applyBindings(bind);
    sg.applyUniforms(0, sg.asRange(&shd.VsParams{
        .mvp = view_proj,
    }));
    sg.draw(0, chunk.index_count, 1);
    sg.endPass();
    sg.commit();

    //std.debug.print("FPS: {d}\n", .{1.0 / sapp.frameDuration()});
}

export fn cleanup() void {
    sg.shutdown();
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
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
