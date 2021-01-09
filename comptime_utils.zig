const std = @import("std");
const TypeInfo = std.builtin.TypeInfo;

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

pub fn makeBundleMut(comptime Bundle: type) type {
    const info = @typeInfo(Bundle);
    const field_len = info.Struct.fields.len;
    const bundle_mut_data: TypeInfo.Struct = .{
        // TODO: align to info
        .layout = info.Struct.layout,
        .fields = fields: {
            comptime var arr: [field_len]TypeInfo.StructField = undefined;

            inline for (info.Struct.fields) |field, idx| {
                const new_field = TypeInfo.StructField{
                    .name = field.name,
                    .field_type = *field.field_type,
                    .default_value = null,
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
    const bundle_info = TypeInfo{ .Struct = bundle_mut_data };
    return @Type(bundle_info);
}

test "type generation" {
    const eql = std.mem.eql;
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u32 };
    const HitPoints = struct { hp: u32 };

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

    // Create a BundleMut from the basic Bundle
    const MutType1 = makeBundleMut(Type1);
    const mut_info1 = @typeInfo(MutType1);
    const mut_fields1 = mut_info1.Struct.fields;
    expect(eql(u8, mut_fields1[0].name, "Point"));
    expect(mut_fields1[0].field_type == *Point);
    expect(eql(u8, mut_fields1[1].name, "Velocity"));
    expect(mut_fields1[1].field_type == *Velocity);
}

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

fn assertTupleOf(comptime ty: type, any: anytype) void {
    const info = @typeInfo(@TypeOf(any));
    if (info != .Struct or !info.Struct.is_tuple) {
        @compileError("expecting tuple to be passed");
    }

    inline for (info.Struct.fields) |field| {
        if (field.field_type != ty) {
            @compileError("expecting all tuple elements to be of same type " ++ @typeName(ty) ++ ", found type " ++ @typeName(field.field_type));
        }
    }
}

fn assertTypeAndOrdering(comptime ty: type, arch: anytype) void {
    const arch_info = @typeInfo(@TypeOf(arch));
    if (arch_info != .Struct or !arch_info.Struct.is_tuple) {
        @compileError("expecting tuple to be passed, got " ++ @typeName(@TypeOf(arch)));
    }
    if (arch_info.Struct.fields.len == 0) {
        @compileError("tuple argument cannot be empty");
    }

    const type_info = @typeInfo(ty);
    // TODO: see at some point if we can cut out passing the type
    //comptime var type_info = @typeInfo(@TypeOf(arch_info.Struct.fields[0].default_value.?));
    //@compileError("MY TYPE INFO: " ++ type_info);
    if (type_info != .Struct and type_info != .Type) {
        @compileError("expecting struct or type element specifier, got " ++ @typeName(ty));
    }

    if (type_info == .Struct) {
        inline for (arch_info.Struct.fields) |field, idx| {
            if (@typeInfo(field.field_type) != .Struct) {
                @compileError("expecting all tuple elements to be of same type " ++ @typeName(ty) ++ ", found type " ++ @typeName(field.field_type));
            }
            if (idx == 0) continue;
            comptime const field1 = @typeName(arch_info.Struct.fields[idx - 1].field_type);
            comptime const field2 = @typeName(field.field_type);
            comptime const ordered = std.mem.order(u8, field1, field2) == std.math.Order.lt;
            if (!ordered) {
                @compileError("components structs must be lexicographically ordered");
            }
        }
    } else if (type_info == .Type) {
        inline for (arch_info.Struct.fields) |field, idx| {
            if (field.field_type != ty) {
                @compileError("expecting all tuple elements to be of same type " ++ @typeName(ty) ++ ", found type " ++ @typeName(field.field_type));
            }
            if (idx == 0) continue;
            comptime const field1 = @typeName(arch_info.Struct.fields[idx - 1].default_value.?);
            comptime const field2 = @typeName(field.default_value.?);
            comptime const ordered = std.mem.order(u8, field1, field2) == std.math.Order.lt;
            if (!ordered) {
                @compileError("components structs must be lexicographically ordered");
            }
        }
    } else {
        // Leaving this terminating condition in defensively
        @compileError("expecting struct or type element specifier, got " ++ @typeName(ty));
    }
}

test "tuple assertions" {
    const allocator = std.testing.allocator;

    const CAPACITY = 1024;
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6, magnitude: u8 };

    const p1 = Point{ .x = 3, .y = 4 };
    const v1 = Velocity{ .dir = 2, .magnitude = 100 };

    const type_tup1 = .{ Point, Velocity };
    const comp_tup1 = .{ Point{ .x = 3, .y = 4 }, Velocity{ .dir = 2, .magnitude = 100 } };

    // This section should pass
    assertTypeAndOrdering(type, type_tup1);
    assertTypeAndOrdering(TypeInfo.Struct, comp_tup1);

    // Fail section
    const type_tup2 = .{ Velocity, Point };
    //assertTypeAndOrdering(type, type_tup2);
    const comp_tup2 = .{ Velocity{ .dir = 2, .magnitude = 100 }, Point{ .x = 3, .y = 4 } };
    //assertTypeAndOrdering(TypeInfo.Struct, comp_tup2);
    //const fail_tup = .{ Velocity{ .dir = 2, .magnitude = 100 }, Point{ .x = 3, .y = 4 }, true };
    //assertTypeAndOrdering(TypeInfo.Struct, fail_tup);
    //const fail_tup = .{ Point, Velocity, true };
    //assertTypeAndOrdering(type, fail_tup);
}
