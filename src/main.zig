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
const Chunk = @import("worldgen/chunk.zig");

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
        .buffer_pool_size = RENDER_DISTANCE_LIMIT * RENDER_DISTANCE_LIMIT * 5,
        .view_pool_size = RENDER_DISTANCE_LIMIT * RENDER_DISTANCE_LIMIT * 5 + 1,
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    //initialize ztbi
    zstbi.init(allocator);
    defer zstbi.deinit();

    const texture_names = [_][:0]const u8{
        "textures/default.png",
        "textures/dirt.png",
        "textures/cobblestone.png",
        "textures/water.png",
        "textures/grass.png",
        "textures/sand.png",
        "textures/snow.png",
    };
    var textures: [7][5]Image = undefined;
    defer for (&textures) |*t|
        for (t) |*i|
            i.deinit();
    for (texture_names, 0..) |name, i| {
        generate_images(name, &textures[i]) catch @panic("texture load failed");
    }

    const mip0: [7][16][16][4]u8 = fill_mip(16, 16, 0, textures);
    const mip1: [7][8][8][4]u8 = fill_mip(8, 8, 1, textures);
    const mip2: [7][4][4][4]u8 = fill_mip(4, 4, 2, textures);
    const mip3: [7][2][2][4]u8 = fill_mip(2, 2, 3, textures);
    const mip4: [7][1][1][4]u8 = fill_mip(1, 1, 4, textures);

    //TODO: make views a global somewhere and transition to using a texture atlas. current implementation only supports one texture (which is bad)
    view = sg.makeView(.{
        .texture = .{
            .image = sg.makeImage(.{
                .type = .ARRAY,
                .width = 16,
                .height = 16,
                .num_slices = 7,
                .num_mipmaps = 5,
                .pixel_format = .RGBA8,
                .data = init: {
                    var data = sg.ImageData{};
                    data.mip_levels[0] = sg.asRange(&mip0);
                    data.mip_levels[1] = sg.asRange(&mip1);
                    data.mip_levels[2] = sg.asRange(&mip2);
                    data.mip_levels[3] = sg.asRange(&mip3);
                    data.mip_levels[4] = sg.asRange(&mip4);
                    break :init data;
                },
            }),
        },
    });

    //TODO: make samplers a global somewhere!
    sampler = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .mipmap_filter = .LINEAR,
    });

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

    //make the world!
    world = World.init(allocator);

    var chunks: std.ArrayList(*Chunk) = .empty;
    defer chunks.deinit(allocator);
    var total_time: u64 = 0;
    var n: f64 = 0.0;
    for (0..RENDER_DISTANCE_LIMIT) |i| {
        for (0..RENDER_DISTANCE_LIMIT) |j| {
            for (0..5) |k| {
                var timer = std.time.Timer.start() catch @panic("timer failed!");
                const chunk = world.generate_chunk(@intCast(i), @intCast(k), @intCast(j)) catch @panic("chunk generation fail!");
                total_time += timer.read();
                n += 1.0;
                chunks.append(allocator, chunk) catch @panic("fuck");
            }
        }
    }
    std.debug.print("total time taken: {d} ms\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000});
    std.debug.print("average time taken: {d} ms\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000 / n});
    n = 0;
    total_time = 0;
    for (chunks.items) |chunk| {
        if (chunk.all_air)
            continue;
        const x = chunk.pos[0];
        const y = chunk.pos[1];
        const z = chunk.pos[2];
        const neighbours: [6]?*Chunk = .{
            world.get_chunk(x - 1, y, z),
            world.get_chunk(x, y - 1, z),
            world.get_chunk(x, y, z - 1),
            world.get_chunk(x + 1, y, z),
            world.get_chunk(x, y + 1, z),
            world.get_chunk(x, y, z + 1),
        };
        var timer = std.time.Timer.start() catch @panic("timer failed!");
        chunk.greedy_mesh(allocator, neighbours);
        total_time += timer.read();
        n += 1.0;
    }
    std.debug.print("total time taken: {d} ms\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000});
    std.debug.print("average time taken: {d} ms\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000 / n});
}

fn generate_images(name: [:0]const u8, arr: *[5]Image) !void {
    arr[0] = try Image.loadFromFile(name, 4);

    var w: u32 = 16;
    var h: u32 = 16;

    for (1..5) |i| {
        w /= 2;
        h /= 2;

        arr[i] = arr[i - 1].resize(w, h);
    }
}

fn fill_mip(comptime w: usize, comptime h: usize, level: usize, textures: [7][5]Image) [7][w][h][4]u8 {
    var pixels: [7][w][h][4]u8 = undefined;

    for (0..7) |i| {
        @memcpy(@as([*]u8, @ptrCast(&pixels[i]))[0 .. w * h * 4], textures[i][level].data);
    }

    return pixels;
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
            for (0..5) |k| {
                const chunk = world.get_chunk(@intCast(i), @intCast(k), @intCast(j));
                if (chunk.?.all_air)
                    continue;
                bind.views[shd.VIEW_ssbo] = chunk.?.ssbo_view; //includes vertices via ssbo
                sg.applyBindings(bind);
                sg.applyUniforms(shd.UB_vs_params, sg.asRange(&shd.VsParams{
                    .mvp = view_proj,
                    .chunk_pos = .{
                        @floatFromInt(chunk.?.pos[0] * CHUNK_SIZE),
                        @floatFromInt(chunk.?.pos[1] * CHUNK_SIZE),
                        @floatFromInt(chunk.?.pos[2] * CHUNK_SIZE),
                    },
                }));
                sg.draw(0, chunk.?.vertex_count, 1);
            }
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
        .width = 1280,
        .height = 720,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
