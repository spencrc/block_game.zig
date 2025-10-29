const World = @This();

const std = @import("std");

const Chunk = @import("chunk.zig");
const vec3 = @import("../math.zig").Vec3;

allocator: std.mem.Allocator,
chunks: std.AutoArrayHashMapUnmanaged([3]i32, Chunk) = .empty,

pub fn init(allocator: std.mem.Allocator) World {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *World) void {
    self.chunks.deinit(self.allocator);
}

pub fn generate_chunk(self: *World, x: i32, y: i32, z: i32) !*Chunk {
    const chunk = Chunk.init(x, y, z);
    try self.chunks.put(self.allocator, .{ x, y, z }, chunk);
    return self.chunks.getPtr(.{ x, y, z }).?; //can't be null, since we just put it there
}

pub fn get_chunk(self: *World, x: i32, y: i32, z: i32) ?Chunk {
    return self.chunks.get(.{ x, y, z });
}

//TODO: move is_block_at function to here. shouldn't be in chunk
