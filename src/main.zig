const std = @import("std");
const print = std.debug.print;
const random = std.Random;
const ArrayList = std.ArrayList;

const Spline = struct {
    char: []const u8,
    ansi: []const u8,
    weight: f32,
    adjacents: [3]bool,
};
const ANSI_COLOR_GREEN = "\x1b[32m";
const ANSI_COLOR_YELLOW = "\x1b[33m";
const ANSI_COLOR_BLUE = "\x1b[34m";
const ANSI_COLOR_RESET = "\x1b[0m";
const ANSI_CURSOR_HOME = "\x1b[H";
const ANSI_CLEAR_SCREEN = "\x1b[2J";

const land = Spline{
    .char = "l",
    .ansi = ANSI_COLOR_GREEN,
    .weight = 60,
    .adjacents = [_]bool{ true, true, false },
};

const coast = Spline{
    .char = "c",
    .ansi = ANSI_COLOR_YELLOW,
    .weight = 10,
    .adjacents = [_]bool{ true, true, true },
};
const sea = Spline{
    .char = "s",
    .ansi = ANSI_COLOR_BLUE,
    .weight = 20,
    .adjacents = [_]bool{ false, true, true },
};

const empty = Spline{
    .char = "-",
    .ansi = ANSI_COLOR_RESET,
    .weight = 0,
    .adjacents = [_]bool{ true, true, true },
};

const SplineEnum = enum {
    land,
    coast,
    sea,
    none,
};

const EntropyRecord = struct {
    entropy: f32,
    x: usize,
    y: usize,
};

const Point = struct {
    x: usize,
    y: usize,
};

fn selectEnum(choice: u8) !SplineEnum {
    if (choice > 2) return error.InvalidChoice;
    return @as(SplineEnum, @enumFromInt(choice));
}

fn selectSpline(enumValue: SplineEnum) !Spline {
    return switch (enumValue) {
        .land => land,
        .coast => coast,
        .sea => sea,
        .none => empty,
    };
}

const Tile = struct {
    collapsed: SplineEnum,
    entropy: f32,
    options: [3]bool,
    pub const init: Tile = .{
        .collapsed = .none,
        .entropy = std.math.floatMax(f32),
        .options = [_]bool{ true, true, true },
    };
};

pub fn updateEntropy(tile: Tile) !f32 {
    const opts = tile.options;
    var sumWeights: f32 = 0;
    for (opts, 0..) |opt, index| {
        if (opt) {
            const en = try selectEnum(@as(u8, @intCast(index)));
            const spline = try selectSpline(en);
            sumWeights += spline.weight;
        }
    }
    const logSum = std.math.log(f32, 2, sumWeights);

    var weightedSum: f32 = 0;
    for (opts, 0..) |opt, index| {
        if (opt) {
            const i = @as(u8, @intCast(index));
            const en = try selectEnum(i);
            const spline = try selectSpline(en);
            const weight = spline.weight;
            const logWeight = std.math.log(f32, 2, weight);
            weightedSum += (weight * logWeight);
        }
    }

    return logSum - weightedSum / sumWeights;
}

pub fn newAdjacent(index: u8) [3]bool {
    const adj = switch (index) {
        0 => [_]bool{ true, true, false },
        1 => [_]bool{ true, true, true },
        2 => [_]bool{ false, true, true },
        else => unreachable,
    };
    return adj;
}

pub inline fn checkVisited(visitedCells: *std.AutoHashMap(Point, void), x: usize, y: usize) bool {
    return visitedCells.contains(.{ .x = x, .y = y });
}

// TODO:  implmenent this shit fuckeerrr
pub inline fn weightedRandomSelect(choices: ArrayList(u8), prng: *std.rand.Random) u8 {
    const items = choices.items;
    _ = prng.next();
    const rand = prng.random();
    rand.shuffle(u8, items);
    return items[0];
}

pub fn main() !void {
    const width = 50;
    const height = 30;
    var collapsed: u32 = 0;
    var lowestEntropy: f32 = std.math.floatMax(f32);
    var lowestX: usize = 0;
    var lowestY: usize = 0;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    var bw_writer = bw.writer();

    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    var visitedCells = std.AutoHashMap(Point, void).init(
        gpa,
    );
    defer visitedCells.deinit();

    // initiate tiles
    var tiles: [height][width]Tile = @splat(@splat(.init));
    for (0..height) |y| {
        for (0..width) |x| {
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;
            if (entropy < lowestEntropy) {
                lowestEntropy = entropy;
                lowestX = x;
                lowestY = y;
            }
        }
    }

    var choices = ArrayList(u8).init(gpa);
    var entropyRecords = ArrayList(EntropyRecord).init(gpa);

    try bw_writer.writeAll(ANSI_CLEAR_SCREEN);

    while (collapsed < (width * height) or entropyRecords.items.len != 0) : (collapsed += 1) {
        const opts = tiles[lowestY][lowestX].options;
        for (opts, 0..) |opt, index| {
            if (opt) {
                try choices.append(@as(u8, @intCast(index)));
            }
        }
        // _ = prng.next();
        const rand = prng.random();

        const items = choices.items;
        rand.shuffle(u8, items);
        const first = items[0];
        const en = try selectEnum(first);
        tiles[lowestY][lowestX].collapsed = en;

        const newAdj = newAdjacent(first);

        // check top
        if (lowestY > 0) {
            const x = lowestX;
            const y = lowestY - 1;

            tiles[y][x].options = newAdj;
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;

            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{
                    .entropy = entropy,
                    .x = x,
                    .y = y,
                });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        // check right
        if (lowestX < (width - 1)) {
            const x = lowestX + 1;
            const y = lowestY;
            tiles[y][x].options = newAdj;
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;
            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{
                    .entropy = entropy,
                    .x = x,
                    .y = y,
                });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        // check bottom
        if (lowestY < (height - 1)) {
            const x = lowestX;
            const y = lowestY + 1;
            tiles[y][x].options = newAdj;
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;
            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{
                    .entropy = entropy,
                    .x = x,
                    .y = y,
                });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        // check left
        if (lowestX > 0) {
            const x = lowestX - 1;
            const y = lowestY;
            tiles[y][x].options = newAdj;
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;
            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{
                    .entropy = entropy,
                    .x = x,
                    .y = y,
                });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        try bw_writer.writeAll(ANSI_CURSOR_HOME);

        for (0..height) |y| {
            for (0..width) |x| {
                const tile = tiles[y][x].collapsed;
                const c = try selectSpline(tile);
                try bw_writer.writeAll(c.ansi);
                try bw_writer.writeAll(c.char);
                try bw_writer.writeAll(ANSI_COLOR_RESET);
            }
            try bw_writer.writeByte('\n');
        }
        try bw_writer.writeByte('\n');

        choices.clearRetainingCapacity();
        const enRecItems = entropyRecords.items;
        std.mem.sort(EntropyRecord, enRecItems, {}, struct {
            fn lessThan(_: void, a: EntropyRecord, b: EntropyRecord) bool {
                return a.entropy < b.entropy;
            }
        }.lessThan);
        lowestEntropy = enRecItems[0].entropy;
        lowestX = enRecItems[0].x;
        lowestY = enRecItems[0].y;

        _ = entropyRecords.orderedRemove(0);
        try bw_writer.print("Entropy records length: {d}\n", .{entropyRecords.items.len});
        std.time.sleep(2 * std.time.ns_per_ms);
    }

    try bw.flush();
}
