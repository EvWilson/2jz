const std = @import("std");
const Allocator = std.mem.Allocator;

const comptime_utils = @import("./comptime_utils.zig");
const MaskType = comptime_utils.MaskType;
const IdType = comptime_utils.IdType;

pub const Entity = struct {
    id: IdType,
    location: MaskType,
};

pub const Entities = struct {
    const Self = @This();

    allocator: *Allocator,
    capacity: usize,
    stack: []IdType,
    cursor: usize,

    pub fn init_capacity(allocator: *Allocator, capacity: usize) !Self {
        var self = Self{
            .allocator = allocator,
            .capacity = capacity,
            .stack = &[_]IdType{},
            .cursor = 0,
        };
        self.stack = try allocator.alloc(IdType, self.capacity);
        self.cursor = self.stack.len;

        var i: IdType = 0;
        while (i < self.capacity) : (i += 1) {
            self.stack[i] = i;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.stack);
    }

    pub fn alloc(self: *Self, mask: MaskType) !Entity {
        if (self.cursor == 0) {
            try self.grow();
        }
        self.cursor -= 1;
        return Entity{
            .id = self.stack[self.cursor],
            .location = mask,
        };
    }

    pub fn free(self: *Self, entity: Entity) void {
        defer self.cursor += 1;
        self.stack[self.cursor] = entity.id;
    }

    fn grow(self: *Self) !void {
        const new_cap = self.capacity * 2;
        self.stack = try self.allocator.realloc(self.stack, new_cap);
        var stack_idx: IdType = 0;
        while (stack_idx < self.capacity) : (stack_idx += 1) {
            // This int cast shouldn't realistically cause an issue, given that
            //  the capacity is unlikely to meaningfully exceed the bit width of
            //  the id type.
            const cursor_val = @intCast(IdType, self.capacity);
            self.stack[stack_idx] = stack_idx + cursor_val;
        }
        self.cursor = self.capacity;
        self.capacity = new_cap;
    }

    fn print(self: *Self) void {
        std.debug.print("cursor: {}, capacity: {}, contents: ", .{ self.cursor, self.capacity });
        var i: usize = 0;
        while (i < self.capacity) : (i += 1) {
            std.debug.print("{} ", .{self.stack[i]});
        }
        std.debug.print("\n", .{});
    }
};

// Basic entity manager test
test "basic" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const ArrayList = std.ArrayList;

    const ENTITY_TOTAL = 1024;

    var entities = try Entities.init_capacity(test_allocator, ENTITY_TOTAL);
    defer entities.deinit();

    {
        var old_cursor = entities.cursor;

        var ent = try entities.alloc(1);
        expect(old_cursor == entities.cursor + 1);
        expect(ent.id >= 0 and ent.id < ENTITY_TOTAL);

        entities.free(ent);
        expect(old_cursor == entities.cursor);
    }

    {
        var entity_holder = ArrayList(Entity).init(test_allocator);
        defer entity_holder.deinit();

        var ct: usize = ENTITY_TOTAL;
        while (ct > 0) : (ct -= 1) {
            try entity_holder.append(try entities.alloc(1));
        }
        expect(entities.cursor == 0);

        ct = entity_holder.items.len;
        while (ct > 0) : (ct -= 1) {
            var ent = entity_holder.pop();
            expect(ent.id >= 0 and ent.id < ENTITY_TOTAL);
            entities.free(ent);
        }
        expect(entities.cursor == ENTITY_TOTAL);
    }
}

// Ensure that entity storage is able to grow and behaves as expected
test "storage resizing" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const ArrayList = std.ArrayList;

    var entities = try Entities.init_capacity(test_allocator, 1);
    defer entities.deinit();
    var ids = ArrayList(IdType).init(test_allocator);
    defer ids.deinit();

    // Alloc'd: 1, cap: 1
    const ent = try entities.alloc(1);
    expect(entities.capacity == 1);
    try ids.append(ent.id);
    expect(ent.id == 0);
    expect(ent.location == 1);
    // Alloc'd: 2, cap: 1 -> 2
    const ent2 = try entities.alloc(1);
    expect(entities.capacity == 2);
    try ids.append(ent2.id);
    expect(ent2.location == 1);
    // Alloc'd: 3, cap: 2 -> 4
    const ent3 = try entities.alloc(1);
    expect(entities.capacity == 4);
    try ids.append(ent3.id);
    expect(ent3.location == 1);
    // Alloc'd: 4, cap: 4
    const ent4 = try entities.alloc(1);
    expect(entities.capacity == 4);
    try ids.append(ent4.id);
    expect(ent4.location == 1);
    // Alloc'd: 5, cap: 4 -> 8
    const ent5 = try entities.alloc(1);
    expect(entities.capacity == 8);
    expect(ent4.location == 1);

    // Makes sure all received entity id's are what we're expecting
    var id_values = [_]usize{ 1, 1, 1, 1 };
    for (ids.items) |id| {
        id_values[id] = 0;
    }
    for (id_values) |value| {
        expect(value == 0);
    }
}
