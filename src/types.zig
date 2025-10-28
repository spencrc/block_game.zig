const vec3 = @import("math.zig").Vec3;

pub const InstanceData = struct {
    pos: vec3 = vec3.zero(),
};

pub const Vertex = extern struct { x: f32, y: f32, z: f32, u: f32, v: f32 };
