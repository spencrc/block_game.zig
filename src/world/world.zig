const World = @This();

const std = @import("std");

const Chunk = @import("../chunk.zig");
const vec3 = @import("../math.zig");

allocator: std.mem.Allocator,
chunks: std.AutoHashMap(vec3, Chunk),

pub fn init(allocator: std.mem.Allocator) World {
    return .{
        .allocator = allocator,
        .chunks = std.AutoHashMap(vec3, Chunk).init(allocator),
    };
}

pub fn deinit(self: *World) void {
    self.chunks.deinit(self.allocator);
}

//pub fn generate_chunk(self: *World) Chunk {}
