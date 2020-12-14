const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const TypeInfo = std.builtin.TypeInfo;

const comptime_utils = @import("./comptime_utils.zig");
const typeFromBundle = comptime_utils.typeFromBundle;
const typeFromBundleMut = comptime_utils.typeFromBundleMut;

pub fn Archetype(comptime comp_types: anytype) type {
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

        fn put(self: *Self, id: u32, bundle: anytype) void {
            if (self.cursor == self.capacity) {
                std.debug.print("cursor ({}) met capacity({}). GROWING MEM REGION.\n", .{ self.cursor, self.capacity });
                self.grow();
            }
            comptime var offset = 0;
            const field_info = @typeInfo(@TypeOf(bundle));

            inline for (field_info.Struct.fields) |field, idx| {
                const field_bytes = std.mem.asBytes(&bundle[idx]);

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
    var arch = try Archetype(.{ Point, Velocity }).init(allocator);
    defer arch.deinit();
    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 3, .magnitude = 4 };

    //std.debug.print("\n{}\n", .{arch});

    // `has` testing
    expect(arch.has(Point));
    expect(!arch.has(HitPoints));

    // `put` testing
    expect(arch.cursor == 0);
    arch.put(0, .{ p, v });
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
