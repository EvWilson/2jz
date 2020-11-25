const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const TypeInfo = std.builtin.TypeInfo;

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
    std.debug.print("\n", .{});
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

    std.debug.print("Tuple assertion success\n", .{});
}

test "arch test" {
    const allocator = std.testing.allocator;

    const CAPACITY = 1024;
    const Point = struct { x: u32, y: u32 };
    const Velocity = struct { dir: u6 };

    const type_tup = .{ Point, Velocity };
}
