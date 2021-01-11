# 2JZ

An archetype-based entity-component-system(ECS) library in Zig, inspired by
[hecs](https://github.com/Ralith/hecs) and the many other delightful ECS
libraries of the world. I'd highly recommend reading the README there for more
background on ECS in general.

### Example

```zig
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
        std.debug.print("removed entity: {}, with position: {}\n", .{ ent, position });
    }
}
```

### ECS in a Breath
ECS architecture is designed to make it easy to maintain loosely-coupled state
and behavior for complex systems, while ideally not sacrificing in performance
or developer ergonomics. Basically, entities are things, components are
descriptions of those things, and systems are ways to use and modify those
descriptions.

### What's this archetype bit about?
The naive approach to this architecture might have you arrange your components
in separate arrays of some kind, as seen in
[this easy to follow jumping off point](https://austinmorlan.com/posts/entity_component_system/).
However, this approach effectively kills your chances of pulling in all the
information you need for a given system's operation in a minimal number of cache
lines. The archetype helps to group your heterogeneous data together as densely
as possible, allowing for efficient memory access and minimal need for the
cross-referencing data structures you get otherwise.

### Acknowledgements
I'd love to be able to take a moment to give a huge thank you to the Zig
community for being such an awesome bunch of helpful hackers and tinkerers.
Tuning into the many showcases and demos from that scene is what convinced me to
keep pushing with this project, and the Discord is an amazing place to pick up
on all sorts of systems programming tidbits and adventures.

Of course, I also owe a good amount to the other open source ECS libraries of
the world, most notably hecs above, for providing helpful design pillars for me
to see, ignore, and then realize later was in fact a much better way of doing
things.
