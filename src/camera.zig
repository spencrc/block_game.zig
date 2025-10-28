const Camera = @This();

const vec3 = @import("math.zig").Vec3;
const mat4 = @import("math.zig").Mat4;

const STARTING_POSITION: vec3 = vec3{ .x = 0.0, .y = 0.0, .z = 5.0 };

position: vec3 = STARTING_POSITION,
yaw: f32 = 0,
pitch: f32 = 0,
input: vec3 = vec3.zero(),
target: vec3 = vec3.zero(),
proj: mat4 = mat4.lookat(STARTING_POSITION, vec3.zero(), vec3.up()),
view: mat4 = mat4.persp(90.0, 1, 0.1, 500),

pub fn init() Camera {
    return .{};
}

const speed = 0.5;
pub fn update_camera(self: *Camera, dt: f32) void {
    const multiplier = speed * dt;

    const ch = @cos(self.yaw);
    const sh = @sin(self.yaw);
    const cp = @cos(self.pitch);
    const sp = @sin(self.pitch);
    //code following this line was adapted from here: https://github.com/nadako/hello-sokol-odin/blob/master/main.odin
    const forward = vec3{ .x = cp * sh, .y = sp, .z = -cp * ch };
    const right = vec3{ .x = ch, .y = 0.0, .z = sh };

    const move_dir = vec3.add(vec3.mul(forward, self.input.y), vec3.mul(right, self.input.x));
    const motion = vec3.mul(vec3.norm(move_dir), multiplier);

    self.position.x += motion.x;
    self.position.y += motion.y;
    self.position.z += motion.z;

    self.target = vec3.add(self.position, forward);
}

pub fn update_matricies(self: *Camera, width: f32, height: f32) void {
    self.proj = mat4.persp(90.0, width / height, 0.1, 500);
    self.view = mat4.lookat(self.position, self.target, vec3.up());
}

const sens = 0.004;
pub fn handle_mouse_movement(self: *Camera, is_mouse_locked: bool, dx: f32, dy: f32) void {
    if (!is_mouse_locked)
        return;

    self.yaw += dx * sens;
    self.pitch -= dy * sens;
    //wrap yap to be in interval [0, 360]
    self.yaw = @mod(self.yaw, 2 * 3.14);
    if (self.yaw < 0) {
        self.yaw += 2 * 3.14;
    }
    //clamp pitch to be in interval [-90, 90]
    self.pitch = @max(-3.14 / 2.0, @min(3.14 / 2.0, self.pitch));
}
