const Chunk = @This();

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simplex = @import("noise.zig");

const World = @import("world.zig");
const Block = @import("block.zig");
const Material = Block.Material;

const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
    width: u32,
    height: u32,
    tex_id: u32,
};

const CHUNK_SIZE = @import("../constants.zig").CHUNK_SIZE;
const MAX_CUBES_PER_CHUNK = @import("../constants.zig").MAX_CUBES_PER_CHUNK;

pos: [3]i32,
blocks: [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]Block,
all_air: bool,
world: *World,
ssbo_view: sg.View = undefined, //if unitialized like this, it takes up just 4 bytes
vertex_count: u32 = 0,

pub fn init(cx: i32, cy: i32, cz: i32, world: *World) Chunk {
    var blocks: [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]Block = undefined;
    var all_air = true;

    for (0..CHUNK_SIZE) |x| {
        for (0..CHUNK_SIZE) |z| {
            const height: i32 = get_height(cx, @intCast(x), cz, @intCast(z));
            for (0..CHUNK_SIZE) |y| {
                const block_type = determine_block_type(@intCast(y), cy, height);
                blocks[x][y][z] = Block{ .material = block_type };
                if (block_type != .AIR)
                    all_air = false;
            }
        }
    }

    return .{
        .pos = .{ cx, cy, cz },
        .all_air = all_air,
        .blocks = blocks,
        .world = world,
    };
}

fn get_height(cx: i32, lx: i32, cz: i32, lz: i32) i32 {
    var amp: f64 = 1.0;
    var freq: f64 = 0.01;
    var noise: f64 = 0.0;
    for (0..8) |_| {
        noise += simplex.noise(
            @as(f64, @floatFromInt(cx * CHUNK_SIZE + lx)) * freq,
            2.0 * 0.001,
            @as(f64, @floatFromInt(cz * CHUNK_SIZE + lz)) * freq,
        ) * amp;

        freq *= 2.0;
        amp *= 0.5;
    }
    return @intFromFloat(((noise + 1.0)) * 50 + 30);
}

fn determine_block_type(y: i32, cy: i32, height: i32) Material {
    const world_y = cy * CHUNK_SIZE + y;
    if (world_y == height) {
        if (height <= 70) {
            return .SAND;
        } else if (height <= 95) {
            return .GRASS;
        } else {
            return .SNOW;
        }
    } else if (world_y == height - 1) {
        return .DIRT;
    } else if (world_y < height) {
        return .STONE;
    } else if (world_y <= 62) {
        return .WATER;
    } else {
        return .AIR;
    }
}

