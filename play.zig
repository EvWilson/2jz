const std = @import("std");
const allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const HashMap = std.AutoHashMap;
const print = std.debug.print;

const DEFAULT_SIZE = 1024;
const Point = struct { x: u32, y: u32 };
const Velocity = struct { dir: u6, magnitude: u32 };
const HitPoints = struct { hp: u32 };

test "type fiddling" {
    print("\n", .{});

    const BitMaskField = u64;

    print("type name point: {}\n", .{@typeName(Point)});

    comptime const reg_tup = .{ Point, Velocity, HitPoints };
    comptime const reg_arr = [_]type{ Point, Velocity, HitPoints };

    var map = HashMap([]const u8, BitMaskField).init(allocator);
    defer map.deinit();

    // Experimenting w/ type naming
    {
        const ty = @TypeOf(reg_tup);
        const type_info = @typeInfo(ty);
        const fields = type_info.Struct.fields.len;
        print("tup is tup: {}\n", .{type_info.Struct.is_tuple});
        std.debug.print("Size of fields: {}\n", .{fields});
        std.debug.print("type name: {}\n", .{@typeName(ty)});

        var p: Point = .{ .x = 5, .y = 7 };
        print("point type name: {}\n", .{@typeName(@TypeOf(p))});
    }

    // PoC for comptime-aided bitmask construction
    {
        // Make sure bitmask field contains enough bits
        if (@typeInfo(BitMaskField).Int.bits < reg_tup.len) {
            @compileError("not enough bits in BitMaskField to create bitmask");
        }
        comptime var mask_val = 1;
        inline for (reg_tup) |ty| {
            try map.put(@typeName(ty), mask_val);
            mask_val = mask_val << 1;
        }

        print("mask val of Point: {}\n", .{map.get(@typeName(Point))});
        print("mask val of Velocity: {}\n", .{map.get(@typeName(Velocity))});
        print("mask val of HitPoints: {}\n", .{map.get(@typeName(HitPoints))});
    }

    // Generate bitmask from type sets
    {
        const physics = .{ Point, Velocity };
        var mask: BitMaskField = 0;
        inline for (physics) |ty| {
            const field = map.get(@typeName(ty));
            mask |= field.?;
        }
        print("physics mask: {}\n", .{mask});
    }

    // Generate bitmask from structs themselves
    {
        const p: Point = .{ .x = 2, .y = 3 };
        const v: Velocity = .{ .dir = 2, .magnitude = 200 };
        const physics = .{ p, v };
        var mask: BitMaskField = 0;
        inline for (physics) |str| {
            const field = map.get(@typeName(@TypeOf(str)));
            mask |= field.?;
        }
        print("physics mask on actual structs: {}\n", .{mask});
    }
}

test "type array" {
    const TypeInfo = std.builtin.TypeInfo;

    const Garbage = union(enum) {
        One: i32,
        Two: u8,
        Three: void,
    };
    const garbo_mem = try allocator.alloc(Garbage, 5);
    defer allocator.free(garbo_mem);
    garbo_mem[0] = Garbage{ .One = 5 };
    switch (garbo_mem[0]) {
        .One => |value| expect(value == 5),
        else => unreachable,
    }

    //const type_mem = try allocator.alloc(TypeInfo, 1024);
    //allocator.free(type_mem);
}

test "untyped memory" {
    print("\n", .{});

    const p = Point{ .x = 150, .y = 200 };
    const v = Velocity{ .dir = 12, .magnitude = 8 };
    const hp = HitPoints{ .hp = 90 };

    const type_tup = .{ Point, Velocity };

    // Try to get size of these type tuples
    {
        print("Size of point: {}, velocity: {}\n", .{ @sizeOf(Point), @sizeOf(Velocity) });
        comptime var sz = 0;
        inline for (@typeInfo(@TypeOf(type_tup)).Struct.fields) |typ| {
            //print("Adding size of {} which is: {}\n", .{ typ, @sizeOf(typ.default_value.?) });
            sz += @sizeOf(typ.default_value.?);
        }
        print("Size with comptime calc: {}\n", .{sz});
    }

    // Try to alloc area of mem, store structs, then retrieve later
    {
        // Figure out size and allocate
        comptime var sz = 0;
        inline for (@typeInfo(@TypeOf(type_tup)).Struct.fields) |field| {
            sz += @sizeOf(field.default_value.?);
        }
        print("Struct seems to be {} bytes large, thus allocating {}*{} bytes\n", .{ sz, sz, DEFAULT_SIZE });
        var mem = try allocator.alloc(u8, sz * DEFAULT_SIZE);
        defer allocator.free(mem);

        // Try to start adding things to this section of memory
        var cursor: usize = 0;
        while (cursor < 10) : (cursor += 1) {
            const pt = Point{ .x = @intCast(u32, cursor), .y = @intCast(u32, cursor) };
            const vel = Velocity{ .dir = @intCast(u6, cursor), .magnitude = @intCast(u6, cursor) };
            // Put structs in format we can expect in future
            const tup = .{ pt, vel };
            print("{}\n", .{tup});

            //@memcpy(mem.ptr + cursor * sz, &tup, sz);
        }

        cursor = 0;
        while (cursor < 10) : (cursor += 1) {
            //const tup = @as(@TypeOf(.{ Point, Velocity }), mem[cursor * sz .. cursor * sz + sz]);
        }
    }
}
