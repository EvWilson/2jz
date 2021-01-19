const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const TypeInfo = std.builtin.TypeInfo;

const comptime_utils = @import("./comptime_utils.zig");
const MaskType = comptime_utils.MaskType;
const IdType = comptime_utils.IdType;
const Entity = @import("./entities.zig").Entity;

// Inspired by Alex Naskos' Runtime Polymorphism talk, on YouTube, @14:53
// This is entirely a proxy object for types returned by ArchetypeGen below,
// used to provide an interface over the produced structs.
// For archetype's operation, see ArchetypeGen.
pub const Archetype = struct {
    const Self = @This();
    const VTable = struct {
        cursor: fn (usize) usize,
        deinit: fn (usize) void,
        entityAt: fn (usize, usize) Entity,
        mask: fn (usize) MaskType,
        put: fn (usize, Entity, usize) bool,
        remove: fn (usize, Entity) bool,
        typeAt: fn (usize, []const u8, usize) usize,
        typeForEntity: fn (usize, []const u8, IdType) usize,
    };
    alloc: *Allocator,
    vtable: *const VTable,
    object: usize,

    pub fn cursor(self: @This()) usize {
        return self.vtable.cursor(self.object);
    }

    pub fn deinit(self: @This()) void {
        self.vtable.deinit(self.object);
    }

    pub fn entityAt(self: @This(), idx: usize) Entity {
        return self.vtable.entityAt(self.object, idx);
    }

    pub fn mask(self: @This()) MaskType {
        return self.vtable.mask(self.object);
    }

    pub fn put(self: @This(), entity: Entity, bundle_ptr: usize) bool {
        return self.vtable.put(self.object, entity, bundle_ptr);
    }

    pub fn remove(self: @This(), entity: Entity) bool {
        return self.vtable.remove(self.object, entity);
    }

    pub fn typeAt(self: @This(), typename: []const u8, elem_idx: usize) usize {
        return self.vtable.typeAt(self.object, typename, elem_idx);
    }

    pub fn typeForEntity(self: @This(), typename: []const u8, ent_id: IdType) usize {
        return self.vtable.typeForEntity(self.object, typename, ent_id);
    }

    // This function and the one below are what set up the dynamic reference to
    // the type returned by ArchetypeGen, including putting together the
    // function pointers for the vtable
    pub fn make(comptime Bundle: type, mask_val: MaskType, alloc: *Allocator, capacity: usize) !Self {
        const arch = try ArchetypeGen(Bundle).initCapacity(mask_val, alloc, capacity);
        return makeInternal(Bundle, alloc, capacity, arch);
    }

    fn makeInternal(comptime Bundle: type, alloc: *Allocator, capacity: usize, arch: anytype) Self {
        const PtrType = @TypeOf(arch);
        const bundle_info = @typeInfo(Bundle);
        return Self{
            .alloc = alloc,
            .vtable = &comptime VTable{
                .cursor = struct {
                    fn cursor(ptr: usize) usize {
                        const self = @intToPtr(PtrType, ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).cursor, .{self});
                    }
                }.cursor,
                .deinit = struct {
                    fn deinit(ptr: usize) void {
                        const self = @intToPtr(PtrType, ptr);
                        @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).deinit, .{self});
                    }
                }.deinit,
                .entityAt = struct {
                    fn entityAt(ptr: usize, idx: usize) Entity {
                        const self = @intToPtr(PtrType, ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).entityAt, .{ self, idx });
                    }
                }.entityAt,
                .mask = struct {
                    fn mask(ptr: usize) MaskType {
                        const self = @intToPtr(PtrType, ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).mask, .{self});
                    }
                }.mask,
                .put = struct {
                    fn put(ptr: usize, entity: Entity, bundle_ptr: usize) bool {
                        const self = @intToPtr(PtrType, ptr);
                        const bundle: *Bundle = @intToPtr(*Bundle, bundle_ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).put, .{ self, entity, bundle.* });
                    }
                }.put,
                .remove = struct {
                    fn remove(ptr: usize, entity: Entity) bool {
                        const self = @intToPtr(PtrType, ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).remove, .{ self, entity });
                    }
                }.remove,
                .typeAt = struct {
                    fn typeAt(ptr: usize, typename: []const u8, elem_idx: usize) usize {
                        const self = @intToPtr(PtrType, ptr);
                        const ret_ptr = @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).typeAt, .{ self, typename, elem_idx });
                        return ret_ptr;
                    }
                }.typeAt,
                .typeForEntity = struct {
                    fn typeForEntity(ptr: usize, typename: []const u8, ent_id: IdType) usize {
                        const self = @intToPtr(PtrType, ptr);
                        const ret_ptr = @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).typeForEntity, .{ self, typename, ent_id });
                        return ret_ptr;
                    }
                }.typeForEntity,
            },
            .object = @ptrToInt(arch),
        };
    }
};

