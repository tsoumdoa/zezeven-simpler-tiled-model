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
    .weight = 20,
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
    isCollapsed: bool,
    collapsed: *const Spline,
    entropy: f32,
    options: [3]*const Spline,
    pub const init: Tile = .{
        .isCollapsed = false,
        .collapsed = &empty,
        .entropy = std.math.floatMax(f32),
        .options = .{ &empty, &empty, &land },
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
            .Right => adj = [_]*const Spline{ &land, &empty, &empty },
            .Bottom => adj = [_]*const Spline{ &land, &coast, &empty },
            .Left => adj = [_]*const Spline{ &land, &empty, &empty },
        }
    }

    if (tile.char[0] == 'c') {
        switch (orientation) {
            .Top => adj = [_]*const Spline{ &land, &empty, &empty },
            .Right => adj = [_]*const Spline{ &coast, &sea, &empty },
            .Bottom => adj = [_]*const Spline{ &empty, &sea, &empty },
            .Left => adj = [_]*const Spline{ &land, &empty, &empty },
        }
    }

    if (tile.char[0] == 's') {
        switch (orientation) {
            .Top => adj = [_]*const Spline{ &sea, &coast, &empty },
            .Right => adj = [_]*const Spline{ &empty, &sea, &empty },
            .Bottom => adj = [_]*const Spline{ &sea, &empty, &empty },
            .Left => adj = [_]*const Spline{ &sea, &coast, &empty },
        }
    }

    return adj;
}

pub inline fn checkVisited(visitedCells: *std.AutoHashMap(Point, void), x: usize, y: usize) bool {
    return visitedCells.contains(.{ .x = x, .y = y });
}

pub inline fn weightedRandomSelect(rand: *const std.Random, s: *const [3]*const Spline) *const Spline {
    //this ignores the element where element has a weight of 0

    var total: f32 = 0;
    var accumilativeWeight: [3]f32 = .{ 0, 0, 0 };
    for (s, 0..) |w, i| {
        if (w.weight == 0) continue;
        total += w.weight;
        accumilativeWeight[i] = total;
    }

    const sel = rand.intRangeAtMost(i32, 0, @as(i32, @intFromFloat(total)));
    var selected: *const Spline = &empty;

    for (accumilativeWeight, 0..) |w, i| {
        if (s[i].weight == 0) continue;
        if (sel <= @as(i32, @intFromFloat(w))) {
            selected = s[i];
            break;
        }
    }
    return selected;
}

pub inline fn checkTile(
    comptime tileheight: usize,
    comptime tilewidth: usize,
    tiles: *[tileheight][tilewidth]Tile,
    x: usize,
    y: usize,
    visitedCells: *std.AutoHashMap(Point, void),
    selected: *const Spline,
    entropyRecords: *ArrayList(EntropyRecord),
    orientation: Orientation,
) !void {
    if (!tiles[y][x].isCollapsed and !checkVisited(visitedCells, x, y)) {
        tiles[y][x].options = newAdjacent(selected, orientation);
        const entropy = try updateEntropy(tiles[y][x]);
        tiles[y][x].entropy = entropy;

        try entropyRecords.append(.{ .entropy = entropy, .x = x, .y = y });
        try visitedCells.put(.{ .x = x, .y = y }, {});
    }
}

pub fn main() !void {
    const width = 60;
    const height = 20;
    var collapsed: u32 = 0;
    var lowestX: usize = 0;
    var lowestY: usize = 0;
    var collapsedTotal: u32 = 0;

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
    var entropyRecords = ArrayList(EntropyRecord).init(gpa);

    while (true) {
        _ = prng.next();
        const rand = prng.random();

        // initiate tiles
        var tiles: [height][width]Tile = @splat(@splat(.init));

        try bw_writer.writeAll(ANSI_CLEAR_SCREEN);

        try entropyRecords.append(.{ .entropy = 0, .x = lowestX, .y = lowestY });

        while (collapsed < (width * height) or entropyRecords.items.len != 0) : (collapsed += 1) {
            const enRecItems = entropyRecords.items;
            std.mem.sort(EntropyRecord, enRecItems, {}, struct {
                fn lessThan(_: void, a: EntropyRecord, b: EntropyRecord) bool {
                    return a.entropy < b.entropy;
                }
            }.lessThan);
            lowestX = enRecItems[0].x;
            lowestY = enRecItems[0].y;
            const t = tiles[lowestY][lowestX];

            const selected = weightedRandomSelect(&rand, &t.options);

            tiles[lowestY][lowestX].collapsed = selected;
            tiles[lowestY][lowestX].isCollapsed = true;
            collapsedTotal += 1;

            // check top
            if (lowestY > 0) {
                const x = lowestX;
                const y = lowestY - 1;
                try checkTile(height, width, &tiles, x, y, &visitedCells, selected, &entropyRecords, .Top);
            }

            // check right
            if (lowestX < (width - 1)) {
                const x = lowestX + 1;
                const y = lowestY;
                try checkTile(height, width, &tiles, x, y, &visitedCells, selected, &entropyRecords, .Right);
            }

            // check bottom
            if (lowestY < (height - 1)) {
                const x = lowestX;
                const y = lowestY + 1;
                try checkTile(height, width, &tiles, x, y, &visitedCells, selected, &entropyRecords, .Bottom);
            }

            // check left
            if (lowestX > 0) {
                const x = lowestX - 1;
                const y = lowestY;
                try checkTile(height, width, &tiles, x, y, &visitedCells, selected, &entropyRecords, .Left);
            }

            _ = entropyRecords.orderedRemove(0);

            try bw_writer.writeAll(ANSI_CURSOR_HOME);

            for (0..height) |y| {
                for (0..width) |x| {
                    const cell = tiles[y][x];
                    const collapsedTile = cell.collapsed;
                    try bw_writer.writeAll(collapsedTile.ansi);
                    try bw_writer.writeAll(collapsedTile.char);
                    try bw_writer.writeAll(ANSI_COLOR_RESET);
                }
                try bw_writer.writeByte('\n');
            }
            try bw_writer.writeByte('\n');

            try bw_writer.print("Selected: {s}\n", .{tiles[lowestY][lowestX].collapsed.char});
            try bw_writer.print("Entropy records length: {d}\n", .{entropyRecords.items.len});
            try bw_writer.print("Collapsed total: {d}\n", .{collapsedTotal});
        }

        try bw.flush();
        std.time.sleep(500 * std.time.ns_per_ms);
        visitedCells.clearRetainingCapacity();
        entropyRecords.clearRetainingCapacity();
        lowestX = rand.intRangeAtMost(usize, 0, (width - 1) / 2);
        lowestY = rand.intRangeAtMost(usize, 0, (height - 1) / 2);
    }
}
