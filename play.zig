const std = @import("std");
const print = std.debug.print;
const HashMap = std.AutoHashMap;
const allocator = std.testing.allocator;

test "play" {
    print("\n", .{});
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

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
}

const Registrar = struct {
    const Self = @This();
};
