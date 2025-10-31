const Block = @This();

pub const Material = enum(u3) {
    AIR = 0,
    DEFAULT = 1,
    DIRT = 2,
    STONE = 3,
    WATER = 4,
    GRASS = 5,
    SAND = 6,
    SNOW = 7,
};

material: Material,
