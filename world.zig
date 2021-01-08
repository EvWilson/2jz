const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

const typeFromBundle = @import("./comptime_utils.zig").typeFromBundle;
const arch_file = @import("./archetype.zig");
const Archetype = arch_file.Archetype;
const ArchetypeGen = arch_file.ArchetypeGen;

fn coerceToBundle(comptime T: type, comptime args: anytype) T {
    var ret: T = .{};
    std.debug.print("point ret: {}\n", .{ret});
    return ret;
}

const World = struct {
    const Self = @This();
    const DEFAULT_CAPACITY = 1024;
    const MaskType = u64;

    allocator: *Allocator,
    arch_map: AutoHashMap(MaskType, Archetype),
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
            .arch_map = AutoHashMap(MaskType, Archetype).init(allocator),
            .capacity = init_capacity,
            .mask_map = comp_map,
        };
    }

    fn deinit(self: *Self) void {
        // archetypes
        var it = self.arch_map.iterator();
        var maybe_entry = it.next();
        while (maybe_entry) |entry| {
            entry.value.deinit();
            maybe_entry = it.next();
        }
        // arch map
        self.arch_map.deinit();
        // component map
        self.mask_map.deinit();
    }

    fn spawn(self: *Self, comptime args: anytype) !void {
        const BundleType = typeFromBundle(args);
        // Create mask from component set
        const mask = self.getComponentMask(args);
        const bundle = coerceToBundle(BundleType, args);
        var maybe_arch = self.arch_map.get(mask);
        if (maybe_arch) |arch| {
            // TODO: get proper entity id
            arch.put(0, @ptrToInt(&bundle));
        } else {
            // TODO: heap allocate this arch or the deinit routine segfaults
            // Probably want to pass allocator to make function
            // PREV
            //var arch = try ArchetypeGen(BundleType).init(self.allocator);
            //var dyn = Archetype.make(BundleType, &arch, self.allocator);
            // NEW
            var dyn = try Archetype.make(BundleType, self.allocator);
            try self.arch_map.put(mask, dyn);
        }
    }

    fn query(self: *Self, comptime args: anytype) void {
        // Only take tuples as component bundles
        const type_info = @typeInfo(@TypeOf(args));
        if (type_info != .Struct or type_info.Struct.is_tuple != true) {
            @compileError("Expected tuple for components");
        }

        const mask = self.getComponentMaskTypes(args);
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

const QueryIterator = struct {
    fn next(self: *Self) void {
        return;
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
