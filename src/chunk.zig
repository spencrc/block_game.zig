const Chunk = @This();

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;

const Vertex = extern struct { x: f32, y: f32, z: f32, u: f32, v: f32 };

const CHUNK_SIZE = @import("constants.zig").CHUNK_SIZE;
const MAX_CUBES_PER_CHUNK = @import("constants.zig").MAX_CUBES_PER_CHUNK;

blocks: [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]bool,
vertex_buffer: sg.Buffer = undefined,
index_buffer: sg.Buffer = undefined,

vertex_count: u32 = 0,
index_count: u32 = 0,

pub fn create() Chunk {
    var blocks: [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]bool = undefined;

    for (0..CHUNK_SIZE) |cx| {
        for (0..CHUNK_SIZE) |cy| {
            for (0..CHUNK_SIZE) |cz| {
                blocks[cx][cy][cz] = true;
            }
        }
    }

    return .{
        .blocks = blocks,
    };
}

//TODO: somehow get width/length of final result greedy mesh quads, so we can pass to uniform and then scale texcoords accurately
//Greedy mesher algorithm implementation in Zig. Works to generate a mesh for a chunk with minimals vertices for performance.
//Please see here for where the code originates, as it's not my own: https://gist.github.com/Vercidium/a3002bd083cce2bc854c9ff8f0118d33#file-greedyvoxelmeshing-L19
pub fn greedy_mesh(self: *Chunk) void {
    var indices: [6 * 6 * MAX_CUBES_PER_CHUNK]u16 = undefined;
    var vertices: [6 * 4 * MAX_CUBES_PER_CHUNK]Vertex = undefined;
    var vertex_count: u16 = 0;
    var index_count: u16 = 0;

    for (0..3) |d| {
        const u = (d + 1) % 3;
        const v = (d + 2) % 3;
        var x: [3]isize = .{ 0, 0, 0 };
        var q: [3]isize = .{ 0, 0, 0 };

        var mask: [CHUNK_SIZE * CHUNK_SIZE]bool = undefined;
        var flip: [CHUNK_SIZE * CHUNK_SIZE]bool = undefined;
        q[d] = 1;
        x[d] = -1;

        // Check each slice of the chunk one at a time
        while (x[d] < CHUNK_SIZE) {
            var n: usize = 0;
            for (0..CHUNK_SIZE) |j| {
                x[v] = @intCast(j);
                for (0..CHUNK_SIZE) |k| {
                    x[u] = @intCast(k);

                    // q determines the direction (X, Y or Z) that we are searching
                    // self.is_block_at(x,y,z) takes global map positions and returns true if a block exists there
                    //TODO: add chunk position to both is_block_at call
                    const blockCurrent: bool = if (0 <= x[d]) self.is_block_at(x[0], x[1], x[2]) else false;
                    const blockCompare: bool = if (x[d] < CHUNK_SIZE - 1) self.is_block_at(x[0] + q[0], x[1] + q[1], x[2] + q[2]) else false;

                    // The mask is set to true if there is a visible face between two blocks,
                    //   i.e. both aren't empty and both aren't blocks
                    mask[n] = blockCurrent != blockCompare;
                    //Flip is set to true if its normals should be flipped
                    flip[n] = blockCompare;
                    n += 1;
                }
            }

            x[d] += 1;
            n = 0;

            // Generate a mesh from the mask using lexicographic ordering,
            //   by looping over each block in this slice of the chunk
            for (0..CHUNK_SIZE) |j| {
                var i: usize = 0;
                while (i < CHUNK_SIZE) {
                    if (mask[n]) {
                        var w: usize = 1;
                        var h: usize = 1;
                        // Compute the width of this quad and store it in w
                        //   This is done by searching along the current axis until mask[n + w] is false
                        while (i + w < CHUNK_SIZE and mask[n + w] and (flip[n] == flip[n + w])) : (w += 1) {}

                        // Compute the height of this quad and store it in h
                        //   This is done by checking if every block next to this row (range 0 to w) is also part of the mask.
                        //   For example, if w is 5 we currently have a quad of dimensions 1 x 5. To reduce triangle count,
                        //   greedy meshing will attempt to expand this quad out to CHUNK_SIZE x 5, but will stop if it reaches a hole in the mask
                        var done = false;
                        while (j + h < CHUNK_SIZE) : (h += 1) {
                            // Check each block next to this quad
                            for (0..w) |k| {
                                // If there's a hole in the mask, exit
                                if (!mask[n + k + h * CHUNK_SIZE] or flip[n] != flip[n + k + h * CHUNK_SIZE]) {
                                    done = true;
                                    break;
                                }
                            }

                            if (done)
                                break;
                        }

                        x[u] = @intCast(i);
                        x[v] = @intCast(j);

                        // du and dv determine the size and orientation of this face
                        var du: [3]isize = .{ 0, 0, 0 };
                        du[u] = @intCast(w);

                        var dv: [3]isize = .{ 0, 0, 0 };
                        dv[v] = @intCast(h);

                        //Build the vertices for the quad
                        vertices[vertex_count + 0] = create_vertex(x[0], x[1], x[2], 0.0, 0.0); //TOP LEFT
                        vertices[vertex_count + 1] = create_vertex(x[0] + du[0], x[1] + du[1], x[2] + du[2], 1.0, 0.0); //BOTTOM LEFT
                        vertices[vertex_count + 2] = create_vertex(x[0] + du[0] + dv[0], x[1] + du[1] + dv[1], x[2] + du[2] + dv[2], 1.0, 1.0); //TOP RIGHT
                        vertices[vertex_count + 3] = create_vertex(x[0] + dv[0], x[1] + dv[1], x[2] + dv[2], 0.0, 1.0); //BOTTOM RIGHT

                        //Build the indices for the quad (to, you know, actually render the quad)
                        if (!flip[n]) { //Not flip means we don't want to be flip the normal!
                            indices[index_count + 0] = vertex_count + 2;
                            indices[index_count + 1] = vertex_count + 1;
                            indices[index_count + 2] = vertex_count;
                            indices[index_count + 3] = vertex_count + 3;
                            indices[index_count + 4] = vertex_count + 2;
                            indices[index_count + 5] = vertex_count;
                        } else { //Here we want to flip the normal!
                            indices[index_count + 0] = vertex_count;
                            indices[index_count + 1] = vertex_count + 1;
                            indices[index_count + 2] = vertex_count + 2;
                            indices[index_count + 3] = vertex_count + 0;
                            indices[index_count + 4] = vertex_count + 2;
                            indices[index_count + 5] = vertex_count + 3;
                        }
                        //Done messing with vertices/quad, so increment!
                        index_count += 6;
                        vertex_count += 4;

                        for (0..h) |l| {
                            for (0..w) |k| {
                                mask[n + k + l * CHUNK_SIZE] = false;
                            }
                        }

                        i += w;
                        n += w;
                    } else {
                        i += 1;
                        n += 1;
                    }
                }
            }
        }
    }
    self.vertex_buffer = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
    });
    self.index_buffer = sg.makeBuffer(.{
        .data = sg.asRange(&indices),
        .usage = .{ .index_buffer = true },
    });
    self.index_count = index_count;
    self.vertex_count = vertex_count;
}

fn is_block_at(self: *Chunk, x: isize, y: isize, z: isize) bool {
    const x_usize: usize = @intCast(x);
    const y_usize: usize = @intCast(y);
    const z_usize: usize = @intCast(z);
    return self.blocks[x_usize][y_usize][z_usize] == true;
}

fn create_vertex(x: isize, y: isize, z: isize, u: f32, v: f32) Vertex {
    return Vertex{ .x = @floatFromInt(x), .y = @floatFromInt(y), .z = @floatFromInt(z), .u = u, .v = v };
}
