const std = @import("std");
const print = std.debug.print;
const Timer = std.time.Timer;

const ecs = @import("ecs");

// Benchmarking strategy inspired by:
// https://csherratt.github.io/blog/posts/specs-and-legion/

// Purposefully leaving out component addition/removal for now, as it isn't an
// emphasis for this library

const A = struct { val: u32 };
const B = struct { val: u32 };
const C = struct { val: u32 };
const D = struct { val: u32 };
const E = struct { val: u32 };
const F = struct { val: u32 };
const G = struct { val: u32 };
const H = struct { val: u32 };

pub fn main() !void {
    // Create component sets to use below
    const OneComp = .{A};
    const TwoComp = .{ A, B };
    const ThreeComp = .{ A, B, C };
    const FourComp = .{ A, B, C, D };
    const FiveComp = .{ A, B, C, D, E };
    const SixComp = .{ A, B, C, D, E, F };
    const SevenComp = .{ A, B, C, D, E, F, G };
    const EightComp = .{ A, B, C, D, E, F, G, H };

    // Other setup
    var RUNS: usize = 1000;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;

    print("NOTE: All times printed are in nanoseconds. Care when testing on Windows for potentially imprecise timer readings (see std.time.Timer documentation\n\n", .{});

    // 1. Creating 1000 entities, 1-6 components attached
    // Measure time to create one entity
    {
        print("Test 1 - spawning entities:\n", .{});
        const COUNT = 1000;
        {
            const comp_bundle = .{A{ .val = 1 }};
            try runTestOne(allocator, RUNS, COUNT, 1, OneComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 } };
            try runTestOne(allocator, RUNS, COUNT, 2, TwoComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 } };
            try runTestOne(allocator, RUNS, COUNT, 3, ThreeComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 } };
            try runTestOne(allocator, RUNS, COUNT, 4, FourComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 }, E{ .val = 5 } };
            try runTestOne(allocator, RUNS, COUNT, 5, FiveComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 }, E{ .val = 5 }, F{ .val = 6 } };
            try runTestOne(allocator, RUNS, COUNT, 6, SixComp, comp_bundle);
        }
        print("\n", .{});
    }
    // Removing entities
    // 2. Removing 1000 entities, 1-8 components attached
    {
        print("Test 2 - removing entities, from within a query:\n", .{});
        const COUNT = 1000;
        {
            const comp_bundle = .{A{ .val = 1 }};
            try runTestTwo(allocator, RUNS, COUNT, 1, OneComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 } };
            try runTestTwo(allocator, RUNS, COUNT, 2, TwoComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 } };
            try runTestTwo(allocator, RUNS, COUNT, 3, ThreeComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 } };
            try runTestTwo(allocator, RUNS, COUNT, 4, FourComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 }, E{ .val = 5 } };
            try runTestTwo(allocator, RUNS, COUNT, 5, FiveComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 }, E{ .val = 5 }, F{ .val = 6 } };
            try runTestTwo(allocator, RUNS, COUNT, 6, SixComp, comp_bundle);
        }
        print("\n", .{});
    }

    // Iteration tests
    // 3. 1000 entities, 1-8 components
    {
        print("Test 3 - iteration, over 1000 entities:\n", .{});
        const COUNT = 1000;
        {
            const comp_bundle = .{A{ .val = 1 }};
            try runTestThree(allocator, RUNS, COUNT, 1, OneComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 } };
            try runTestThree(allocator, RUNS, COUNT, 2, TwoComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 } };
            try runTestThree(allocator, RUNS, COUNT, 3, ThreeComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 } };
            try runTestThree(allocator, RUNS, COUNT, 4, FourComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 }, E{ .val = 5 } };
            try runTestThree(allocator, RUNS, COUNT, 5, FiveComp, comp_bundle);
        }
        {
            const comp_bundle = .{ A{ .val = 1 }, B{ .val = 2 }, C{ .val = 3 }, D{ .val = 4 }, E{ .val = 5 }, F{ .val = 6 } };
            try runTestThree(allocator, RUNS, COUNT, 6, SixComp, comp_bundle);
        }
        print("\n", .{});
    }
    // 4. 10-10k entities, 1 component
    {
        print("Test 4 - iteration, 10-10k entites, 1 component:\n", .{});
        try runTestFour(allocator, RUNS, 10);
        try runTestFour(allocator, RUNS, 100);
        try runTestFour(allocator, RUNS, 1000);
        try runTestFour(allocator, RUNS, 10000);
        print("\n", .{});
    }
    // 5. 1-1000 entities per archetype, 32 unique archetypes
    {
        print("Test 5 - iteration, 1-1000 entities per archetype, 32 archetypes:\n", .{});
        try runTestFive(allocator, RUNS, 1, 32);
        try runTestFive(allocator, RUNS, 10, 32);
        try runTestFive(allocator, RUNS, 100, 32);
        try runTestFive(allocator, RUNS, 1000, 32);
        try runTestFive(allocator, RUNS, 10000, 32);
        print("\n", .{});
    }
    // 6. 2-component join (16 bytes total), 16k entities, varying %s of entities with those 2 components
    // TODO
    // 7. See 6, 1M entities
    // TODO
    // 8. See 6, 2 component join equaling 64 bytes
    // TODO
}

