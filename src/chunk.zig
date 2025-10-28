const Chunk = @This();

const InstanceData = @import("types.zig").InstanceData;
const Vertex = @import("types.zig").Vertex;
const vec3 = @import("math.zig").Vec3;

const CHUNK_SIZE = 16;
const MAX_CUBES_PER_CHUNK = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

instances: [MAX_CUBES_PER_CHUNK]InstanceData,
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
        .instances = instances,
        .count = count,
    };
}
