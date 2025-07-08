const std = @import("std");
const random = std.Random;

const Spline = struct {
    char: []const u8,
    ansi: []const u8,
    weight: f32,
};
const ANSI_COLOR_GREEN = "\x1b[32m";
const ANSI_COLOR_YELLOW = "\x1b[33m";
const ANSI_COLOR_BLUE = "\x1b[34m";
const ANSI_COLOR_RESET = "\x1b[0m";

const land = Spline{
    .char = "l",
    .ansi = ANSI_COLOR_GREEN,
    .weight = 20,
};

const coast = Spline{
    .char = "c",
    .ansi = ANSI_COLOR_YELLOW,
    .weight = 10,
};
const sea = Spline{
    .char = "o",
    .ansi = ANSI_COLOR_BLUE,
    .weight = 20,
};

const SplineEnum = enum {
    coast,
    sea,
    land,
    none,
};

fn selectSpline(choice: u8) !Spline {
    if (choice > 2) return error.InvalidChoice;
    const enumValue = @as(SplineEnum, @enumFromInt(choice));
    return switch (enumValue) {
        .coast => coast,
        .sea => sea,
        .land => land,
        .none => return error.InvalidChoice,
    };
}

const Tile = struct {
    collapsed: SplineEnum = .none,
    entropy: f32 = std.math.floatMax(f32),
    options: @Vector(3, bool) = [_]bool{ true, true, true },
};

const TileList = std.MultiArrayList(Tile);

const Monster = struct {
    element: enum { fire, water, earth, wind },
    hp: u32,
};

const MonsterList = std.MultiArrayList(Monster);
pub fn main() !void {
    const width = 30;
    const height = 8;

    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    var tiles = TileList{};
    defer tiles.deinit(gpa);
    try tiles.ensureTotalCapacity(gpa, width * height);

    // print tiles
    const entrypies = tiles.items(.entropy);
    std.debug.print("{any}", .{entrypies});

    // var soa = MonsterList{};
    // defer soa.deinit(gpa);

    // // Normally you would want to append many monsters
    // try soa.append(gpa, .{
    //     .element = .fire,
    //     .hp = 20,
    // });
    // try soa.append(gpa, .{
    //     .element = .fire,
    //     .hp = 50,
    // });
    //
    // std.debug.print("soa.len = {any}\n", .{soa.items(.hp)});

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    var bw_writer = bw.writer();

    for (0..height) |_| {
        for (0..width) |_| {
            const choice = rand.intRangeAtMost(u8, 0, 2);
            const c = try selectSpline(choice);
            try bw_writer.writeAll(c.ansi);
            try bw_writer.writeAll(c.char);
            try bw_writer.writeAll(ANSI_COLOR_RESET);
        }
        try bw_writer.writeByte('\n');
    }

    try bw.flush();
}
