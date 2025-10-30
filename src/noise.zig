//Simplex noise is a noise function comparable to Perlin noise, but with fewer directional artifacts and supports higher dimensions. It was designed by Ken Perlin.
//This implementation of Simplex noise was taken from the following link and adapted from Java:
//https://web.archive.org/web/20230310204125/https://webstaff.itn.liu.se/%7Estegu/simplexnoise/simplexnoise.pdf
const grad3: [][]i8 = .{ .{ 1, 1, 0 }, .{ -1, 1, 0 }, .{ 1, -1, 0 }, .{ -1, -1, 0 }, .{ 1, 0, 1 }, .{ -1, 0, 1 }, .{ 1, 0, -1 }, .{ -1, 0, -1 }, .{ 0, 1, 1 }, .{ 0, -1, 1 }, .{ 0, 1, -1 }, .{ 0, -1, -1 } };
const p: []u16 = .{ 151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180 };
const perm: [512]u16 = blk: {
    var arr: [512]u16 = undefined;
    for (0..512) |i| {
        arr[i] = p[i & 255];
    }
    break :blk arr;
};
const F3 = 1.0 / 3.0; //Skew factor for 3D
const G3 = 1.0 / 6.0; //Unskew factor for 3D

fn dot(g: []i8, x: f32, y: f32, z: f32) f32 {
    return g[0] * x + g[1] * y + g[2] * z;
}

pub fn noise(xin: f32, yin: f32, zin: f32) f32 {
    //Skew input space to determine which simplex cell we're in
    const s = (xin + yin + zin) * F3;
    const i: u16 = @floor(xin + s);
    const j: u16 = @floor(yin + s);
    const k: u16 = @floor(zin + s);

    const t: f32 = (i + j + k) * G3;
    const X_0: f32 = i - t; //Unskew cell origin back to (x, y, z) space
    const Y_0: f32 = j - t;
    const Z_0: f32 = k - t;
    const x_0: f32 = xin - X_0; //The x, y, z distances from the cell origin
    const y_0: f32 = yin - Y_0;
    const z_0: f32 = zin - Z_0;

    var i_1: u16 = 0; //Offsets for second corner of simplex in (i, j, k) coords
    var j_1: u16 = 0;
    var k_1: u16 = 0;
    var i_2: u16 = 0; //Offsets for third corner of simplex in (i, j, k) coords
    var j_2: u16 = 0;
    var k_2: u16 = 0;

    //For the 3D case, Simplex shape is a slightly irregular tetrahedron.
    //Determine which simplex we are in.
    if (x_0 >= y_0) {
        if (y_0 >= z_0) { //XYZ order
            i_1 = 1;
            j_1 = 0;
            k_1 = 0;
            i_2 = 1;
            j_2 = 1;
            k_2 = 0;
        } else if (x_0 >= z_0) { //XZY order
            i_1 = 1;
            j_1 = 0;
            k_1 = 0;
            i_2 = 1;
            j_2 = 0;
            k_2 = 1;
        } else { //ZXY order
            i_1 = 0;
            j_1 = 0;
            k_1 = 1;
            i_2 = 1;
            j_2 = 0;
            k_2 = 1;
        }
    } else { //x_0 < y_0
        if (y_0 < z_0) { //ZYX order
            i_1 = 0;
            j_1 = 0;
            k_1 = 1;
            i_2 = 0;
            j_2 = 1;
            k_2 = 1;
        } else if (x_0 < z_0) { //YZX order
            i_1 = 0;
            j_1 = 1;
            k_1 = 0;
            i_2 = 0;
            j_2 = 1;
            k_2 = 1;
        } else { //YXZ order
            i_1 = 0;
            j_1 = 1;
            k_1 = 0;
            i_2 = 1;
            j_2 = 1;
            k_2 = 0;
        }
    }

    // A step of (1,0,0) in (i,j,k) means a step of (1-c,-c,-c) in (x,y,z),
    // a step of (0,1,0) in (i,j,k) means a step of (-c,1-c,-c) in (x,y,z), and
    // a step of (0,0,1) in (i,j,k) means a step of (-c,-c,1-c) in (x,y,z), where
    // c = 1/
    const x_1: f32 = x_0 - i_1 + G3; //Offsets for second corner in (x, y, z) coords
    const y_1: f32 = y_0 - j_1 + G3;
    const z_1: f32 = z_0 - k_1 + G3;
    const x_2: f32 = x_0 - i_2 + 2.0 * G3; //Offsets for third corner in (x, y, z) coords
    const y_2: f32 = y_0 - j_2 + 2.0 * G3;
    const z_2: f32 = z_0 - k_2 + 2.0 * G3;
    const x_3: f32 = x_0 - 1.0 + 3.0 * G3; //Offsets for fourth corner in (x, y, z) coords
    const y_3: f32 = y_0 - 1.0 + 3.0 * G3;
    const z_3: f32 = z_0 - 1.0 + 3.0 * G3;

    //Work out hashed gradient indices of the four simplex corners
    const ii = i & 255;
    const jj = j & 255;
    const kk = k & 255;
    const gi_0: u16 = perm[ii + perm[jj + perm[kk]]] % 12;
    const gi_1: u16 = perm[ii + i_1 + perm[jj + j_1 + perm[kk + k_1]]] % 12;
    const gi_2: u16 = perm[ii + i_2 + perm[jj + j_2 + perm[kk + k_2]]] % 12;
    const gi_3: u16 = perm[ii + 1 + perm[jj + 1 + perm[kk + 1]]] % 12;

    var n_0: f32 = 0; //Noise contributions from the four corners
    var n_1: f32 = 0;
    var n_2: f32 = 0;
    var n_3: f32 = 0;

    //Calculate contribution from the four corners
    var t_0: f32 = 0.6 - x_0 * x_0 - y_0 * y_0 - z_0 * z_0;
    if (t_0 >= 0) {
        t_0 *= t_0;
        n_0 = t_0 * t_0 * dot(grad3[gi_0], x_0, y_0, z_0);
    }

    var t_1: f32 = 0.6 - x_1 * x_1 - y_1 * y_1 - z_1 * z_1;
    if (t_1 >= 0) {
        t_1 *= t_1;
        n_1 = t_1 * t_1 * dot(grad3[gi_1], x_1, y_1, z_1);
    }

    var t_2: f32 = 0.6 - x_2 * x_2 - y_2 * y_2 - z_2 * z_2;
    if (t_2 >= 0) {
        t_2 *= t_2;
        n_2 = t_2 * t_2 * dot(grad3[gi_2], x_2, y_2, z_2);
    }

    var t_3: f32 = 0.6 - x_3 * x_3 - y_3 * y_3 - z_3 * z_3;
    if (t_3 >= 0) {
        t_3 *= t_3;
        n_3 = t_3 * t_3 * dot(grad3[gi_3], x_3, y_3, z_3);
    }

    //Add contributions from each corner to get the final noise value.
    //Result is scaled to stay just inside [-1, 1];
    return 32.0 * (n_0 + n_1 + n_2 + n_3);
}
