const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const TypeInfo = std.builtin.TypeInfo;

const comptime_utils = @import("./comptime_utils.zig");
const MaskType = comptime_utils.MaskType;
const IdType = comptime_utils.IdType;

// Inspired by Alex Naskos' Runtime Polymorphism talk, 14:53
// This is entirely a proxy object for types returned by ArchetypeGen below,
// used to provide an interface over the produced generics.
// For archetype's operation, see ArchetypeGen.
pub const Archetype = struct {
    const Self = @This();
    const VTable = struct {
        deinit: fn (usize) void,
        cursor: fn (usize) usize,
        put: fn (usize, IdType, usize) bool,
        remove: fn (usize, IdType) bool,
        type_at: fn (usize, []const u8, usize) usize,
        // For diagnostic purposes
        print_at: fn (usize, usize) void,
    };
    alloc: *Allocator,
    vtable: *const VTable,
    object: usize,

    pub fn deinit(self: @This()) void {
        self.vtable.deinit(self.object);
    }

    pub fn cursor(self: @This()) usize {
        return self.vtable.cursor(self.object);
    }

    pub fn put(self: @This(), id: IdType, bundle_ptr: usize) bool {
        return self.vtable.put(self.object, id, bundle_ptr);
    }

    pub fn remove(self: @This(), id: IdType) bool {
        return self.vtable.remove(self.object, id);
    }

    pub fn type_at(self: @This(), typename: []const u8, elem_idx: usize) usize {
        return self.vtable.type_at(self.object, typename, elem_idx);
    }

    pub fn print_at(self: @This(), idx: usize) void {
        self.vtable.print_at(self.object, idx);
    }

    // This function and the one below are what set up the dynamic reference to
    // the type returned by ArchetypeGen, including putting together the
    // function pointers for the vtable
    pub fn make(comptime Bundle: type, alloc: *Allocator) !Self {
        const arch = try ArchetypeGen(Bundle).init(alloc);
        return makeInternal(Bundle, alloc, arch);
    }

    fn makeInternal(comptime Bundle: type, alloc: *Allocator, arch: anytype) Self {
        const PtrType = @TypeOf(arch);
        const bundle_info = @typeInfo(Bundle);
        return Self{
            .alloc = alloc,
            .vtable = &comptime VTable{
                .deinit = struct {
                    fn deinit(ptr: usize) void {
                        const self = @intToPtr(PtrType, ptr);
                        @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).deinit, .{self});
                    }
                }.deinit,
                .cursor = struct {
                    fn cursor(ptr: usize) usize {
                        const self = @intToPtr(PtrType, ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).cursor, .{self});
                    }
                }.cursor,
                .put = struct {
                    fn put(ptr: usize, id: IdType, bundle_ptr: usize) bool {
                        const self = @intToPtr(PtrType, ptr);
                        const bundle: *Bundle = @intToPtr(*Bundle, bundle_ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).put, .{ self, id, bundle.* });
                    }
                }.put,
                .remove = struct {
                    fn remove(ptr: usize, id: IdType) bool {
                        const self = @intToPtr(PtrType, ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).remove, .{ self, id });
                    }
                }.remove,
                .type_at = struct {
                    fn type_at(ptr: usize, typename: []const u8, elem_idx: usize) usize {
                        const self = @intToPtr(PtrType, ptr);
                        const ret_ptr = @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).type_at, .{ self, typename, elem_idx });
                        return ret_ptr;
                    }
                }.type_at,

                .print_at = struct {
                    fn print_at(ptr: usize, idx: usize) void {
                        const self = @intToPtr(PtrType, ptr);
                        @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).print_at, .{ self, idx });
                    }
                }.print_at,
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
    var arch = try ArchetypeGen(Bundle).init(allocator);

    // Set up the dynamic reference
    var dyn = Archetype.makeInternal(Bundle, allocator, arch);
    defer dyn.deinit();

    // `put`
    const add: Bundle = .{ .Point = p, .Velocity = v };
    expect(dyn.put(0, @ptrToInt(&add)));

    // `type_at` - ensure the produced reference can mutate the archetype memory
    // Point
    const point_ptr: usize = dyn.type_at(@typeName(Point), 0);
    const point: *Point = @intToPtr(*Point, point_ptr);
    expect(point.x == 1);
    expect(point.y == 2);
    point.x += 10;
    expect(point.x == 11);
    expect(point.y == 2);
    // Check first 4 bytes of memory (Point x) to make sure it's mutated
    var i: usize = 0;
    var total: usize = 0;
    while (i < 4) : (i += 1) {
        total += arch.type_mem[i];
    }
    expect(total == 11);
    // Velocity
    const vel_ptr: usize = arch.type_at(@typeName(Velocity), 0);
    const vel: *Velocity = @intToPtr(*Velocity, vel_ptr);
    expect(vel.dir == 7);
    expect(vel.magnitude == 8);
}

