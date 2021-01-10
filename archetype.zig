const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const TypeInfo = std.builtin.TypeInfo;

const comptime_utils = @import("./comptime_utils.zig");

// Inspired by Alex Naskos' Runtime Polymorphism talk, 14:53
pub const Archetype = struct {
    const Self = @This();
    const VTable = struct {
        deinit: fn (usize) void,
        get_idx: fn (usize, usize) usize,
        get_idx_mut: fn (usize, usize) usize,
        cursor: fn (usize) usize,
        put: fn (usize, u32, usize) void,
        type_at: fn (usize, []const u8, usize) usize,

        print_at: fn (usize, usize) void,
    };
    alloc: *Allocator,
    vtable: *const VTable,
    object: usize,

    pub fn deinit(self: @This()) void {
        self.vtable.deinit(self.object);
    }

    pub fn get_idx(self: @This(), idx: usize) usize {
        return self.vtable.get_idx(self.object, idx);
    }

    pub fn get_idx_mut(self: @This(), idx: usize) usize {
        return self.vtable.get_idx_mut(self.object, idx);
    }

    pub fn cursor(self: @This()) usize {
        return self.vtable.cursor(self.object);
    }

    pub fn put(self: @This(), id: u32, bundle_ptr: usize) void {
        self.vtable.put(self.object, id, bundle_ptr);
    }

    pub fn type_at(self: @This(), typename: []const u8, elem_idx: usize) usize {
        return self.vtable.type_at(self.object, typename, elem_idx);
    }

    pub fn make(comptime Bundle: type, alloc: *Allocator) !Self {
        const arch = try ArchetypeGen(Bundle).init(alloc);
        return makeInternal(Bundle, alloc, arch);
    }

    pub fn print_at(self: @This(), idx: usize) void {
        self.vtable.print_at(self.object, idx);
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
                .get_idx = struct {
                    fn get_idx(ptr: usize, idx: usize) usize {
                        const self = @intToPtr(PtrType, ptr);
                        const ret_ptr = @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).get_idx, .{ self, idx });
                        return @ptrToInt(ret_ptr);
                    }
                }.get_idx,
                .get_idx_mut = struct {
                    fn get_idx_mut(ptr: usize, idx: usize) usize {
                        const self = @intToPtr(PtrType, ptr);
                        const ret_ptr = @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).get_idx_mut, .{ self, idx });
                        return @ptrToInt(ret_ptr);
                    }
                }.get_idx_mut,
                .cursor = struct {
                    fn cursor(ptr: usize) usize {
                        const self = @intToPtr(PtrType, ptr);
                        return @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).cursor, .{self});
                    }
                }.cursor,
                .put = struct {
                    fn put(ptr: usize, id: u32, bundle_ptr: usize) void {
                        const self = @intToPtr(PtrType, ptr);
                        const bundle: *Bundle = @intToPtr(*Bundle, bundle_ptr);
                        @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).put, .{ self, id, bundle.* });
                    }
                }.put,
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
    const BundleMut = comptime_utils.makeBundleMut(Bundle);
    var arch = try ArchetypeGen(Bundle).init(allocator);

    // Set up the dynamic reference
    var dyn = Archetype.makeInternal(Bundle, allocator, arch);
    defer dyn.deinit();

    // `put`
    const add: Bundle = .{ .Point = p, .Velocity = v };
    dyn.put(0, @ptrToInt(&add));

    // `get` - non-mutable
    var bundle_ptr: usize = dyn.get_idx(0);
    var bundle: Bundle = @intToPtr(*Bundle, bundle_ptr).*;
    expect(bundle.Point.x == 1 and bundle.Point.y == 2 and
        bundle.Velocity.dir == 7 and bundle.Velocity.magnitude == 8);
    var cnt: usize = 0;
    var sum: usize = 0;
    while (cnt < 16) : (cnt += 1) {
        sum += arch.type_mem[cnt];
    }
    expect(sum == 18);
    bundle.Point.x += 10;
    cnt = 0;
    sum = 0;
    while (cnt < 16) : (cnt += 1) {
        sum += arch.type_mem[cnt];
    }
    expect(bundle.Point.x == 11 and sum == 18);

    // `get` - mutable
    bundle_ptr = dyn.get_idx_mut(0);
    var bundle_mut: BundleMut = @intToPtr(*BundleMut, bundle_ptr).*;
    expect(bundle_mut.Point.x == 1 and bundle_mut.Point.y == 2 and
        bundle_mut.Velocity.dir == 7 and bundle_mut.Velocity.magnitude == 8);
    cnt = 0;
    sum = 0;
    while (cnt < 16) : (cnt += 1) {
        sum += arch.type_mem[cnt];
    }
    expect(sum == 18);
    bundle_mut.Point.x += 10;
    cnt = 0;
    sum = 0;
    while (cnt < 16) : (cnt += 1) {
        sum += arch.type_mem[cnt];
    }
    expect(bundle_mut.Point.x == 11 and sum == 28);
}

