const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const World = struct {
    const Self = @This();
    const DEFAULT_STARTING_CAPACITY = 1024;

    allocator: *Allocator,
    archetypes: ArrayList(Archetype),
    arch_map: AutoHashMap(u32, u32),
    capacity: usize,
    mask_map: AutoHashMap([]const u8, u32),
    entities: Entities,

    pub fn init(allocator: *Allocator, init_capacity: usize, comptime bitmask_type: type, comptime registry: anytype) !Self {
        // Bitmask for easy identification of component combinations
        if (@typeInfo(bitmask_type) != .Int) {
            @compileError("bitmask type must be an int");
        }
        // Ensure registry is a tuple
        //if (@typeInfo(registry) != .Struct or @typeInfo(registry).Struct.is_tuple == false) {
        //    @compileError("component registry must be a tuple");
        //}
        // Make sure bitmask field contains enough bits
        if (@typeInfo(bitmask_type).Int.bits < registry.len) {
            @compileError("not enough bits in bitmask field to create bitmask");
        }

        var comp_map = AutoHashMap([]const u8, bitmask_type).init(allocator);
        comptime var mask_val = 1;
        inline for (registry) |ty| {
            try comp_map.put(@typeName(ty), mask_val);
            mask_val = mask_val << 1;
        }

        return Self{
            .allocator = allocator,
            .arch_map = AutoHashMap(u32, u32).init(allocator),
            .archetypes = ArrayList(Archetype).init(allocator),
            .capacity = init_capacity,
            .mask_map = comp_map,
            .entities = try Entities.initCapacity(allocator, init_capacity),
        };
    }

    fn deinit(self: *Self) void {
        // archetypes
        var i: usize = 0;
        while (i < self.archetypes.items.len) : (i += 1) {
            self.archetypes.items[i].deinit();
        }
        self.archetypes.deinit();
        // arch map
        self.arch_map.deinit();
        // component map
        self.mask_map.deinit();
        // entities
        self.entities.deinit();
    }

    fn spawn(self: *Self, comptime args: anytype) !Entity {
        // Only take tuples as component bundles
        const type_info = @typeInfo(@TypeOf(args));
        if (type_info != .Struct or type_info.Struct.is_tuple != true) {
            @compileError("Expected tuple for components");
        }

        // Create mask from component set
        const mask = self.getComponentMaskStructs(args);

        // Check if we have that mask for an existing archetype set
        // If we don't
        var arch_idx: ?u32 = null;
        arch_idx = self.arch_map.get(mask);
        if (arch_idx) |idx| {
            // No-op to set up archetype cache "miss" handling
        } else {
            arch_idx = try self.addArchetype(mask);
        }

        var ent = self.entities.alloc();
        try self.archetypes.items[arch_idx.?].addEntity(ent);

        return ent;
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

    // TODO: combine w/ below
    fn getComponentMaskStructs(self: *Self, comptime component_tuple: anytype) u32 {
        var mask: u32 = 0;
        inline for (component_tuple) |str| {
            const comp_val = self.mask_map.get(@typeName(@TypeOf(str)));
            mask |= comp_val.?;
        }
        return mask;
    }

    // TODO: combine w/ above
    fn getComponentMaskTypes(self: *Self, comptime component_tuple: anytype) u32 {
        var mask: u32 = 0;
        inline for (component_tuple) |str| {
            const comp_val = self.mask_map.get(@typeName(str));
            mask |= comp_val.?;
        }
        return mask;
    }

    fn addArchetype(self: *Self, mask: u32) !u32 {
        var arch = try Archetype.initCapacity(self.allocator, Self.DEFAULT_STARTING_CAPACITY, mask);
        try self.archetypes.append(arch);
        const new_idx = @intCast(u32, self.archetypes.items.len - 1);
        try self.arch_map.put(mask, new_idx);
        return new_idx;
    }
};

const QueryIterator = struct {
    fn next(self: *Self) void {
        return;
    }
};

test "world test" {
    const allocator = std.testing.allocator;

    const CAPACITY = 1024;
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    const p: Point = .{ .x = 2, .y = 3 };

    var world = try World.init(allocator, CAPACITY, u32, .{ Point, Velocity, HitPoints });
    defer world.deinit();

    var ent = world.spawn(.{p});
    var ent2 = world.spawn(.{Point{ .x = 3, .y = 4 }});
}
