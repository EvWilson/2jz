const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const World = struct {
    const Self = @This();

    allocator: *Allocator,
    archetypes: ArrayList(Archetype),
    capacity: usize,
    component_map: AutoHashMap([]const u8, u32),
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
            .archetypes = ArrayList(Archetype).init(allocator),
            .capacity = init_capacity,
            .component_map = comp_map,
            .entities = try Entities.initCapacity(allocator, init_capacity),
        };
    }

    fn deinit(self: *Self) void {
        // archetypes
        var i: usize = 0;
        while (i < self.archetypes.items.len) : (i += 1) {
            self.archetypes.items[i].deinit();
        }
        // component map
        self.component_map.deinit();
        // entities
        self.entities.deinit();
    }

    fn spawn(self: *Self, comptime args: anytype) Entity {
        // Only take tuples as component bundles
        const type_info = @typeInfo(@TypeOf(args));
        if (type_info != .Struct or type_info.Struct.is_tuple != true) {
            @compileError("Expected tuple for components");
        }

        // Get a
        //inline for (comptime type_info.Struct.fields) |field| {
        //    std.debug.print("Field name: {}\n", field.name);
        //}

        //const i: comptime_int = 0;
        //while (i < type_info.Struct.fields.len) : (i += 1) {
        //    std.debug.print("field: {}\n", .{type_info.Struct.fields[i].name});
        //}

        //for (std.meta.fields(@TypeOf(args))) |field| {
        //    std.debug.print("Field name: {}\n", field.name);
        //}

        //comptime var i = 0;
        //while (i < type_info.Struct.fields.len) : (i += 1) {
        //    std.debug.print("field name: {}\n", type_info.Struct.fields[i].name);
        //}

        var ent = self.entities.alloc();

        return ent;
    }
};

test "world test" {
    const allocator = std.testing.allocator;

    const CAPACITY = 1024;
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    var world = try World.init(allocator, CAPACITY, u32, .{ Point, Velocity, HitPoints });
    defer world.deinit();

    var ent = world.spawn(.{'a'});

    const tup = .{ 'a', 1, true };
    comptime const typeInfo = @typeInfo(@TypeOf(tup));
    std.debug.print("\nType info of a random tup: {}\n", .{typeInfo});

    std.debug.print("Field name: {}\n", .{typeInfo.Struct.fields[0].name});
}

const Archetype = struct {
    const Self = @This();

    allocator: *Allocator,
    capacity: usize,
    entities: []u32,

    fn initCapacity(allocator: *Allocator, num: usize) !Self {
        return Self{
            .allocator = allocator,
            .capacity = num,
            .entities = try allocator.alloc(u32, num),
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.entities.ptr[0..self.capacity]);
    }
};

test "archetype test" {
    const allocator = std.testing.allocator;

    const CAPACITY = 1024;

    var archetype = try Archetype.initCapacity(allocator, CAPACITY);
    defer archetype.deinit();
}

const Entities = struct {
    const Self = @This();

    allocator: *Allocator,
    stack: []Entity,
    capacity: usize,
    cursor: usize,

    fn initCapacity(allocator: *Allocator, num: usize) !Self {
        var self = Self{
            .allocator = allocator,
            .stack = &[_]Entity{},
            .capacity = 0,
            .cursor = 0,
        };
        self.stack = try allocator.alloc(Entity, num);
        self.capacity = self.stack.len;
        self.cursor = self.stack.len;

        var i: u32 = 0;
        while (i < num) : (i += 1) {
            self.stack[i].id = i;
        }

        return self;
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.stack.ptr[0..self.capacity]);
    }

    fn alloc(self: *Self) Entity {
        assert(self.cursor > 0);
        self.cursor -= 1;
        return Entity{
            .id = self.stack[self.cursor].id,
        };
    }

    fn free(self: *Self, entity: Entity) void {
        assert(self.cursor < self.capacity);
        defer self.cursor += 1;
        self.stack[self.cursor].id = entity.id;
    }
};

const Entity = struct {
    id: u32,
};

test "entities test" {
    const test_allocator = std.testing.allocator;
    const print = std.debug.print;
    const expect = std.testing.expect;

    const ENTITY_TOTAL = 1024;

    var entities = try Entities.initCapacity(test_allocator, ENTITY_TOTAL);
    defer entities.deinit();

    {
        var old_cursor = entities.cursor;

        // Not explicitly testing entity id value, as the plan is eventually to
        //  have the behavior be a deterministic stack layout
        var ent = entities.alloc();
        assert(old_cursor == entities.cursor + 1);
        assert(ent.id >= 0 and ent.id < ENTITY_TOTAL);

        entities.free(ent);
        assert(old_cursor == entities.cursor);
    }

    {
        var entity_holder = ArrayList(Entity).init(test_allocator);
        defer entity_holder.deinit();

        var ct: usize = ENTITY_TOTAL;
        while (ct > 0) : (ct -= 1) {
            try entity_holder.append(entities.alloc());
        }
        assert(entities.cursor == 0);

        ct = entity_holder.items.len;
        while (ct > 0) : (ct -= 1) {
            var ent = entity_holder.pop();
            assert(ent.id >= 0 and ent.id < ENTITY_TOTAL);
            entities.free(ent);
        }
        assert(entities.cursor == ENTITY_TOTAL);
    }
}