fn runTestOne(alloc: *std.mem.Allocator, run_count: usize, ent_count: usize, comp_count: usize, comp_types: anytype, comptime comp_bundle: anytype) !void {
    print("{} component - ", .{comp_count});
    var total: u64 = 0;
    var run: usize = 0;
    while (run < run_count) : (run += 1) {
        var world = try ecs.World.initCapacity(alloc, ent_count, comp_types);
        defer world.deinit();

        var i: usize = 0;
        var timer = try Timer.start();
        while (i < ent_count) : (i += 1) {
            const ent = try world.spawn(comp_bundle);
        }
        const time = timer.read();
        total += time;
    }
    const time = total / run_count;
    print("time elapsed: {}, per entity: {}\n", .{ time, @intToFloat(f64, time) / @intToFloat(f64, ent_count) });
}

fn runTestTwo(alloc: *std.mem.Allocator, run_count: usize, ent_count: usize, comp_count: usize, comp_types: anytype, comptime comp_bundle: anytype) !void {
    print("{} component - ", .{comp_count});
    var total: u64 = 0;
    var run: usize = 0;
    while (run < run_count) : (run += 1) {
        var world = try ecs.World.initCapacity(alloc, ent_count, comp_types);
        defer world.deinit();

        var i: usize = 0;
        while (i < ent_count) : (i += 1) {
            const ent = try world.spawn(comp_bundle);
        }

        var timer = try Timer.start();
        var query = try world.query(comp_types);
        while (query.next()) {
            const ent = query.entity();
            std.testing.expect(world.remove(ent));
        }
        const time = timer.read();
        total += time;
    }
    const time = total / run_count;
    print("time elapsed: {}, per entity: {}\n", .{ time, @intToFloat(f64, time) / @intToFloat(f64, ent_count) });
}

fn runTestThree(alloc: *std.mem.Allocator, run_count: usize, ent_count: usize, comp_count: usize, comp_types: anytype, comptime comp_bundle: anytype) !void {
    print("{} component - ", .{comp_count});
    var world = try ecs.World.initCapacity(alloc, ent_count, comp_types);
    defer world.deinit();

    var i: usize = 0;
    while (i < ent_count) : (i += 1) {
        const ent = try world.spawn(comp_bundle);
    }

    const mask = world.componentMask(comp_types);
    var run: usize = 0;
    var total: u64 = 0;
    while (run < run_count) : (run += 1) {
        var timer = try Timer.start();
        var query = try world.queryWithMask(mask, comp_types);
        while (query.next()) {
            const a = query.data(A);
        }
        const time = timer.read();
        total += time;
    }
    const time = total / run_count;
    print("time elapsed: {}, per entity: {}\n", .{ time, @intToFloat(f64, time) / @intToFloat(f64, ent_count) });
}

fn runTestFour(alloc: *std.mem.Allocator, run_count: usize, ent_count: usize) !void {
    print("{} entities - ", .{ent_count});
    var world = try ecs.World.initCapacity(alloc, ent_count, .{A});
    defer world.deinit();

    var i: usize = 0;
    while (i < ent_count) : (i += 1) {
        const ent = try world.spawn(.{A{ .val = 1 }});
    }

    const mask = world.componentMask(.{A});
    var run: usize = 0;
    var total: u64 = 0;
    while (run < run_count) : (run += 1) {
        var timer = try Timer.start();
        var query = try world.queryWithMask(mask, .{A});
        while (query.next()) {
            const a = query.data(A);
        }
        const time = timer.read();
        total += time;
    }
    const time = total / run_count;
    print("time elapsed: {}, per entity: {}\n", .{ time, @intToFloat(f64, time) / @intToFloat(f64, ent_count) });
}

fn runTestFive(alloc: *std.mem.Allocator, run_count: usize, ent_count: usize, num_archetypes: usize) !void {
    print("{} entities per arch - ", .{ent_count});
    var world = try ecs.World.initCapacity(alloc, ent_count, .{A});
    defer world.deinit();

    // Create NUM_ARCHETYPES archetypes each holding ent_count entities
    // Cheat a little bit by using different mask values to create new arches
    const orig_mask = world.componentMask(.{A});
    var i: usize = 0;
    var maskVal: ecs.MaskType = 1;
    while (i < num_archetypes) : (i += 1) {
        var j: usize = 0;
        while (j < ent_count) : (j += 1) {
            const ent = try world.spawnWithMask(maskVal, .{A{ .val = 1 }});
        }
        maskVal = (maskVal * 2) | orig_mask;
    }

    var run: usize = 0;
    var total: u64 = 0;
    while (run < run_count) : (run += 1) {
        var timer = try Timer.start();
        var query = try world.queryWithMask(orig_mask, .{A});
        while (query.next()) {
            const a = query.data(A);
        }
        const time = timer.read();
        total += time;
    }
    const time = total / run_count;
    print("time elapsed: {}, per entity: {}\n", .{ time, @intToFloat(f64, time) / @intToFloat(f64, ent_count * num_archetypes) });
}
