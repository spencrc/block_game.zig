const Camera = @This();

const std = @import("std");
const math = std.math;
const vec2 = @import("math.zig").Vec2;
const vec3 = @import("math.zig").Vec3;
const mat4 = @import("math.zig").Mat4;

position: vec3 = vec3{ .x = 0.0, .y = 0.0, .z = 5.0 },
rotation: vec2 = vec2{ .x = math.tau / 4.0, .y = 0 },
input: vec3 = vec3.zero(),
view: mat4 = mat4.lookat(.{ .x = 0.0, .y = 0, .z = 5 }, vec3.zero(), vec3.up()),
proj: mat4 = undefined,

pub fn init() Camera {
    return .{};
}

pub fn update_camera(self: *Camera, dt: f32) void {
    if (self.input.x == 0 and self.input.y == 0 and self.input.z == 0)
        return;

    const speed = 1;
    const multiplier = speed * dt;
    const angle = self.rotation.x + math.atan2(self.input.z, self.input.x) - math.tau / 4.0;

    self.position.y += self.input.y * multiplier;
    self.position.x += @cos(angle) * multiplier;
    self.position.z += @sin(angle) * multiplier;
}

pub fn update_matricies(self: *Camera, width: f32, height: f32) void {
    //TODO: this function currently only works if you are just rotating (so update_camera is disabled). we don't want that, so please re-write to use non-chatgpt code :]
    self.proj = mat4.persp(90.0, width / height, 0.1, 500);

    const yaw = -(self.rotation.x - math.tau / 4.0); //god bless chatgpt i pray this works
    const pitch = self.rotation.y;
    const target = vec3.add(self.position, vec3{ //based on obiwac's 2d rotation implementation in python
        .x = @cos(pitch) * @sin(yaw),
        .y = @sin(pitch),
        .z = -@cos(pitch) * @cos(yaw),
    });
    self.view = mat4.lookat(self.position, target, vec3.up());
}
