# 2JZ

An archetype-based entity-component-system library in Zig, inspired by
(hecs)[https://github.com/Ralith/hecs] and the many other delightful ECS
libraries of the world.

### Example

```zig
const allocator = std.testing.allocator;
const expect = std.testing.expect;

const Position = struct { x: u32, y: u32 };
const Velocity = struct { dir: u6, magnitude: u32 };

// Create a world from your component types
var world = try World.init(allocator, .{ Position, Velocity });
defer world.deinit();

// Create entries with any combination of types
var entity = try world.spawn(.{Position{ .x = 5, .y = 7 }});
var entity2 = try world.spawn(.{ Position{ .x = 1, .y = 2 }, Velocity{ .dir = 13, .magnitude = 200 } });

// Query for all entries containing a Position
var query = try world.query(.{Position});

while (query.next()) {
    var position = query.dataMut(Position);
    position.x *= 2;

    const ent = query.entity();

    if (world.remove(ent)) {
        std.debug.print("removed entity: {}, with position: {}\n", .{ ent, position });
    }
}
```
