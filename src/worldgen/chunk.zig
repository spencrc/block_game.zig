const Chunk = @This();

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simplex = @import("noise.zig");

const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
    width: u32,
    height: u32,
};

const CHUNK_SIZE = @import("../constants.zig").CHUNK_SIZE;
const MAX_CUBES_PER_CHUNK = @import("../constants.zig").MAX_CUBES_PER_CHUNK;

pos: [3]i32,
blocks: [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]bool,
ssbo_view: sg.View = undefined, //if unitialized like this, it takes up just 4 bytes
vertex_count: u32 = 0,

pub fn init(x: i32, y: i32, z: i32) Chunk {
    var blocks: [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]bool = undefined;

    for (0..CHUNK_SIZE) |cx| {
        for (0..CHUNK_SIZE) |cy| {
            for (0..CHUNK_SIZE) |cz| {
                const noise = simplex.noise(@floatFromInt(cx), @floatFromInt(cy), @floatFromInt(cz));
                if (noise < 0.1) {
                    blocks[cx][cy][cz] = false;
                } else blocks[cx][cy][cz] = true;
            }
        }
    }

    return .{
        .pos = .{ x, y, z },
        .blocks = blocks,
    };
}

//TODO: somehow get width/length of final result greedy mesh quads, so we can pass to uniform and then scale texcoords accurately
//Greedy mesher algorithm implementation in Zig. Works to generate a mesh for a chunk with minimals vertices for performance.
//Please see here for where the code originates, as it's not my own: https://gist.github.com/Vercidium/a3002bd083cce2bc854c9ff8f0118d33#file-greedyvoxelmeshing-L19
pub fn greedy_mesh(self: *Chunk, allocator: std.mem.Allocator) void {
    var vertices_list = std.ArrayList(Vertex).empty;
    defer vertices_list.deinit(allocator);

    for (0..3) |d| {
        const u = (d + 1) % 3;
        const v = (d + 2) % 3;
        var pos: [3]isize = .{ 0, 0, 0 };
        var q: [3]isize = .{ 0, 0, 0 };

        var mask: [CHUNK_SIZE * CHUNK_SIZE]bool = undefined;
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
                    // self.is_block_at(x,y,z) takes global map positions and returns true if a block exists there
                    //TODO: add chunk position to both is_block_at call
                    const blockCurrent: bool = if (0 <= pos[d]) self.is_block_at(pos[0], pos[1], pos[2]) else false;
                    const blockCompare: bool = if (pos[d] < CHUNK_SIZE - 1) self.is_block_at(pos[0] + q[0], pos[1] + q[1], pos[2] + q[2]) else false;

                    // The mask is set to true if there is a visible face between two blocks,
                    //   i.e. both aren't empty and both aren't blocks
                    mask[mask_index] = blockCurrent != blockCompare;
                    //Flip is set to true if its normals should be flipped
                    flip[mask_index] = blockCompare;
                    mask_index += 1;
                }
            }

            pos[d] += 1;
            mask_index = 0;

            // Generate a mesh from the mask using lexicographic ordering,
            //   by looping over each block in this slice of the chunk
            for (0..CHUNK_SIZE) |j| {
                var i: usize = 0;
                while (i < CHUNK_SIZE) {
                    if (mask[mask_index]) {
                        var width: u32 = 1;
                        var height: u32 = 1;
                        // Compute the width of this quad and store it in width
                        //   This is done by searching along the current axis until mask[mask_index + width] is false
                        while (i + width < CHUNK_SIZE and mask[mask_index + width] and (flip[mask_index] == flip[mask_index + width])) : (width += 1) {}

                        // Compute the height of this quad and store it in height
                        //   This is done by checking if every block next to this row (range 0 to width) is also part of the mask.
                        //   For example, if width is 5 we currently have a quad of dimensions 1 x 5. To reduce triangle count,
                        //   greedy meshing will attempt to expand this quad out to CHUNK_SIZE x 5, but will stop if it reaches a hole in the mask
                        var done = false;
                        while (j + height < CHUNK_SIZE) : (height += 1) {
                            // Check each block next to this quad
                            for (0..width) |k| {
                                // If there's a hole in the mask, exit
                                if (!mask[mask_index + k + height * CHUNK_SIZE] or flip[mask_index] != flip[mask_index + k + height * CHUNK_SIZE]) {
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
                        var du: [3]isize = .{ 0, 0, 0 };
                        du[u] = @intCast(width);

                        var dv: [3]isize = .{ 0, 0, 0 };
                        dv[v] = @intCast(height);

                        //Create the vertices for the quad (to, you know, actually render the quad)
                        const bottom_right = create_vertex(pos[0] + du[0] + dv[0], pos[1] + du[1] + dv[1], pos[2] + du[2] + dv[2], 1.0, 1.0, width, height);
                        const top_right = create_vertex(pos[0] + du[0], pos[1] + du[1], pos[2] + du[2], 1.0, 0.0, width, height);
                        const top_left = create_vertex(pos[0], pos[1], pos[2], 0.0, 0.0, width, height);
                        const bottom_left = create_vertex(pos[0] + dv[0], pos[1] + dv[1], pos[2] + dv[2], 0.0, 1.0, width, height);

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
                                mask[mask_index + k + l * CHUNK_SIZE] = false;
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
    const storage_buffer = sg.makeBuffer(.{
        .data = sg.asRange(vertices_list.items),
        .usage = .{ .storage_buffer = true },
    });
    self.ssbo_view = sg.makeView(.{
        .storage_buffer = .{
            .buffer = storage_buffer,
        },
    });
    self.vertex_count = @intCast(vertices_list.items.len);
}

fn is_block_at(self: *Chunk, x: isize, y: isize, z: isize) bool {
    const x_usize: usize = @intCast(x);
    const y_usize: usize = @intCast(y);
    const z_usize: usize = @intCast(z);
    return self.blocks[x_usize][y_usize][z_usize] == true;
}

fn create_vertex(x: isize, y: isize, z: isize, u: f32, v: f32, width: u32, height: u32) Vertex {
    return Vertex{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z), .u = u, .v = v, .width = width, .height = height };
}