//Greedy mesher algorithm implementation in Zig. Works to generate a mesh for a chunk with minimals vertices for performance.
//Please see here for where the code originates, as it's not my own: https://gist.github.com/Vercidium/a3002bd083cce2bc854c9ff8f0118d33#file-greedyvoxelmeshing-L19
pub fn greedy_mesh(self: *Chunk, allocator: std.mem.Allocator, neighbours: [6]?*Chunk) void {
    var vertices_list = std.ArrayList(Vertex).empty;
    defer vertices_list.deinit(allocator);

    for (0..3) |d| {
        const u = (d + 1) % 3;
        const v = (d + 2) % 3;
        var pos: [3]i32 = .{ 0, 0, 0 };
        var q: [3]i32 = .{ 0, 0, 0 };

        var mask: [CHUNK_SIZE * CHUNK_SIZE]Material = undefined;
        var flip: [CHUNK_SIZE * CHUNK_SIZE]bool = undefined;
        q[d] = 1;
        pos[d] = -1;

        // Check each slice of the chunk one at a time
        while (pos[d] < CHUNK_SIZE) {
            var mask_index: usize = 0;
            for (0..CHUNK_SIZE) |i| {
                pos[v] = @intCast(i);
                for (0..CHUNK_SIZE) |j| {
                    pos[u] = @intCast(j);

                    // q determines the direction (X, Y or Z) that we are searching
                    // self.get_block(x,y,z) takes local map positions and returns the block type if it exists within the chunk, otherwise we look to self.world.get_block(x,y,z)
                    //   which returns the block type of any block in the world. If the block doesn't exist (i.e it's in a chunk that hasn't been generated), it returns .AIR
                    const blockCurrent: Material = if (pos[d] >= 0)
                        self.get_block(pos[0], pos[1], pos[2])
                    else
                        self.get_block_from_neighbours(pos[0], pos[1], pos[2], neighbours);
                    //self.world.get_block(pos[0] + self.pos[0] * CHUNK_SIZE, pos[1] + self.pos[1] * CHUNK_SIZE, pos[2] + self.pos[2] * CHUNK_SIZE);
                    const blockCompare: Material = if (pos[d] < CHUNK_SIZE - 1)
                        self.get_block(pos[0] + q[0], pos[1] + q[1], pos[2] + q[2])
                    else
                        self.get_block_from_neighbours(pos[0] + q[0], pos[1] + q[1], pos[2] + q[2], neighbours);
                    //self.world.get_block(pos[0] + self.pos[0] * CHUNK_SIZE, pos[1] + self.pos[1] * CHUNK_SIZE, pos[2] + self.pos[2] * CHUNK_SIZE);

                    // The mask is set to the block type if there is a visible face between two blocks,
                    //   i.e. both aren't empty and both aren't blocks
                    if ((blockCurrent != .AIR) != (blockCompare != .AIR)) {
                        mask[mask_index] = if (blockCompare != .AIR) blockCompare else blockCurrent;
                    } else {
                        mask[mask_index] = .AIR;
                    }
                    // Flip is set to true if its normals should be flipped
                    flip[mask_index] = blockCompare != .AIR;
                    mask_index += 1;
                }
            }

            pos[d] += 1;
            mask_index = 0; // Reset mask index so we can traverse mask again

            // Generate a mesh from the mask using lexicographic ordering,
            //   by looping over each block in this slice of the chunk
            for (0..CHUNK_SIZE) |j| {
                var i: usize = 0;
                while (i < CHUNK_SIZE) {
                    const block_type = mask[mask_index];
                    if (block_type != .AIR) {
                        var width: u32 = 1;
                        var height: u32 = 1;
                        // Compute the width of this quad and store it in width
                        //   This is done by searching along the current axis until mask[mask_index + width] is a different block type
                        while (i + width < CHUNK_SIZE and block_type == mask[mask_index + width]) : (width += 1) {
                            if (flip[mask_index] != flip[mask_index + width]) {
                                break;
                            }
                        }

                        // Compute the height of this quad and store it in height
                        //   This is done by checking if every block next to this row (range 0 to width) is also part of the mask.
                        //   For example, if width is 5 we currently have a quad of dimensions 1 x 5. To reduce triangle count,
                        //   greedy meshing will attempt to expand this quad out to CHUNK_SIZE x 5, but will stop if it reaches a hole in the mask
                        var done = false;
                        while (j + height < CHUNK_SIZE) : (height += 1) {
                            // Check each block next to this quad
                            for (0..width) |k| {
                                // If there's a hole (not the same block type as the one we're looking for) in the mask, exit
                                if (block_type != mask[mask_index + k + height * CHUNK_SIZE] or flip[mask_index] != flip[mask_index + k + height * CHUNK_SIZE]) {
                                    done = true;
                                    break;
                                }
                            }
                            if (done)
                                break;
                        }

                        pos[u] = @intCast(i);
                        pos[v] = @intCast(j);

                        // du and dv determine the size and orientation of this face
                        var du: [3]i32 = .{ 0, 0, 0 };
                        du[u] = @intCast(width);

                        var dv: [3]i32 = .{ 0, 0, 0 };
                        dv[v] = @intCast(height);

                        //Create the vertices for the quad (to, you know, actually render the quad)
                        const bottom_right = create_vertex(pos[0] + du[0] + dv[0], pos[1] + du[1] + dv[1], pos[2] + du[2] + dv[2], 1.0, 1.0, width, height, block_type);
                        const top_right = create_vertex(pos[0] + du[0], pos[1] + du[1], pos[2] + du[2], 1.0, 0.0, width, height, block_type);
                        const top_left = create_vertex(pos[0], pos[1], pos[2], 0.0, 0.0, width, height, block_type);
                        const bottom_left = create_vertex(pos[0] + dv[0], pos[1] + dv[1], pos[2] + dv[2], 0.0, 1.0, width, height, block_type);

                        const quad: [6]Vertex = if (!flip[mask_index]) .{
                            bottom_right, top_right,    top_left,
                            bottom_left,  bottom_right, top_left,
                        } else .{
                            top_left, top_right,    bottom_right,
                            top_left, bottom_right, bottom_left,
                        };

                        for (quad) |vertex| {
                            vertices_list.append(allocator, vertex) catch unreachable;
                        }

                        for (0..height) |l| {
                            for (0..width) |k| {
                                mask[mask_index + k + l * CHUNK_SIZE] = .AIR;
                            }
                        }

                        i += width;
                        mask_index += width;
                    } else {
                        i += 1;
                        mask_index += 1;
                    }
                }
            }
        }
    }
    if (vertices_list.items.len == 0) {
        self.all_air = true;
        return;
    }

    self.ssbo_view = sg.makeView(.{
        .storage_buffer = .{
            .buffer = sg.makeBuffer(.{
                .data = sg.asRange(vertices_list.items),
                .usage = .{ .storage_buffer = true },
            }),
        },
    });
    self.vertex_count = @intCast(vertices_list.items.len);
}

pub fn get_block(self: *Chunk, x: i32, y: i32, z: i32) Material {
    const x_usize: usize = @intCast(x);
    const y_usize: usize = @intCast(y);
    const z_usize: usize = @intCast(z);
    return self.blocks[x_usize][y_usize][z_usize].material;
}

fn get_block_from_neighbours(self: *Chunk, x: i32, y: i32, z: i32, neighbours: [6]?*Chunk) Material {
    const wx = x + self.pos[0] * CHUNK_SIZE;
    const wy = y + self.pos[1] * CHUNK_SIZE;
    const wz = z + self.pos[2] * CHUNK_SIZE;

    for (neighbours) |n| {
        if (n == null)
            continue;
        const x_relative_to_n = wx - n.?.pos[0] * CHUNK_SIZE;
        const y_relative_to_n = wy - n.?.pos[1] * CHUNK_SIZE;
        const z_relative_to_n = wz - n.?.pos[2] * CHUNK_SIZE;

        if (0 <= x_relative_to_n and x_relative_to_n < CHUNK_SIZE and
            0 <= y_relative_to_n and y_relative_to_n < CHUNK_SIZE and
            0 <= z_relative_to_n and z_relative_to_n < CHUNK_SIZE)
        {
            return n.?.get_block(x_relative_to_n, y_relative_to_n, z_relative_to_n);
        }
    }
    return .AIR;
}

fn create_vertex(x: i32, y: i32, z: i32, u: f32, v: f32, width: u32, height: u32, block_type: Material) Vertex {
    return Vertex{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .z = @floatFromInt(z),
        .u = u,
        .v = v,
        .width = width,
        .height = height,
        .tex_id = @intFromEnum(block_type) - 1,
    };
}
