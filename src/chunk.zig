const Chunk = @This();

const sokol = @import("sokol");
const sg = sokol.gfx;

const InstanceData = @import("constants.zig").InstanceData;

const CHUNK_SIZE = 16;
const MAX_CUBES_PER_CHUNK = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

instance_buffer: sg.Buffer,
count: u32,

pub fn create() Chunk {
    var instances: [MAX_CUBES_PER_CHUNK]InstanceData = undefined;

    var count: u32 = 0;
    for (0..CHUNK_SIZE) |cx| {
        for (0..CHUNK_SIZE) |cy| {
            for (0..CHUNK_SIZE) |cz| {
                instances[count] = InstanceData{ .pos = .{ .x = @floatFromInt(cx), .y = @floatFromInt(cy), .z = @floatFromInt(cz) } };
                count += 1;
            }
        }
    }

    return .{
        .instance_buffer = sg.makeBuffer(.{
            .data = sg.asRange(&instances),
        }),
        .count = count,
    };
}