test "vtable" {
    const eql = std.mem.eql;
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    // Setup
    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 7, .magnitude = 8 };
    const types = .{ Point, Velocity };
    const Bundle = comptime_utils.typeFromBundle(.{ Point, Velocity });
    var arch = try ArchetypeGen(Bundle).initCapacity(1, allocator, 1024);

    // Set up the dynamic reference
    var dyn = Archetype.makeInternal(Bundle, allocator, 1024, arch);
    defer dyn.deinit();

    // `mask`
    expect(dyn.mask() == 1);

    // `put`
    const add: Bundle = .{ .Point = p, .Velocity = v };
    expect(dyn.put(.{ .id = 0, .location = 1 }, @ptrToInt(&add)));

    // `typeAt` - ensure the produced reference can mutate the archetype memory
    // Point
    var point_ptr: usize = dyn.typeAt(@typeName(Point), 0);
    var point: *Point = @intToPtr(*Point, point_ptr);
    expect(point.x == 1);
    expect(point.y == 2);
    point.x += 10;
    expect(point.x == 11);
    expect(point.y == 2);
    point_ptr = dyn.typeAt(@typeName(Point), 0);
    point = @intToPtr(*Point, point_ptr);
    expect(point.x == 11);
    expect(point.y == 2);
    // Velocity
    const vel_ptr: usize = arch.typeAt(@typeName(Velocity), 0);
    const vel: *Velocity = @intToPtr(*Velocity, vel_ptr);
    expect(vel.dir == 7);
    expect(vel.magnitude == 8);
}

pub fn ArchetypeGen(comptime Bundle: type) type {
    const info = @typeInfo(Bundle);

    const SizeCalc = struct {
        fn offset(name: []const u8) u32 {
            comptime var ret = 0;
            inline for (info.Struct.fields) |field, idx| {
                if (std.mem.eql(u8, name, field.name)) {
                    return ret;
                }
                comptime var size = @sizeOf(@TypeOf(field.default_value.?));
                ret += size;
            }
            // This should not be reached. If it is, it means the archetype was
            //  passed a type name it does not contain
            std.debug.panic("Archetype passed a typename it did not contain: {}\n", .{name});
        }
    };

    return struct {
        const Self = @This();
        const DEFAULT_CAPACITY = 1024;

        allocator: *Allocator,
        // Number of bundles arch can currently hold
        capacity: usize,
        // Points to next available mem for bundles
        cursor: u32,
        entities: []Entity,
        mask: MaskType,
        // Memory to hold data
        type_mem: []Bundle,

        fn initCapacity(mask_val: MaskType, alloc: *Allocator, capacity: usize) !*Self {
            var result: *Self = try alloc.create(Self);
            result.allocator = alloc;
            result.capacity = capacity;
            result.cursor = 0;
            result.entities = try alloc.alloc(Entity, capacity);
            result.mask = mask_val;
            result.type_mem = try alloc.alloc(Bundle, result.capacity);
            return result;
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.entities);
            self.allocator.free(self.type_mem);
            self.allocator.destroy(self);
        }

        // Stores the given bundle into the archetype
        fn put(self: *Self, entity: Entity, bundle: Bundle) bool {
            if (self.cursor == self.capacity) {
                self.grow() catch return false;
            }
            self.type_mem[self.cursor] = bundle;
            self.entities[self.cursor] = entity;
            self.cursor += 1;
            return true;
        }

        // Returns the address of the piece of data requested
        // Must be typecast back to the desired type, left as a responsibility for
        // higher-level mechanisms
        fn typeAt(self: *Self, typename: []const u8, elem_idx: usize) usize {
            const offset = SizeCalc.offset(typename);
            const bundle: *Bundle = &self.type_mem[elem_idx];
            return @ptrToInt(bundle) + offset;
        }

        // A companion to the above method that works of an entity id rather
        // than a specified index.
        fn typeForEntity(self: *Self, typename: []const u8, ent_id: IdType) usize {
            var i: usize = 0;
            while (i < self.cursor) : (i += 1) {
                if (self.entities[i].id == ent_id) {
                    break;
                }
            }
            // Zero value can be assumed to be a bad pointer at higher levels
            // (Entity not found)
            if (i == self.cursor) {
                return 0;
            }
            const offset = SizeCalc.offset(typename);
            const bundle: *Bundle = &self.type_mem[i];
            return @ptrToInt(bundle) + offset;
        }

        // Returns the entity data stored at the given index
        fn entityAt(self: *Self, idx: usize) Entity {
            return self.entities[idx];
        }

        // Remove the given entity id
        fn remove(self: *Self, entity: Entity) bool {
            var idx: usize = 0;
            while (idx != self.cursor + 1) : (idx += 1) {
                if (self.entities[idx].id == entity.id) {
                    self.removeIdx(idx);
                    return true;
                }
            }
            return false;
        }

        // Effectively works as a swap-remove
        // Copies bundle at end of array to indicated location and decrements
        // cursor
        fn removeIdx(self: *Self, idx: usize) void {
            self.type_mem[idx] = self.type_mem[self.cursor];
            self.entities[idx] = self.entities[self.cursor];
            self.cursor -= 1;
        }

        fn has(self: *Self, comptime comp_type: type) bool {
            const other = @typeName(comp_type);
            inline for (info.Struct.fields) |field| {
                if (std.mem.eql(u8, other, @typeName(@TypeOf(field.default_value.?)))) {
                    return true;
                }
            }
            return false;
        }

        fn mask(self: *Self) MaskType {
            return self.mask;
        }

        fn cursor(self: *Self) usize {
            return self.cursor;
        }

        // Increase the storage size once needed
        fn grow(self: *Self) !void {
            const new_cap = self.capacity * 2;
            self.type_mem = try self.allocator.realloc(self.type_mem, new_cap);
            self.entities = try self.allocator.realloc(self.entities, new_cap);
            self.capacity = new_cap;
        }
    };
}

