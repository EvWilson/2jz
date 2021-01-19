const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

// These are stashed here to avoid cyclical imports among other files
// The type used to construct bitmasks for component groupings
pub const MaskType = u64;
// The type used for entity IDs
pub const IdType = u32;

// Used to sort the constituent structs in the below typeFromBundle function
const SizeInfo = struct {
    size: comptime_int,
    idx: comptime_int,
};
// This function used for the failed sorting attempt, see comment about std.sort.sort below
//fn sizeInfoSort(context: void, comptime lhs: SizeInfo, comptime rhs: SizeInfo) bool {
//    return rhs.size < lhs.size;
//}
// Create a distinct type from a tuple of structs
// Expects to receive a tuple of types or structs, produces a struct type with
// each of the provided types as a field.
// Safety note: it is expected that the format of the provided tuple is checked
// in another function to ensure it is processable.
pub fn typeFromBundle(comptime comp_types: anytype) type {
    const info = @typeInfo(@TypeOf(comp_types));
    const field_len = info.Struct.fields.len;
    // Determine if we're operating on types or structs
    const is_types = if (@TypeOf(comp_types[0]) == type) true else false;

    // Sort the types provided by size, in descending order. This helps to avoid
    // alignment issues when dereferencing type addresses down the road.
    comptime var size_sorted: [info.Struct.fields.len]SizeInfo = undefined;
    inline for (info.Struct.fields) |field, idx| {
        comptime var field_type: type = undefined;
        if (is_types) {
            field_type = comp_types[idx];
        } else {
            field_type = @TypeOf(comp_types[idx]);
        }
        size_sorted[idx] = .{ .size = @sizeOf(field_type), .idx = idx };
    }
    // Using std.sort.sort on the size_sorted array yields a compiler error at
    // the moment (very sad), so I'm resorting to a basic selection sort. Don't
    // anticipate this being an issue, as the max N here is bounded by the bit
    // count of MaskType
    // The previous attempt, for when the stage2 compiler lands:
    // std.sort.sort(SizeInfo, &size_sorted, {}, sizeInfoSort);
    comptime var i = 0;
    while (i < info.Struct.fields.len) : (i += 1) {
        comptime var min_idx = i;
        comptime var j = i + 1;
        while (j < info.Struct.fields.len) : (j += 1) {
            if (size_sorted[min_idx].size < size_sorted[j].size) {
                min_idx = j;
            }
        }
        const tmp: SizeInfo = size_sorted[min_idx];
        size_sorted[min_idx] = size_sorted[i];
        size_sorted[i] = tmp;
    }

    const bundle_data: TypeInfo.Struct = .{
        .layout = .Auto,
        .fields = fields: {
            comptime var arr: [field_len]TypeInfo.StructField = undefined;

            inline for (info.Struct.fields) |field, pos| {
                const idx = size_sorted[pos].idx;
                comptime var field_type: type = undefined;
                if (is_types) {
                    field_type = comp_types[idx];
                } else {
                    field_type = @TypeOf(comp_types[idx]);
                }
                const new_field = TypeInfo.StructField{
                    .name = @typeName(field_type),
                    .field_type = field_type,
                    .default_value = std.mem.zeroInit(field_type, .{}),
                    .is_comptime = false,
                    .alignment = info.Struct.fields[pos].alignment,
                };
                arr[pos] = new_field;
            }

            break :fields &arr;
        },
        .decls = &[_]TypeInfo.Declaration{},
        .is_tuple = false,
    };
    const bundle_info = TypeInfo{ .Struct = bundle_data };
    return @Type(bundle_info);
}

test "new type" {
    const eql = std.mem.eql;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };

    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 7, .magnitude = 8 };

    const bundle1 = .{ @TypeOf(p), @TypeOf(v) };

    // Create a basic Bundle
    const Type = typeFromBundle(bundle1);
    const fields = @typeInfo(Type).Struct.fields;
    expect(eql(u8, fields[0].name, "Point"));
    expect(fields[0].field_type == Point);
    expect(eql(u8, fields[1].name, "Velocity"));
    expect(fields[1].field_type == Velocity);
}

test "size sorted" {
    const expect = std.testing.expect;

    const A = struct { val: u8 };
    const B = struct { val: u32 };

    {
        const Type = typeFromBundle(.{ A, B });
        const fields = @typeInfo(Type).Struct.fields;
        expect(fields[0].field_type == B);
        expect(fields[1].field_type == A);
    }

    {
        const bundle = .{ A{ .val = 1 }, B{ .val = 2 } };
        const Type = typeFromBundle(bundle);
        const fields = @typeInfo(Type).Struct.fields;
        expect(fields[0].field_type == B);
        expect(fields[1].field_type == A);
    }
}

// Coerce a tuple to the given type (used to convert tuple to type from above)
pub fn coerceToBundle(comptime T: type, comptime args: anytype) T {
    var ret: T = .{};
    inline for (args) |arg, idx| {
        @field(ret, @typeName(@TypeOf(arg))) = arg;
    }
    return ret;
}

test "coercion test" {
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };

    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 7, .magnitude = 8 };
    const bundle = .{ p, v };
    const Bundle = typeFromBundle(bundle);

    const new_bundle: Bundle = coerceToBundle(Bundle, bundle);

    expect(new_bundle.Point.x == 1);
    expect(new_bundle.Point.y == 2);
    expect(new_bundle.Velocity.dir == 7);
    expect(new_bundle.Velocity.magnitude == 8);
}

// Ensure that all elements of a tuple are either types or structs
// Useful for checking inbound tuples at API edge
pub fn assertTupleFormat(arch: anytype) void {
    const arch_info = @typeInfo(@TypeOf(arch));
    if (arch_info != .Struct or !arch_info.Struct.is_tuple) {
        @compileError("expecting tuple to be passed, got " ++ @typeName(@TypeOf(arch)));
    }
    if (arch_info.Struct.fields.len == 0) {
        @compileError("tuple argument cannot be empty");
    }
    const first_type = arch_info.Struct.fields[0].field_type;
    const type_info = @typeInfo(first_type);
    if (type_info == .Struct) {
        inline for (arch_info.Struct.fields) |field| {
            if (@typeInfo(field.field_type) != .Struct) {
                @compileError("expecting all tuple elements to be structs, found type " ++ @typeName(field.field_type));
            }
        }
    } else if (type_info == .Type) {
        inline for (arch_info.Struct.fields) |field| {
            if (@typeInfo(field.field_type) != .Type) {
                @compileError("expecting all tuple elements to be types, found type " ++ @typeName(field.field_type));
            }
        }
    } else {
        // Leaving this terminating condition in defensively
        @compileError("expecting struct or type element specifier, got " ++ @typeName(first_type));
    }
}

test "ordered tuples" {
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u8 };

    const type_tup = .{ Point, Velocity };
    assertTupleFormat(type_tup);

    const comp_tup = .{ Point{ .x = 3, .y = 4 }, Velocity{ .dir = 2, .magnitude = 100 } };
    assertTupleFormat(comp_tup);

    // This test should fail, commented out to not fail tests normally
    //const mixed_tup = .{ Point{ .x = 1, .y = 2 }, Velocity };
    //assertTupleFormat(mixed_tup);
}
