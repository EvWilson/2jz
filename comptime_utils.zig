const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

// These are stashed here to avoid cyclical imports among other files
// The type used to construct bitmasks for component groupings
pub const MaskType = u64;
// The type used for entity IDs
pub const IdType = u32;

// Create a distinct type from a tuple of structs
pub fn typeFromBundle(comptime comp_types: anytype) type {
    const info = @typeInfo(@TypeOf(comp_types));
    const field_len = info.Struct.fields.len;
    const is_types = if (@TypeOf(comp_types[0]) == type) true else false;
    const bundle_data: TypeInfo.Struct = .{
        .layout = .Auto,
        .fields = fields: {
            comptime var arr: [field_len]TypeInfo.StructField = undefined;

            inline for (info.Struct.fields) |field, idx| {
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
                    .alignment = field.alignment,
                };
                arr[idx] = new_field;
            }

            break :fields &arr;
        },
        .decls = &[_]TypeInfo.Declaration{},
        .is_tuple = false,
    };
    const bundle_info = TypeInfo{ .Struct = bundle_data };
    return @Type(bundle_info);
}

test "type generation" {
    const eql = std.mem.eql;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };

    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 7, .magnitude = 8 };

    const bundle1 = .{ p, v };

    // Create a basic Bundle
    const Type1 = typeFromBundle(bundle1);
    const info1 = @typeInfo(Type1);
    const fields1 = info1.Struct.fields;
    expect(eql(u8, fields1[0].name, "Point"));
    expect(fields1[0].field_type == Point);
    expect(eql(u8, fields1[1].name, "Velocity"));
    expect(fields1[1].field_type == Velocity);
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
// Usefull for checking inbound tuples at API edge
fn assertTypeAndOrdering(arch: anytype) void {
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
        inline for (arch_info.Struct.fields) |field, idx| {
            if (@typeInfo(field.field_type) != .Struct) {
                @compileError("expecting all tuple elements to be structs, found type " ++ @typeName(field.field_type));
            }
            if (idx == 0) continue;
            comptime const field1 = @typeName(arch_info.Struct.fields[idx - 1].field_type);
            comptime const field2 = @typeName(field.field_type);
            comptime const ordered = std.mem.order(u8, field1, field2) == std.math.Order.lt;
            if (!ordered) {
                @compileError("component structs must be lexicographically ordered");
            }
        }
    } else if (type_info == .Type) {
        inline for (arch_info.Struct.fields) |field, idx| {
            if (@typeInfo(field.field_type) != .Type) {
                @compileError("expecting all tuple elements to be types, found type " ++ @typeName(field.field_type));
            }
            if (idx == 0) continue;
            comptime const field1 = @typeName(arch_info.Struct.fields[idx - 1].default_value.?);
            comptime const field2 = @typeName(field.default_value.?);
            comptime const ordered = std.mem.order(u8, field1, field2) == std.math.Order.lt;
            if (!ordered) {
                @compileError("component types must be lexicographically ordered");
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
    assertTypeAndOrdering(type_tup);

    const comp_tup = .{ Point{ .x = 3, .y = 4 }, Velocity{ .dir = 2, .magnitude = 100 } };
    assertTypeAndOrdering(comp_tup);
}
