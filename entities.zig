const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

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
        while (i < num) : (i += 1) {
            self.stack[i] = i;
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.stack);
    }

    pub fn alloc(self: *Self, mask: MaskType) !Entity {
        // TODO: grow on empty
        if (self.cursor == 0) {
            try self.grow();
        }
        self.cursor -= 1;
        return .{
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

        self.capacity = new_cap;
    }
};

test "entities test" {
    const test_allocator = std.testing.allocator;
    const expect = std.testing.expect;
    const ArrayList = std.ArrayList;

    const ENTITY_TOTAL = 1024;

    var entities = try Entities.init_capacity(test_allocator, ENTITY_TOTAL);
    defer entities.deinit();

    {
        var old_cursor = entities.cursor;

        // Not explicitly testing entity id value, as the plan is eventually to
        // have the behavior be a deterministic stack layout
        var ent = entities.alloc(1);
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
            try entity_holder.append(entities.alloc(1));
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
