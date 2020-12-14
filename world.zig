const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

const Archetype = @import("./archetype.zig").Archetype;

const World = struct {
    const Self = @This();
    const DEFAULT_STARTING_CAPACITY = 1024;
    const MaskType = u64;

    allocator: *Allocator,
    arch_map: AutoHashMap(u32, u32),
    capacity: usize,
    mask_map: AutoHashMap([]const u8, MaskType),
    //entities: Entities,
    //registry: anytype,

    pub fn init(allocator: *Allocator, init_capacity: usize, comptime registry: anytype) !Self {
        var comp_map = AutoHashMap([]const u8, MaskType).init(allocator);
        comptime var mask_val = 1;
        inline for (registry) |ty| {
            try comp_map.put(@typeName(ty), mask_val);
            mask_val = mask_val << 1;
        }

        return Self{
            .allocator = allocator,
            .arch_map = AutoHashMap(u32, u32).init(allocator),
            .capacity = init_capacity,
            .mask_map = comp_map,
            //.entities = try Entities.initCapacity(allocator, init_capacity),
            //.registry = registry,
        };
    }

    fn deinit(self: *Self) void {
        // arch map
        self.arch_map.deinit();
        // component map
        self.mask_map.deinit();
        // entities
        //self.entities.deinit();
    }

    fn spawn(self: *Self, comptime args: anytype) !void {
        // Create mask from component set
        const mask = self.getComponentMask(args);
    }

    fn query(self: *Self, comptime args: anytype) void {
        std.debug.print("in query now\n", .{});
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
    //std.debug.print("mask: {}, mask2: {}\n", .{ mask, mask2 });
    expect(mask == mask2);
}
