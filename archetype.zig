const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Archetype = struct {
    const Self = @This();

    allocator: *Allocator,
    cursor: usize,
    entities: []u32,

    fn initCapacity(allocator: *Allocator, cap: usize, comptime tup: anytype) !Self {
        comptime const tup_len = @typeInfo(@TypeOf(tup)).Struct.fields.len;
        const type_mem = try allocator.alloc(type, tup_len);
        return Self{
            .allocator = allocator,
            .cursor = 0,
            .entities = try allocator.alloc(u32, cap),
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.entities.ptr[0..self.entities.len]);
    }

    fn addEntity(self: *Self, ent: Entity) !void {
        self.entities[self.cursor] = ent.id;
        self.cursor += 1;
    }
};

test "archetype test" {
    const allocator = std.testing.allocator;

    const CAPACITY = 1024;
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u8 };

    const p1 = Point{ .x = 3, .y = 4 };
    const v1 = Velocity{ .dir = 2, .magnitude = 100 };

    var archetype = try Archetype.initCapacity(allocator, CAPACITY, .{ @TypeOf(p1), @TypeOf(v1) });
    defer archetype.deinit();
}
