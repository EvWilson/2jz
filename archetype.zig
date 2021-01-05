const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const TypeInfo = std.builtin.TypeInfo;

const comptime_utils = @import("./comptime_utils.zig");
const typeFromBundle = comptime_utils.typeFromBundle;
const typeFromBundleMut = comptime_utils.typeFromBundleMut;

// TODO: fix this and understand it
// Taken from Alex Naskos' Runtime Polymorphism talk, 14:53
pub const Archetype = struct {
    const VTable = struct {
        deinit: fn (usize) void,
        get_idx: fn (usize, usize) usize,
        get_idx_mut: fn (usize, usize) usize,
        put: fn (usize, u32, usize) void,
        print_at: fn (usize, usize) void,
    };
    vtable: *const VTable,
    object: usize,

    fn deinit(self: @This()) void {
        self.vtable.deinit(self.object);
    }

    fn get_idx(self: @This(), idx: usize) usize {
        return self.vtable.get_idx(self.object, idx);
    }

    fn get_idx_mut(self: @This(), idx: usize) usize {
        return self.vtable.get_idx_mut(self.object, idx);
    }

    fn put(self: @This(), id: u32, bundle_ptr: usize) void {
        self.vtable.put(self.object, id, bundle_ptr);
    }

    fn print_at(self: @This(), idx: usize) void {
        self.vtable.print_at(self.object, idx);
    }

    fn make(obj: anytype) @This() {
        const PtrType = @TypeOf(obj);
        const BundleType = @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).get_bundle, .{});
        const BundleTypeMut = @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).get_bundle_mut, .{});
        return .{
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
                .put = struct {
                    fn put(ptr: usize, id: u32, bundle_ptr: usize) void {
                        const self = @intToPtr(PtrType, ptr);
                        const bundle: *BundleType = @intToPtr(*BundleType, bundle_ptr);
                        // TODO: fix
                        @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).put, .{ self, id, bundle.* });
                    }
                }.put,
                .print_at = struct {
                    fn print_at(ptr: usize, idx: usize) void {
                        const self = @intToPtr(PtrType, ptr);
                        @call(.{ .modifier = .always_inline }, std.meta.Child(PtrType).print_at, .{ self, idx });
                    }
                }.print_at,
            },
            .object = @ptrToInt(obj),
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
    var arch = try ArchetypeGen(.{ Point, Velocity }).init(allocator);
    //defer arch.deinit();
    //arch.put(0, .{ .Point = p, .Velocity = v });

    // Set up the dynamic reference
    var dyn = Archetype.make(&arch);
    defer dyn.deinit();
    const BundleType = @TypeOf(arch).get_bundle();
    const BundleTypeMut = @TypeOf(arch).get_bundle_mut();

    // `put`
    const add: BundleType = .{ .Point = p, .Velocity = v };
    dyn.put(0, @ptrToInt(&add));
    // This notation also works, though it's a bit of an eyesore
    //dyn.put(0, @ptrToInt(&@TypeOf(arch.get_bundle_instance()){ .Point = p, .Velocity = v }));

    // `get` - non-mutable
    var bundle_ptr: usize = dyn.get_idx(0);
    var bundle: BundleType = @intToPtr(*BundleType, bundle_ptr).*;
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
    var bundle_mut: BundleTypeMut = @intToPtr(*BundleTypeMut, bundle_ptr).*;
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

pub fn ArchetypeGen(comptime comp_types: anytype) type {
    const info = @typeInfo(@TypeOf(comp_types));

    // Create a struct from the passed in types to be used as a return value
    const BundleType = typeFromBundle(comp_types);

    // Create another struct from the passed in types to be used as a mutable
    // return value
    const BundleTypeMut = typeFromBundleMut(comp_types);

    return struct {
        const Self = @This();

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

        fn init(alloc: *Allocator) !Self {
            const CAPACITY = 1024;
            var result: Self = .{
                .allocator = alloc,
                .bundle_size = undefined,
                .capacity = CAPACITY,
                .cursor = 0,
                .entity_ids = try alloc.alloc(u32, CAPACITY),
                .type_mem = undefined,
            };
            comptime var total_size = 0;
            inline for (info.Struct.fields) |field, idx| {
                const size = @sizeOf(field.default_value.?);
                total_size += size;
            }
            result.bundle_size = total_size;
            result.type_mem = try alloc.alloc(u8, result.bundle_size * result.capacity);
            return result;
        }

        fn deinit(self: *Self) void {
            self.allocator.free(self.entity_ids);
            self.allocator.free(self.type_mem);
        }

        fn put(self: *Self, id: u32, bundle: BundleType) void {
            if (self.cursor == self.capacity) {
                std.debug.print("cursor ({}) met capacity({}). GROWING MEM REGION.\n", .{ self.cursor, self.capacity });
                self.grow();
            }
            comptime var offset = 0;
            const field_info = @typeInfo(@TypeOf(bundle));

            inline for (field_info.Struct.fields) |field, idx| {
                const field_bytes = std.mem.asBytes(&@field(bundle, field.name));

                var dest_slice = self.type_mem;
                dest_slice.ptr += (self.cursor * self.bundle_size) + offset;
                std.mem.copy(u8, dest_slice, field_bytes);

                offset += field_bytes.len;
            }
            self.entity_ids[self.cursor] = id;
            self.cursor += 1;
        }

        fn get_idx(self: *Self, idx: usize) *BundleType {
            var struct_mem = self.type_mem;
            struct_mem.ptr += idx * self.bundle_size;

            var result: BundleType = .{};
            inline for (info.Struct.fields) |field, i| {
                const field_type = field.default_value.?;
                // For the current field, set it to a dereferenced pointer of
                // the current location in the data array
                @field(result, @typeName(field_type)) =
                    @ptrCast(*field_type, @alignCast(@sizeOf(field_type), struct_mem)).*;
                struct_mem.ptr += @sizeOf(field_type);
            }

            return &result;
        }

        fn get_idx_mut(self: *Self, idx: usize) *BundleTypeMut {
            var struct_mem = self.type_mem;
            struct_mem.ptr += idx * self.bundle_size;

            var result: BundleTypeMut = undefined;
            inline for (info.Struct.fields) |field, i| {
                const field_type = field.default_value.?;
                @field(result, @typeName(field_type)) =
                    @ptrCast(*field_type, @alignCast(@sizeOf(field_type), struct_mem));
                struct_mem.ptr += @sizeOf(field_type);
            }
            return &result;
        }

        fn has(self: *Self, comptime comp_type: type) bool {
            const other = @typeName(comp_type);
            inline for (info.Struct.fields) |field| {
                if (std.mem.eql(u8, other, @typeName(field.default_value.?))) {
                    return true;
                }
            }
            return false;
        }

        // TODO
        fn grow(self: *Self) void {
            std.debug.print("UNIMPLEMENTED: hit archetype grow function\n", .{});
            std.debug.assert(false);
        }

        fn print_at(self: *Self, idx: usize) void {
            std.debug.print("arch type mem: ", .{});
            var i: usize = 0;
            while (i < self.bundle_size) : (i += 1) {
                std.debug.print("{} ", .{self.type_mem[i]});
            }
            std.debug.print("\n", .{});
        }

        fn get_bundle() type {
            return BundleType;
        }

        fn get_bundle_mut() type {
            return BundleTypeMut;
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
    var arch = try ArchetypeGen(.{ Point, Velocity }).init(allocator);
    defer arch.deinit();
    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 3, .magnitude = 4 };

    //std.debug.print("\narch test print: \n", .{});

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
