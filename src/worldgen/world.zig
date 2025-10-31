const World = @This();

const std = @import("std");

const Chunk = @import("chunk.zig");
const vec3 = @import("../math.zig").Vec3;
const Material = @import("block.zig").Material;

const CHUNK_SIZE = @import("../constants.zig").CHUNK_SIZE;

allocator: std.mem.Allocator,
chunks: std.AutoHashMapUnmanaged([3]i32, Chunk) = .empty,

pub fn init(allocator: std.mem.Allocator) World {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *World) void {
    self.chunks.deinit(self.allocator);
}

pub fn generate_chunk(self: *World, x: i32, y: i32, z: i32) !*Chunk {
    const neighbours: [6]?*Chunk = .{
        self.get_chunk(x - 1, y, z),
        self.get_chunk(x, y - 1, z),
        self.get_chunk(x, y, z - 1),
        self.get_chunk(x + 1, y, z),
        self.get_chunk(x, y + 1, z),
        self.get_chunk(x, y, z + 1),
    };
    const chunk = Chunk.init(x, y, z, self, neighbours);
    try self.chunks.put(self.allocator, .{ x, y, z }, chunk);
    return self.chunks.getPtr(.{ x, y, z }).?; //can't be null, since we just put it there
}

pub fn get_chunk(self: *World, x: i32, y: i32, z: i32) ?*Chunk {
    return self.chunks.getPtr(.{ x, y, z });
}

pub fn get_block(self: *World, wx: i32, wy: i32, wz: i32) Material {
    const cx = @divFloor(wx, CHUNK_SIZE);
    const cy = @divFloor(wy, CHUNK_SIZE);
    const cz = @divFloor(wz, CHUNK_SIZE);
    const chunk = self.get_chunk(cx, cy, cz);
    if (chunk == null)
        return .AIR;

    const x: usize = @intCast(@rem(wx, CHUNK_SIZE));
    const y: usize = @intCast(@rem(wy, CHUNK_SIZE));
    const z: usize = @intCast(@rem(wz, CHUNK_SIZE));

    return chunk.?.blocks[x][y][z].material;
}
