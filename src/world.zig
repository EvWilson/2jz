const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

const comptime_utils = @import("./comptime_utils.zig");
const MaskType = comptime_utils.MaskType;
const arch_file = @import("./archetype.zig");
const Archetype = arch_file.Archetype;
const ArchetypeGen = arch_file.ArchetypeGen;
const ent_file = @import("./entities.zig");
const Entity = ent_file.Entity;
const Entities = ent_file.Entities;

// Possible errors that can arise from operation
const ECSError = error{ BadSpawn, InvalidIterator, NoSuchEntity };

// The main encompassing struct for the library, its methods are effectively the
// API to the library.
pub const World = struct {
    const Self = @This();
    const DEFAULT_CAPACITY = 1024;
    const ArchetypeMap = AutoHashMap(MaskType, Archetype);

    allocator: *Allocator,
    arch_map: ArchetypeMap,
    capacity: usize,
    mask_map: AutoHashMap([]const u8, MaskType),
    entities: Entities,

    pub fn init(allocator: *Allocator, comptime registry: anytype) !Self {
        return Self.initCapacity(allocator, Self.DEFAULT_CAPACITY, registry);
    }

    pub fn initCapacity(allocator: *Allocator, capacity: usize, comptime registry: anytype) !Self {
        var comp_map = AutoHashMap([]const u8, MaskType).init(allocator);
        comptime var mask_val = 1;
        inline for (registry) |ty| {
            try comp_map.put(@typeName(ty), mask_val);
            mask_val = mask_val << 1;
        }

        return Self{
            .allocator = allocator,
            .arch_map = ArchetypeMap.init(allocator),
            .capacity = capacity,
            .mask_map = comp_map,
            .entities = try Entities.initCapacity(allocator, capacity),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.arch_map.iterator();
        while (it.next()) |entry| {
            entry.value.deinit();
        }
        self.arch_map.deinit();
        self.mask_map.deinit();
        self.entities.deinit();
    }

    pub fn spawn(self: *Self, comptime args: anytype) !Entity {
        const mask = self.componentMask(args);
        return self.spawnWithMask(mask, args);
    }

    pub fn spawnWithMask(self: *Self, mask: MaskType, comptime args: anytype) !Entity {
        const BundleType = comptime_utils.typeFromBundle(args);
        const bundle = comptime_utils.coerceToBundle(BundleType, args);
        const ent = try self.entities.alloc(mask);
        if (self.arch_map.get(mask)) |arch| {
            if (!arch.put(ent.id, @ptrToInt(&bundle))) {
                return ECSError.BadSpawn;
            }
        } else {
            var dyn = try Archetype.make(BundleType, mask, self.allocator, self.capacity);
            if (!dyn.put(ent.id, @ptrToInt(&bundle))) {
                return ECSError.BadSpawn;
            }
            try self.arch_map.put(mask, dyn);
        }
        return ent;
    }

    pub fn query(self: *Self, comptime args: anytype) ECSError!Iterator {
        const mask = self.componentMask(args);
        return self.queryWithMask(mask, args);
    }

    pub fn queryWithMask(self: *Self, mask: MaskType, comptime args: anytype) ECSError!Iterator {
        return Iterator.init(self);
    }

    pub fn remove(self: *Self, entity: Entity) bool {
        var maybe_arch = self.arch_map.get(entity.location);
        if (maybe_arch) |arch| {
            return arch.remove(entity.id);
        } else {
            return false;
        }
    }

    pub fn componentMask(self: *Self, comptime component_tuple: anytype) MaskType {
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

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    const p: Point = .{ .x = 2, .y = 3 };
    const v: Velocity = .{ .dir = 5, .magnitude = 6 };

    var world = try World.init(allocator, .{ Point, Velocity, HitPoints });
    defer world.deinit();

    var ent = try world.spawn(.{p});
    var ent2 = try world.spawn(.{Point{ .x = 3, .y = 4 }});

    const mask = world.componentMask(.{ Point, Velocity });
    const mask2 = world.componentMask(.{ p, v });
    expect(mask == mask2);

    const old_cursor = world.arch_map.get(world.componentMask(.{p})).?.cursor();
    expect(world.remove(ent));
    expect(world.arch_map.get(world.componentMask(.{p})).?.cursor() == old_cursor - 1);
}

// Used to create systems.
// Users query a World instance and receive one of these in response, with which
// they're able to loop over the world state and access the data for each entity
const Iterator = struct {
    const Self = @This();
    const IterType = World.ArchetypeMap.Iterator;

    it: IterType,
    arch: *Archetype,
    cursor: usize,
    mask: MaskType,

    fn init(world: *World) ECSError!Self {
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
            .mask = entry.value.mask(),
        };
    }

    // Update the query state to the next entry in the world
    // Returns false when done iterating
    pub fn next(self: *Self) bool {
        self.cursor += 1;
        // If we've reached the end of the current archetype's storage, move to
        //  the next and reset the cursor
        if (self.cursor > self.arch.cursor()) {
            if (!self.nextArch()) {
                return false;
            }
            self.cursor = 1;
        }
        return true;
    }

    // Internal helper method to find the next valid archetype in the map
    fn nextArch(self: *Self) bool {
        if (self.it.next()) |entry| {
            if (self.mask == self.mask & entry.value.mask()) {
                self.mask = entry.value.mask();
                self.arch = &entry.value;
            } else {
                return self.nextArch();
            }
            return true;
        } else {
            return false;
        }
    }

    // Get data from the current query index that cannot mutate the archetype's
    // memory
    pub fn data(self: *Self, comptime T: type) T {
        const type_ptr = self.arch.typeAt(@typeName(T), self.cursor - 1);
        return @intToPtr(*T, type_ptr).*;
    }

    // Get data from the current query index that can mutate the archetype's
    // memory
    pub fn dataMut(self: *Self, comptime T: type) *T {
        const type_ptr = self.arch.typeAt(@typeName(T), self.cursor - 1);
        return @intToPtr(*T, type_ptr);
    }

    // Reconstruct an Entity from a query entry (used in removal)
    pub fn entity(self: *Self) Entity {
        return .{ .id = self.arch.idAt(self.cursor - 1), .location = self.mask };
    }
};

test "query test" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };

    // Spawn and remove test
    {
        var world = try World.init(allocator, .{Point});
        defer world.deinit();
        var ent = try world.spawn(.{Point{ .x = 0, .y = 0 }});
        expect(ent.location == world.componentMask(.{Point}));

        var query = try world.query(.{Point});
        while (query.next()) {
            var pt = query.data(Point);
            expect(pt.x == 0);
            expect(pt.y == 0);
            const entity = query.entity();
            expect(entity.location == world.componentMask(.{Point}));

            expect(world.remove(ent));
        }
    }

    // Queries inclusively over multiple architectures
    {
        const p1: Point = .{ .x = 1, .y = 1 };
        const p2: Point = .{ .x = 2, .y = 2 };
        const p3: Point = .{ .x = 3, .y = 3 };

        // Spawn
        var world = try World.init(allocator, .{ Point, Velocity });
        defer world.deinit();

        var ent1 = world.spawn(.{p1});
        var ent2 = world.spawn(.{p2});
        var ent3 = world.spawn(.{p3});

        var ent4 = world.spawn(.{ Point{ .x = 4, .y = 4 }, Velocity{ .dir = 4, .magnitude = 4 } });
        var ent5 = world.spawn(.{ Point{ .x = 5, .y = 5 }, Velocity{ .dir = 5, .magnitude = 5 } });
        var ent6 = world.spawn(.{ Point{ .x = 6, .y = 6 }, Velocity{ .dir = 6, .magnitude = 6 } });

        var query = try world.query(.{Point});
        var cnt: usize = 0;
        while (query.next()) {
            cnt += 1;
            // First check that we can get the item and mutate w/o mutating
            // archetype memory
            var point: Point = query.data(Point);
            expect(point.x == cnt);
            expect(point.y == cnt);
            point.x -= 1;

            var point_check: Point = query.data(Point);
            expect(point_check.x == cnt);
            expect(point_check.y == cnt);

            // Next, check that we can get an item and mutate archetype memory
            var point_ref: *Point = query.dataMut(Point);
            expect(point_ref.x == cnt);
            expect(point_ref.y == cnt);
            point_ref.x -= 1;

            point_check = query.data(Point);
            expect(point_check.x == cnt - 1);
            expect(point_check.y == cnt);
        }
        expect(cnt == 6);
    }

    // Query excludes some archetypes
    {
        const p1: Point = .{ .x = 1, .y = 1 };
        const p2: Point = .{ .x = 2, .y = 2 };
        const p3: Point = .{ .x = 3, .y = 3 };

        // Spawn
        var world = try World.init(allocator, .{ Point, Velocity });
        defer world.deinit();

        var ent1 = world.spawn(.{Point{ .x = 1, .y = 1 }});
        var ent2 = world.spawn(.{Point{ .x = 2, .y = 2 }});
        var ent3 = world.spawn(.{Point{ .x = 3, .y = 3 }});

        // We should be skipping entries with the Velocity-only archetype
        var ent4 = world.spawn(.{Velocity{ .dir = 4, .magnitude = 4 }});
        var ent5 = world.spawn(.{Velocity{ .dir = 5, .magnitude = 5 }});
        var ent6 = world.spawn(.{Velocity{ .dir = 6, .magnitude = 6 }});

        var query = try world.query(.{Point});
        var cnt: usize = 0;
        while (query.next()) {
            cnt += 1;
            var point: Point = query.data(Point);
            expect(point.x == cnt);
            expect(point.y == cnt);
        }
        expect(cnt == 3);
    }
}

test "README example" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const Position = struct { x: u32, y: u32 };
    const HP = struct { points: u8, alive: bool };

    // Create a world from your component types
    var world = try World.init(allocator, .{ Position, HP });
    defer world.deinit();

    // Create entries with any combination of types
    var entity = try world.spawn(.{Position{ .x = 5, .y = 7 }});
    var entity2 = try world.spawn(.{ Position{ .x = 1, .y = 2 }, HP{ .points = 100, .alive = true } });

    // Query for all entries containing a Position
    var query = try world.query(.{Position});

    while (query.next()) {
        var position = query.dataMut(Position);
        position.x *= 2;

        const ent = query.entity();

        // Prints both entities' Position information
        if (world.remove(ent)) {
            //std.debug.print("removed entity: {}, with position: {}\n", .{ ent, position });
        } else {
            expect(false);
        }
    }
}
