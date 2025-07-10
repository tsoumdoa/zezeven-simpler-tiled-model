const std = @import("std");
const print = std.debug.print;
const random = std.Random;
const ArrayList = std.ArrayList;

const Spline = struct {
    char: []const u8,
    ansi: []const u8,
    weight: f32,
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
    .weight = 80,
};

const coast = Spline{
    .char = "c",
    .ansi = ANSI_COLOR_YELLOW,
    .weight = 10,
};
const sea = Spline{
    .char = "s",
    .ansi = ANSI_COLOR_BLUE,
    .weight = 40,
};

const empty = Spline{
    .char = "-",
    .ansi = ANSI_COLOR_RESET,
    .weight = 0,
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

const Tile = struct {
    collapsed: *const Spline,
    entropy: f32,
    options: [3]*const Spline,
    pub const init: Tile = .{
        .collapsed = &empty,
        .entropy = std.math.floatMax(f32),
        .options = .{ &sea, &coast, &land },
    };
};

pub fn updateEntropy(tile: Tile) !f32 {
    const opts = tile.options;
    var sumWeights: f32 = 0;
    for (opts) |opt| {
        sumWeights += opt.weight;
    }
    const logSum = std.math.log(f32, 2, sumWeights);

    var weightedSum: f32 = 0;
    for (opts) |opt| {
        const weight = opt.weight;
        const logWeight = std.math.log(f32, 2, weight);
        weightedSum += (weight * logWeight);
    }

    return logSum - weightedSum / sumWeights;
}

const Orientation = enum { Top, Right, Bottom, Left };

pub inline fn newAdjacent(tile: *const Spline, orientation: Orientation) [3]*const Spline {
    var adj = [_]*const Spline{ &land, &coast, &sea };
    if (tile.char[0] == 'l') {
        switch (orientation) {
            .Top => adj = [_]*const Spline{ &land, &empty, &empty },
            .Right => adj = [_]*const Spline{ &land, &land, &coast },
            .Bottom => adj = [_]*const Spline{ &land, &land, &coast },
            .Left => adj = [_]*const Spline{ &land, &empty, &empty },
        }
    }

    if (tile.char[0] == 'c') {
        switch (orientation) {
            .Top => adj = [_]*const Spline{ &empty, &empty, &land },
            .Right => adj = [_]*const Spline{ &empty, &sea, &empty },
            .Bottom => adj = [_]*const Spline{ &empty, &sea, &empty },
            .Left => adj = [_]*const Spline{ &empty, &land, &empty },
        }
    }

    if (tile.char[0] == 's') {
        switch (orientation) {
            .Top => adj = [_]*const Spline{ &empty, &coast, &empty },
            .Right => adj = [_]*const Spline{ &empty, &sea, &empty },
            .Bottom => adj = [_]*const Spline{ &sea, &empty, &empty },
            .Left => adj = [_]*const Spline{ &empty, &coast, &empty },
        }
    }

    return adj;
}

pub inline fn checkVisited(visitedCells: *std.AutoHashMap(Point, void), x: usize, y: usize) bool {
    return visitedCells.contains(.{ .x = x, .y = y });
}

pub inline fn weightedRandomSelect(rand: *const std.Random, s: *const [3]*const Spline) *const Spline {
    var total: f32 = 0;
    var accumilativeWeight: [3]f32 = .{ 0, 0, 0 };

    for (s, 0..) |w, i| {
        if (w.weight == 0) {
            accumilativeWeight[i] = 0;
        }
        total += w.weight;
        accumilativeWeight[i] = w.weight;
    }

    const sel = rand.intRangeAtMost(i32, 0, @as(i32, @intFromFloat(total)));
    var selected: *const Spline = &empty;

    for (accumilativeWeight, 0..) |w, i| {
        if (s[i].weight == 0) continue;
        if (sel <= @as(i32, @intFromFloat(w))) {
            selected = s[i];
            break;
        } else {
            selected = s[i];
        }
    }
    return selected;
}

pub fn main() !void {
    const width = 60;
    const height = 40;
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

    lowestX = prng.random().intRangeAtMost(usize, 10, 20);
    lowestY = prng.random().intRangeAtMost(usize, 10, 20);

    var visitedCells = std.AutoHashMap(Point, void).init(
        gpa,
    );
    defer visitedCells.deinit();

    // initiate tiles
    var tiles: [height][width]Tile = @splat(@splat(.init));

    var entropyRecords = ArrayList(EntropyRecord).init(gpa);

    try bw_writer.writeAll(ANSI_CLEAR_SCREEN);
    var collapsedTotal: u32 = 0;

    try entropyRecords.append(.{ .entropy = 0, .x = lowestX, .y = lowestY });

    while (collapsed < (width * height) or entropyRecords.items.len != 0) : (collapsed += 1) {
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
        const t = tiles[lowestY][lowestX];

        const rand = prng.random();
        const selected = weightedRandomSelect(&rand, &t.options);

        // check top
        if (lowestY > 0) {
            const x = lowestX;
            const y = lowestY - 1;

            tiles[y][x].options = newAdjacent(selected, .Top);
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;

            for (entropyRecords.items, 0..) |enRec, i| {
                if (enRec.x == x and enRec.y == y) {
                    entropyRecords.items[i].entropy = entropy;
                }
            }

            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{ .entropy = entropy, .x = x, .y = y });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        // check right
        if (lowestX < (width - 1)) {
            const x = lowestX + 1;
            const y = lowestY;
            tiles[y][x].options = newAdjacent(selected, .Right);
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;

            for (entropyRecords.items, 0..) |enRec, i| {
                if (enRec.x == x and enRec.y == y) {
                    entropyRecords.items[i].entropy = entropy;
                }
            }

            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{ .entropy = entropy, .x = x, .y = y });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        // check bottom
        if (lowestY < (height - 1)) {
            const x = lowestX;
            const y = lowestY + 1;
            tiles[y][x].options = newAdjacent(selected, .Bottom);
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;

            for (entropyRecords.items, 0..) |enRec, i| {
                if (enRec.x == x and enRec.y == y) {
                    entropyRecords.items[i].entropy = entropy;
                }
            }

            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{ .entropy = entropy, .x = x, .y = y });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        // check left
        if (lowestX > 0) {
            const x = lowestX - 1;
            const y = lowestY;
            tiles[y][x].options = newAdjacent(selected, .Left);
            const entropy = try updateEntropy(tiles[y][x]);
            tiles[y][x].entropy = entropy;

            for (entropyRecords.items, 0..) |enRec, i| {
                if (enRec.x == x and enRec.y == y) {
                    entropyRecords.items[i].entropy = entropy;
                }
            }

            if (!checkVisited(&visitedCells, x, y)) {
                try entropyRecords.append(.{ .entropy = entropy, .x = x, .y = y });
                try visitedCells.put(.{ .x = x, .y = y }, {});
            }
        }

        try bw_writer.writeAll(ANSI_CURSOR_HOME);

        for (0..height) |y| {
            for (0..width) |x| {
                const tile = tiles[y][x].collapsed;
                try bw_writer.writeAll(tile.ansi);
                try bw_writer.writeAll(tile.char);
                try bw_writer.writeAll(ANSI_COLOR_RESET);
            }
            try bw_writer.writeByte('\n');
        }
        try bw_writer.writeByte('\n');

        tiles[lowestY][lowestX].collapsed = selected;
        collapsedTotal += 1;

        //print lowestX and lowestY
        // try bw_writer.print("tile options: {any}\n", .{tiles[lowestY][lowestX].options});
        for (t.options) |y| {
            try bw_writer.print("tile options: {s}\n", .{y.char});
        }
        try bw_writer.print("LowestX: {d}\n", .{lowestX});
        try bw_writer.print("LowestY: {d}\n", .{lowestY});
        try bw_writer.print("Selected: {s}\n", .{tiles[lowestY][lowestX].collapsed.char});
        try bw_writer.print("Entropy records length: {d}\n", .{entropyRecords.items.len});
        try bw_writer.print("Collapsed total: {d}\n", .{collapsedTotal});
        // std.time.sleep(9 * std.time.ns_per_ms);
    }

    try bw.flush();
}
