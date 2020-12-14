const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Entities = struct {
    const Self = @This();

    allocator: *Allocator,
    stack: []Entity,
    cursor: usize,

    fn initCapacity(allocator: *Allocator, num: usize) !Self {
        var self = Self{
            .allocator = allocator,
            .stack = &[_]Entity{},
            .cursor = 0,
        };
        self.stack = try allocator.alloc(Entity, num);
        self.cursor = self.stack.len;

        var i: u32 = 0;
        while (i < num) : (i += 1) {
            self.stack[i].id = i;
        }

        return self;
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.stack.ptr[0..self.stack.len]);
    }

    fn alloc(self: *Self) Entity {
        assert(self.cursor > 0);
        self.cursor -= 1;
        return Entity{
            .id = self.stack[self.cursor].id,
        };
    }

    fn free(self: *Self, entity: Entity) void {
        assert(self.cursor < self.stack.len);
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
    const ArrayList = std.ArrayList;

    const ENTITY_TOTAL = 1024;

    var entities = try Entities.initCapacity(test_allocator, ENTITY_TOTAL);
    defer entities.deinit();

    {
        var old_cursor = entities.cursor;

        // Not explicitly testing entity id value, as the plan is eventually to
        // have the behavior be a deterministic stack layout
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
