const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

const comptime_utils = @import("./comptime_utils.zig");
const arch_file = @import("./archetype.zig");
const Archetype = arch_file.Archetype;
const ArchetypeGen = arch_file.ArchetypeGen;

const ECSError = error{InvalidIterator};

const World = struct {
    const Self = @This();
    const DEFAULT_CAPACITY = 1024;
    const MaskType = u64;
    const ArchetypeMap = AutoHashMap(MaskType, Archetype);

    allocator: *Allocator,
    arch_map: ArchetypeMap,
    capacity: usize,
    mask_map: AutoHashMap([]const u8, MaskType),

    pub fn init(allocator: *Allocator, init_capacity: usize, comptime registry: anytype) !Self {
        var comp_map = AutoHashMap([]const u8, MaskType).init(allocator);
        comptime var mask_val = 1;
        inline for (registry) |ty| {
            try comp_map.put(@typeName(ty), mask_val);
            mask_val = mask_val << 1;
        }

        return Self{
            .allocator = allocator,
            .arch_map = ArchetypeMap.init(allocator),
            .capacity = init_capacity,
            .mask_map = comp_map,
        };
    }

    fn deinit(self: *Self) void {
        // archetypes
        var it = self.arch_map.iterator();
        while (it.next()) |entry| {
            entry.value.deinit();
        }
        // arch map
        self.arch_map.deinit();
        // component map
        self.mask_map.deinit();
    }

    fn spawn(self: *Self, comptime args: anytype) !void {
        const BundleType = comptime_utils.typeFromBundle(args);
        // Create mask from component set
        const mask = self.getComponentMask(args);
        const bundle = comptime_utils.coerceToBundle(BundleType, args);
        if (self.arch_map.get(mask)) |arch| {
            // TODO: get proper entity id
            arch.put(0, @ptrToInt(&bundle));
        } else {
            var dyn = try Archetype.make(BundleType, self.allocator);
            dyn.put(0, @ptrToInt(&bundle));
            try self.arch_map.put(mask, dyn);
        }
    }

    fn query(self: *Self, comptime args: anytype) ECSError!Iterator {
        // Only take tuples as component bundles
        const type_info = @typeInfo(@TypeOf(args));
        if (type_info != .Struct or type_info.Struct.is_tuple != true) {
            @compileError("Expected tuple for components");
        }

        const mask = self.getComponentMask(args);
        return Iterator.init(self, mask);
    }

    fn getComponentMask(self: *Self, comptime component_tuple: anytype) MaskType {
        comptime var isType = true;
        const info = @typeInfo(@TypeOf(component_tuple[0]));
        if (info == .Struct) {
            isType = false;
        } else if (info != .Type) {
            @compileError("component tuple had erroneous type: " ++ @TypeOf(component_tuple[0]));
        }

        var mask: MaskType = 0;
        inline for (component_tuple) |field| {
            if (isType) {
                mask |= self.mask_map.get(@typeName(field)).?;
            } else {
                mask |= self.mask_map.get(@typeName(@TypeOf(field))).?;
            }
        }
        return mask;
    }
};

test "world test" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const CAPACITY = 1024;
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    const p: Point = .{ .x = 2, .y = 3 };
    const v: Velocity = .{ .dir = 5, .magnitude = 6 };

    var world = try World.init(allocator, CAPACITY, .{ Point, Velocity, HitPoints });
    defer world.deinit();

    var ent = world.spawn(.{p});
    var ent2 = world.spawn(.{Point{ .x = 3, .y = 4 }});

    const mask = world.getComponentMask(.{ Point, Velocity });
    const mask2 = world.getComponentMask(.{ p, v });
    expect(mask == mask2);
}

const Iterator = struct {
    const Self = @This();
    const IterType = World.ArchetypeMap.Iterator;

    it: IterType,
    arch: *Archetype,
    cursor: usize,
    mask: World.MaskType,

    fn init(world: *World, mask: World.MaskType) ECSError!Self {
        var it = world.arch_map.iterator();
        const maybe_entry = it.next();
        var entry: *World.ArchetypeMap.Entry = undefined;
        if (maybe_entry) |entry_ref| {
            entry = entry_ref;
        } else {
            return ECSError.InvalidIterator;
        }
        return Self{
            .it = it,
            .arch = &entry.value,
            .cursor = 0,
            .mask = mask,
        };
    }

    fn next(self: *Self) bool {
        // If we've reached the end of the current archetype's storage, move to
        //  the next and reset the cursor
        if (self.cursor == self.arch.cursor()) {
            if (self.it.next()) |entry_ptr| {
                self.arch = &entry_ptr.value;
            } else {
                // Return false if we've finished query
                return false;
            }
            self.cursor = 0;
        } else {
            self.cursor += 1;
        }
        return true;
    }

    fn get(self: *Self, comptime T: type) T {
        const type_ptr = self.arch.type_at(@typeName(T), self.cursor - 1);
        return @intToPtr(*T, type_ptr).*;
    }
};

test "query test" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const CAPACITY = 1024;
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    const p1: Point = .{ .x = 1, .y = 1 };
    const p2: Point = .{ .x = 2, .y = 2 };
    const p3: Point = .{ .x = 3, .y = 3 };
    const v: Velocity = .{ .dir = 5, .magnitude = 6 };

    var world = try World.init(allocator, CAPACITY, .{ Point, Velocity, HitPoints });
    defer world.deinit();

    var ent1 = world.spawn(.{p1});
    var ent2 = world.spawn(.{p2});
    var ent3 = world.spawn(.{p3});

    var query = try world.query(.{Point});
    var cnt: usize = 0;
    while (query.next()) {
        cnt += 1;
        const point: Point = query.get(Point);
        expect(point.x == cnt);
        expect(point.y == cnt);
    }
}