test "basic" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    // Setup
    const Bundle = comptime_utils.typeFromBundle(.{ Point, Velocity });
    var arch = try ArchetypeGen(Bundle).initCapacity(1, allocator, 1024);
    defer arch.deinit();
    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 3, .magnitude = 4 };

    // `has` testing
    expect(arch.has(Point));
    expect(!arch.has(HitPoints));

    // `put` testing
    expect(arch.cursor == 0);
    const ent = Entity{ .id = 0, .location = 1 };
    expect(arch.put(ent, .{ .Point = p, .Velocity = v }));
    expect(arch.cursor == 1);

    // Get with type
    // Point
    var point_ptr: usize = arch.typeAt(@typeName(Point), 0);
    var point: *Point = @intToPtr(*Point, point_ptr);
    expect(point.x == 1);
    expect(point.y == 2);
    point.x += 10;
    expect(point.x == 11);
    expect(point.y == 2);
    point_ptr = arch.typeAt(@typeName(Point), 0);
    point = @intToPtr(*Point, point_ptr);
    expect(point.x == 11);
    expect(point.y == 2);
    // Velocity
    var vel_ptr: usize = arch.typeAt(@typeName(Velocity), 0);
    var vel: *Velocity = @intToPtr(*Velocity, vel_ptr);
    expect(vel.dir == 3);
    expect(vel.magnitude == 4);

    // Get with entity
    // Point
    point_ptr = arch.typeForEntity(@typeName(Point), ent.id);
    point = @intToPtr(*Point, point_ptr);
    expect(point.x == 11);
    expect(point.y == 2);
    // Velocity
    vel_ptr = arch.typeForEntity(@typeName(Velocity), ent.id);
    vel = @intToPtr(*Velocity, vel_ptr);
    expect(vel.dir == 3);
    expect(vel.magnitude == 4);
    // Check that we can get an error case
    expect(arch.typeForEntity(@typeName(Point), 1000) == 0);
}

test "storage resizing" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    // Setup
    const Bundle = comptime_utils.typeFromBundle(.{ Point, Velocity });
    var arch = try ArchetypeGen(Bundle).initCapacity(1, allocator, 1);
    defer arch.deinit();

    // Spawned: 1, cap: 1
    expect(arch.put(.{ .id = 0, .location = 1 }, .{ .Point = .{ .x = 1, .y = 1 }, .Velocity = .{ .dir = 1, .magnitude = 1 } }));
    const pt = @intToPtr(*Point, arch.typeAt(@typeName(Point), 0));
    expect(pt.x == 1 and pt.y == 1);
    const vel = @intToPtr(*Velocity, arch.typeAt(@typeName(Velocity), 0));
    expect(vel.dir == 1 and vel.magnitude == 1);

    // Spawned: 2, cap: 1 -> 2
    expect(arch.put(.{ .id = 1, .location = 1 }, .{ .Point = .{ .x = 2, .y = 2 }, .Velocity = .{ .dir = 2, .magnitude = 2 } }));
    const pt2 = @intToPtr(*Point, arch.typeAt(@typeName(Point), 1));
    expect(pt2.x == 2 and pt2.y == 2);
    const vel2 = @intToPtr(*Velocity, arch.typeAt(@typeName(Velocity), 1));
    expect(vel2.dir == 2 and vel2.magnitude == 2);
    // Check first index again after resizing, just in case
    const pt1 = @intToPtr(*Point, arch.typeAt(@typeName(Point), 0));
    expect(pt1.x == 1 and pt1.y == 1);
    const vel1 = @intToPtr(*Velocity, arch.typeAt(@typeName(Velocity), 0));
    expect(vel1.dir == 1 and vel1.magnitude == 1);

    // Spawned: 3, cap: 2 -> 4
    expect(arch.put(.{ .id = 2, .location = 1 }, .{ .Point = .{ .x = 3, .y = 3 }, .Velocity = .{ .dir = 3, .magnitude = 3 } }));
    const pt3 = @intToPtr(*Point, arch.typeAt(@typeName(Point), 2));
    expect(pt3.x == 3 and pt3.y == 3);
    const vel3 = @intToPtr(*Velocity, arch.typeAt(@typeName(Velocity), 2));
    expect(vel3.dir == 3 and vel3.magnitude == 3);
}