pub fn ArchetypeGen(comptime Bundle: type) type {
    const info = @typeInfo(Bundle);

    // Create another struct from the passed in type to be used as a mutable
    // return value
    const BundleMut = comptime_utils.makeBundleMut(Bundle);

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
        entity_ids: []u32,
        // Memory to hold data
        type_mem: []u8,

        pub fn init(alloc: *Allocator) !*Self {
            var result: *Self = try alloc.create(Self);
            result.allocator = alloc;
            result.capacity = Self.DEFAULT_CAPACITY;
            result.cursor = 0;
            result.entity_ids = try alloc.alloc(u32, Self.DEFAULT_CAPACITY);
            comptime var total_size = 0;
            inline for (info.Struct.fields) |field, idx| {
                const size = @sizeOf(@TypeOf(field.default_value.?));
                total_size += size;
            }
            result.bundle_size = total_size;
            result.type_mem = try alloc.alloc(u8, result.bundle_size * result.capacity);
            return result;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.entity_ids);
            self.allocator.free(self.type_mem);
            self.allocator.destroy(self);
        }

        fn print_info(self: *Self) void {
            std.debug.print("capacity: {}, cursor: {}, bundle size: {}\n", .{ self.capacity, self.cursor, self.bundle_size });
        }

        fn put(self: *Self, id: u32, bundle: Bundle) void {
            if (self.cursor == self.capacity) {
                std.debug.print("cursor ({}) met capacity({}). GROWING MEM REGION.\n", .{ self.cursor, self.capacity });
                self.grow();
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
        }

        fn get_idx(self: *Self, idx: usize) *Bundle {
            var struct_mem = self.type_mem;
            struct_mem.ptr += idx * self.bundle_size;

            var result: Bundle = .{};
            inline for (info.Struct.fields) |field, i| {
                const field_type = @TypeOf(field.default_value.?);
                // For the current field, set it to a dereferenced pointer of
                // the current location in the data array
                @field(result, @typeName(field_type)) =
                    @ptrCast(*field_type, @alignCast(@sizeOf(field_type), struct_mem)).*;
                struct_mem.ptr += @sizeOf(field_type);
            }

            return &result;
        }

        fn type_at(self: *Self, typename: []const u8, elem_idx: usize) usize {
            const offset = SizeCalc.offset(typename);
            const elem_start = @ptrToInt(self.get_idx(elem_idx));
            return elem_start + offset;
        }

        fn get_idx_mut(self: *Self, idx: usize) *BundleMut {
            var struct_mem = self.type_mem;
            struct_mem.ptr += idx * self.bundle_size;

            var result: BundleMut = undefined;
            inline for (info.Struct.fields) |field, i| {
                const field_type = @TypeOf(field.default_value.?);
                @field(result, @typeName(field_type)) =
                    @ptrCast(*field_type, @alignCast(@sizeOf(field_type), struct_mem));
                struct_mem.ptr += @sizeOf(field_type);
            }
            return &result;
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

        // TODO
        fn grow(self: *Self) void {
            std.debug.print("UNIMPLEMENTED: hit archetype grow function\n", .{});
            std.debug.assert(false);
        }

        fn print_at(self: *Self, idx: usize) void {
            std.debug.print("arch type mem @[{}]: ", .{idx});
            var i: usize = 0;
            while (i < self.bundle_size) : (i += 1) {
                std.debug.print("{} ", .{self.type_mem[idx * self.bundle_size + i]});
            }
            std.debug.print("\n", .{});
        }

        fn get_bundle() type {
            return Bundle;
        }

        fn get_bundle_mut() type {
            return BundleMut;
        }
    };
}

test "archetype test" {
    const eql = std.mem.eql;
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
    arch.put(0, .{ .Point = p, .Velocity = v });
    expect(arch.cursor == 1);

    // `get` testing - non-mutable
    // Can mutate struct values, but not underlying memory
    var bundle = arch.get_idx(0);
    expect(bundle.Point.x == 1);
    expect(bundle.Point.y == 2);
    expect(bundle.Velocity.dir == 3);
    expect(bundle.Velocity.magnitude == 4);
    bundle.Point.x += 10;
    expect(bundle.Point.x == 11);
    // Check first 4 bytes of memory (Point x) to make sure it's unaffected
    var i: usize = 0;
    var total: usize = 0;
    while (i < 4) : (i += 1) {
        total += arch.type_mem[i];
    }
    expect(total == 1);

    // Get with type
    // Point
    const point_ptr: usize = arch.type_at(@typeName(Point), 0);
    const point: *Point = @intToPtr(*Point, point_ptr);
    expect(point.x == 1);
    expect(point.y == 2);
    point.x += 10;
    expect(point.x == 11);
    expect(point.y == 2);
    // Check first 4 bytes of memory (Point x) to make sure it's unaffected
    i = 0;
    total = 0;
    while (i < 4) : (i += 1) {
        total += arch.type_mem[i];
    }
    expect(total == 1);
    // Velocity
    const vel_ptr: usize = arch.type_at(@typeName(Velocity), 0);
    const vel: *Velocity = @intToPtr(*Velocity, vel_ptr);
    expect(vel.dir == 3);
    expect(vel.magnitude == 4);

    // `get` testing - mutable
    // Struct member mutations directly mutate underlying archetype memory
    var mut_bundle = arch.get_idx_mut(0);
    expect(mut_bundle.Point.x == 1);
    expect(mut_bundle.Point.y == 2);
    expect(mut_bundle.Velocity.dir == 3);
    expect(mut_bundle.Velocity.magnitude == 4);
    mut_bundle.Point.x += 10;
    expect(mut_bundle.Point.x == 11);
    // Leaving this check in because this section was rather wonky for a while
    expect(@ptrToInt(arch.type_mem.ptr) == @ptrToInt(mut_bundle.Point));
    expect(@ptrToInt(arch.type_mem.ptr) + @sizeOf(Point) == @ptrToInt(mut_bundle.Velocity));
    // Check first 4 bytes of memory (Point x) to make sure it's been mutated
    i = 0;
    total = 0;
    while (i < 4) : (i += 1) {
        total += arch.type_mem[i];
    }
    expect(total == 11);
}
