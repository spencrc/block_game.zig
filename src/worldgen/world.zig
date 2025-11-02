const World = @This();

const std = @import("std");

const Chunk = @import("chunk.zig");
const vec3 = @import("../math.zig").Vec3;
const Material = @import("block.zig").Material;

const CHUNK_SIZE = @import("../constants.zig").CHUNK_SIZE;

allocator: std.mem.Allocator,
m: std.Thread.Mutex,
chunks: std.AutoHashMapUnmanaged([3]i32, *Chunk),

pub fn init(allocator: std.mem.Allocator) World {
    return .{
        .allocator = allocator,
        .m = std.Thread.Mutex{},
        .chunks = .empty,
    };
}

pub fn deinit(self: *World) void {
    var iter = self.chunks.valueIterator();
    while (iter.next()) |chunk_obj_ptr| {
        self.allocator.destroy(chunk_obj_ptr.*);
    }
    self.chunks.deinit(self.allocator);
}

pub fn generate_chunk(self: *World, x: i32, y: i32, z: i32) void {
    const chunk_obj = self.allocator.create(Chunk) catch @panic("out of memory error!");
    chunk_obj.* = Chunk.init(x, y, z);

    self.m.lock();
    self.chunks.put(self.allocator, .{ x, y, z }, chunk_obj) catch @panic("out of memory error!");
    self.m.unlock();
}

pub fn generate_chunk_mesh(self: *World, cx: i32, cy: i32, cz: i32) void {
    const chunk = self.get_chunk(cx, cy, cz);
    if (chunk == null)
        return;
    if (chunk.?.all_air)
        return;
    const x = chunk.?.pos[0];
    const y = chunk.?.pos[1];
    const z = chunk.?.pos[2];
    const neighbours: [6]?*Chunk = .{
        self.get_chunk(x - 1, y, z),
        self.get_chunk(x, y - 1, z),
        self.get_chunk(x, y, z - 1),
        self.get_chunk(x + 1, y, z),
        self.get_chunk(x, y + 1, z),
        self.get_chunk(x, y, z + 1),
    };
    chunk.?.greedy_mesh(self.allocator, neighbours, &self.m);
}

pub fn get_chunk(self: *World, x: i32, y: i32, z: i32) ?*Chunk {
    return self.chunks.get(.{ x, y, z });
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