pub fn ArchetypeGen(comptime Bundle: type) type {
    const info = @typeInfo(Bundle);

    const SizeCalc = struct {
        fn offset(name: []const u8) u32 {
            comptime var size = 0;
            inline for (info.Struct.fields) |field, idx| {
                if (std.mem.eql(u8, name, field.name)) {
                    return size;
                }
                size += @sizeOf(@TypeOf(field.default_value.?));
            }
            // This should not be reached. If it is, it means the archetype was
            //  passed a type name it does not contain
            std.debug.assert(false);
            return 0;
        }
    };

    return struct {
        const Self = @This();
        const DEFAULT_CAPACITY = 1024;

        allocator: *Allocator,
        // Total size of all structs in the arch
        bundle_size: u32,
        // Number of bundles arch can currently hold
        capacity: u32,
        // Points to next available mem for bundles
        cursor: u32,
        entity_ids: []MaskType,
        // Memory to hold data
        type_mem: []u8,

        fn init(alloc: *Allocator) !*Self {
            return Self.init_capacity(alloc, Self.DEFAULT_CAPACITY);
        }

        fn init_capacity(alloc: *Allocator, capacity: u32) !*Self {
            var result: *Self = try alloc.create(Self);
            result.allocator = alloc;
            result.capacity = capacity;
            result.cursor = 0;
            result.entity_ids = try alloc.alloc(MaskType, Self.DEFAULT_CAPACITY);
            comptime var total_size = 0;
            inline for (info.Struct.fields) |field, idx| {
                const size = @sizeOf(@TypeOf(field.default_value.?));
                total_size += size;
            }
            result.bundle_size = total_size;
            result.type_mem = try alloc.alloc(u8, result.bundle_size * result.capacity);
            return result;
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.entity_ids);
            self.allocator.free(self.type_mem);
            self.allocator.destroy(self);
        }

        // Stores the given bundle into the archetype
        fn put(self: *Self, id: IdType, bundle: Bundle) bool {
            if (self.cursor == self.capacity) {
                self.grow() catch return false;
            }
            comptime var offset = 0;
            const field_info = @typeInfo(@TypeOf(bundle));
            var dest_slice = self.type_mem;
            dest_slice.ptr += self.cursor * self.bundle_size;

            inline for (field_info.Struct.fields) |field, idx| {
                const field_bytes = std.mem.asBytes(&@field(bundle, field.name));
                std.mem.copy(u8, dest_slice, field_bytes);
                dest_slice.ptr += field_bytes.len;
            }
            self.entity_ids[self.cursor] = id;
            self.cursor += 1;
            return true;
        }

        fn type_at(self: *Self, typename: []const u8, elem_idx: usize) usize {
            const offset = SizeCalc.offset(typename);
            const elem_start = @ptrToInt(self.type_mem.ptr) + (elem_idx * self.bundle_size);
            return elem_start + offset;
        }

        fn remove(self: *Self, id: IdType) bool {
            var idx: usize = 0;
            while (idx != self.cursor + 1) : (idx += 1) {
                if (self.entity_ids[idx] == id) {
                    self.remove_idx(idx);
                    return true;
                }
            }
            return false;
        }

        // Effectively works as a swap-remove
        // Copies bundle at end of array to indicated location and decrements
        // cursor
        fn remove_idx(self: *Self, idx: usize) void {
            var dest_slice: []u8 = self.type_mem;
            dest_slice.ptr += idx * self.bundle_size;
            dest_slice.len = self.bundle_size;
            var src_slice: []u8 = self.type_mem;
            src_slice.ptr += self.cursor * self.bundle_size;
            src_slice.len = self.bundle_size;
            std.mem.copy(u8, dest_slice, src_slice);
            self.entity_ids[idx] = self.entity_ids[self.cursor];
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

        fn cursor(self: *Self) usize {
            return self.cursor;
        }

        fn grow(self: *Self) !void {
            const new_cap = self.capacity * 2;
            self.type_mem = try self.allocator.realloc(self.type_mem, new_cap * self.bundle_size);
            self.entity_ids = try self.allocator.realloc(self.entity_ids, new_cap);
            self.capacity = new_cap;
        }

        // Diagnostic functions section
        fn print_at(self: *Self, idx: usize) void {
            std.debug.print("arch type mem @[{}]: ", .{idx});
            var i: usize = 0;
            while (i < self.bundle_size) : (i += 1) {
                std.debug.print("{} ", .{self.type_mem[idx * self.bundle_size + i]});
            }
            std.debug.print("\n", .{});
        }

        fn print_info(self: *Self) void {
            std.debug.print("capacity: {}, cursor: {}, bundle size: {}\n", .{ self.capacity, self.cursor, self.bundle_size });
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
    var arch = try ArchetypeGen(Bundle).init(allocator);
    defer arch.deinit();
    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 3, .magnitude = 4 };

    // `has` testing
    expect(arch.has(Point));
    expect(!arch.has(HitPoints));

    // `put` testing
    expect(arch.cursor == 0);
    expect(arch.put(0, .{ .Point = p, .Velocity = v }));
    expect(arch.cursor == 1);

    // Get with type
    // Point
    const point_ptr: usize = arch.type_at(@typeName(Point), 0);
    const point: *Point = @intToPtr(*Point, point_ptr);
    expect(point.x == 1);
    expect(point.y == 2);
    point.x += 10;
    expect(point.x == 11);
    expect(point.y == 2);
    // Check first 4 bytes of memory (Point x) to make sure it's mutated
    var i: usize = 0;
    var total: usize = 0;
    while (i < 4) : (i += 1) {
        total += arch.type_mem[i];
    }
    expect(total == 11);
    // Velocity
    const vel_ptr: usize = arch.type_at(@typeName(Velocity), 0);
    const vel: *Velocity = @intToPtr(*Velocity, vel_ptr);
    expect(vel.dir == 3);
    expect(vel.magnitude == 4);
}

test "storage resizing" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

    // Setup
    const Bundle = comptime_utils.typeFromBundle(.{ Point, Velocity });
    var arch = try ArchetypeGen(Bundle).init_capacity(allocator, 1);
    defer arch.deinit();

    // Spawned: 1, cap: 1
    expect(arch.put(0, .{ .Point = .{ .x = 1, .y = 1 }, .Velocity = .{ .dir = 1, .magnitude = 1 } }));
    const pt = @intToPtr(*Point, arch.type_at(@typeName(Point), 0));
    expect(pt.x == 1 and pt.y == 1);
    const vel = @intToPtr(*Velocity, arch.type_at(@typeName(Velocity), 0));
    expect(vel.dir == 1 and vel.magnitude == 1);

    // Spawned: 2, cap: 1 -> 2
    expect(arch.put(1, .{ .Point = .{ .x = 2, .y = 2 }, .Velocity = .{ .dir = 2, .magnitude = 2 } }));
    const pt2 = @intToPtr(*Point, arch.type_at(@typeName(Point), 1));
    expect(pt2.x == 2 and pt2.y == 2);
    const vel2 = @intToPtr(*Velocity, arch.type_at(@typeName(Velocity), 1));
    expect(vel2.dir == 2 and vel2.magnitude == 2);
    // Check first index again after resizing, just in case
    const pt1 = @intToPtr(*Point, arch.type_at(@typeName(Point), 0));
    expect(pt1.x == 1 and pt1.y == 1);
    const vel1 = @intToPtr(*Velocity, arch.type_at(@typeName(Velocity), 0));
    expect(vel1.dir == 1 and vel1.magnitude == 1);

    // Spawned: 3, cap: 2 -> 4
    expect(arch.put(2, .{ .Point = .{ .x = 3, .y = 3 }, .Velocity = .{ .dir = 3, .magnitude = 3 } }));
    const pt3 = @intToPtr(*Point, arch.type_at(@typeName(Point), 2));
    expect(pt3.x == 3 and pt3.y == 3);
    const vel3 = @intToPtr(*Velocity, arch.type_at(@typeName(Velocity), 2));
    expect(vel3.dir == 3 and vel3.magnitude == 3);
}
