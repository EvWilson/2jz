const std = @import("std");
const allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const HashMap = std.AutoHashMap;
const print = std.debug.print;

const DEFAULT_SIZE = 1024;
const Point = struct { x: u32, y: u32 };
const Velocity = struct { dir: u6, magnitude: u32 };
const HitPoints = struct { hp: u32 };

test "type fiddling" {
    print("\n", .{});

    const BitMaskField = u64;

    print("type name point: {}\n", .{@typeName(Point)});

    comptime const reg_tup = .{ Point, Velocity, HitPoints };
    comptime const reg_arr = [_]type{ Point, Velocity, HitPoints };

    var map = HashMap([]const u8, BitMaskField).init(allocator);
    defer map.deinit();

    // Experimenting w/ type naming
    {
        const ty = @TypeOf(reg_tup);
        const type_info = @typeInfo(ty);
        const fields = type_info.Struct.fields.len;
        print("tup is tup: {}\n", .{type_info.Struct.is_tuple});
        std.debug.print("Size of fields: {}\n", .{fields});
        std.debug.print("type name: {}\n", .{@typeName(ty)});

        var p: Point = .{ .x = 5, .y = 7 };
        print("point type name: {}\n", .{@typeName(@TypeOf(p))});
    }

    // PoC for comptime-aided bitmask construction
    {
        // Make sure bitmask field contains enough bits
        if (@typeInfo(BitMaskField).Int.bits < reg_tup.len) {
            @compileError("not enough bits in BitMaskField to create bitmask");
        }
        comptime var mask_val = 1;
        inline for (reg_tup) |ty| {
            try map.put(@typeName(ty), mask_val);
            mask_val = mask_val << 1;
        }

        print("mask val of Point: {}\n", .{map.get(@typeName(Point))});
        print("mask val of Velocity: {}\n", .{map.get(@typeName(Velocity))});
        print("mask val of HitPoints: {}\n", .{map.get(@typeName(HitPoints))});
    }

    // Generate bitmask from type sets
    {
        const physics = .{ Point, Velocity };
        var mask: BitMaskField = 0;
        inline for (physics) |ty| {
            const field = map.get(@typeName(ty));
            mask |= field.?;
        }
        print("physics mask: {}\n", .{mask});
    }

    // Generate bitmask from structs themselves
    {
        const p: Point = .{ .x = 2, .y = 3 };
        const v: Velocity = .{ .dir = 2, .magnitude = 200 };
        const physics = .{ p, v };
        var mask: BitMaskField = 0;
        inline for (physics) |str| {
            const field = map.get(@typeName(@TypeOf(str)));
            mask |= field.?;
        }
        print("physics mask on actual structs: {}\n", .{mask});
    }
}

test "does this work?" {
    const pt = Point{ .x = 1, .y = 2 };
    const vel = Velocity{ .dir = 3, .magnitude = 4 };
    const tup = .{ pt, vel };
    const tup2 = .{ vel, pt };
    const tup3 = .{ Point{ .x = 5, .y = 6 }, Velocity{ .dir = 10, .magnitude = 15 } };
    const tup4 = .{ Velocity{ .dir = 10, .magnitude = 15 }, Point{ .x = 7, .y = 8 } };

    std.debug.print("yeehaw: {}\n", .{@typeName(@typeInfo(@TypeOf(tup3)).Struct.fields[0].field_type)});
    assertFieldOrdering(tup3);

    const type_tup = .{ Point, Velocity };
    std.debug.print("YEEHAW: {}\n", .{@typeInfo(@TypeOf(type_tup)).Struct.fields[0].name});
    //assertFieldOrdering(type_tup);

    print("?: {}\n", .{std.meta.sizeof(tup)});
    print("?????: {}\n", .{std.meta.sizeof(tup3)});
}

test "type array" {
    const TypeInfo = std.builtin.TypeInfo;

    const Garbage = union(enum) {
        One: i32,
        Two: u8,
        Three: void,
    };
    const garbo_mem = try allocator.alloc(Garbage, 5);
    defer allocator.free(garbo_mem);
    garbo_mem[0] = Garbage{ .One = 5 };
    switch (garbo_mem[0]) {
        .One => |value| expect(value == 5),
        else => unreachable,
    }

    //const type_mem = try allocator.alloc(TypeInfo, 1024);
    //allocator.free(type_mem);
}

fn assertFieldOrdering(arch: anytype) void {
    const info = @typeInfo(@TypeOf(arch));
    if (info != .Struct or !info.Struct.is_tuple) {
        @compileError("expecting tuple to be passed");
    }

    inline for (info.Struct.fields) |field, idx| {
        if (idx == 0) continue;
        comptime const field1 = @typeName(info.Struct.fields[idx - 1].field_type);
        comptime const field2 = @typeName(field.field_type);
        comptime const ordered = std.mem.order(u8, field1, field2) == std.math.Order.lt;
        if (!ordered) {
            @compileError("components structs must be lexicographically ordered");
        }
    }
}

test "untyped memory" {
    print("\n", .{});

    const p = Point{ .x = 150, .y = 200 };
    const v = Velocity{ .dir = 12, .magnitude = 8 };
    const hp = HitPoints{ .hp = 90 };

    const type_tup = .{ Point, Velocity };

    // Try to get size of these type tuples
    {
        print("Size of point: {}, velocity: {}\n", .{ @sizeOf(Point), @sizeOf(Velocity) });
        comptime var sz = 0;
        inline for (@typeInfo(@TypeOf(type_tup)).Struct.fields) |typ| {
            //print("Adding size of {} which is: {}\n", .{ typ, @sizeOf(typ.default_value.?) });
            sz += @sizeOf(typ.default_value.?);
        }
        print("Size with comptime calc: {}\n", .{sz});
    }

    // Try to alloc area of mem, store structs, then retrieve later
    {
        // Figure out size and allocate
        comptime var sz = 0;
        inline for (@typeInfo(@TypeOf(type_tup)).Struct.fields) |field| {
            sz += @sizeOf(field.default_value.?);
        }
        print("Struct seems to be {} bytes large, thus allocating {}*{} bytes\n", .{ sz, sz, DEFAULT_SIZE });
        var mem = try allocator.alloc(u8, sz * DEFAULT_SIZE);
        defer allocator.free(mem);

        // Try to start adding things to this section of memory
        var cursor: usize = 0;
        while (cursor < 10) : (cursor += 1) {
            const pt = Point{ .x = @intCast(u32, cursor), .y = @intCast(u32, cursor) };
            const vel = Velocity{ .dir = @intCast(u6, cursor), .magnitude = @intCast(u6, cursor) };
            // Put structs in format we can expect in future
            const tup = .{ pt, vel };
            print("{}\n", .{tup});
            assertFieldOrdering(tup);

            //@memcpy(mem.ptr + cursor * sz, &tup, sz);
        }

        cursor = 0;
        while (cursor < 10) : (cursor += 1) {
            //const tup = @as(@TypeOf(.{ Point, Velocity }), mem[cursor * sz .. cursor * sz + sz]);
        }
    }
}

fn Arch1(comptime comp_types: anytype) type {
    const TypeInfo = std.builtin.TypeInfo;

    const info = @typeInfo(@TypeOf(comp_types));
    comptime const field_len = info.Struct.fields.len;

    const bundle_data: TypeInfo.Struct = .{
        .layout = .Auto,
        .fields = fields: {
            comptime var arr: [field_len]TypeInfo.StructField = undefined;

            inline for (info.Struct.fields) |field, idx| {
                const new_field = TypeInfo.StructField{
                    .name = &[_]u8{idx + 48},
                    .field_type = comp_types[idx],
                    // TODO: get zeroed representation of this type?
                    //.default_value = field.default_value.?, <-- this get type, which is wrong
                    .default_value = std.mem.zeroInit(comp_types[idx], .{}),
                    .is_comptime = field.is_comptime,
                    .alignment = 0,
                };
                arr[idx] = new_field;
            }

            break :fields &arr;
        },
        .decls = &[_]TypeInfo.Declaration{},
        .is_tuple = true,
    };
    const bundle_info = TypeInfo{ .Struct = bundle_data };
    const BundleType = @Type(bundle_info);

    return struct {
        const Self = @This();

        allocator: *Allocator,
        bundle_size: u32,
        capacity: u32,
        cursor: u32,
        entity_ids: []u32,
        names: [field_len][]const u8,
        sizes: [field_len]u32,
        type_mem: []u8,

        fn init(alloc: *Allocator) !Self {
            const CAPACITY = 1024;
            var result: Self = .{
                .allocator = alloc,
                .bundle_size = undefined,
                .capacity = CAPACITY,
                .cursor = 0,
                .entity_ids = try allocator.alloc(u32, CAPACITY),
                .names = undefined,
                .sizes = undefined,
                .type_mem = undefined,
            };
            comptime var total_size = 0;
            inline for (info.Struct.fields) |field, idx| {
                result.names[idx] = @typeName(field.default_value.?);
                const size = @sizeOf(field.default_value.?);
                result.sizes[idx] = size;
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
                print("cursor ({}) met capacity({})\n", .{ self.cursor, self.capacity });
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

            //var result: @TypeOf(components) = undefined;
            //inline for (components) |comp, i| {
            //    //@field(result, @typeName(comp)) = @bitCast(comp, struct_mem);
            //    const comp_size = @sizeOf(comp);
            //    //result[i] = @as(comp, struct_mem[0..comp_size]);
            //    struct_mem.ptr += comp_size;
            //}

            // This is a tuple of types, not of the structs I need
            var result: *BundleType = @ptrCast(*BundleType, struct_mem);

            return result;
        }

        fn has(self: *Self, comptime comp_type: type) bool {
            const other = @typeName(comp_type);
            for (self.names) |name| {
                if (std.mem.eql(u8, other, name)) {
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
    };
}

test "" {
    const eql = std.mem.eql;
    print("\n", .{});

    var arch = try Arch1(.{ Point, Velocity }).init(allocator);
    defer arch.deinit();

    expect(eql(u8, arch.names[0], "Point"));
    expect(arch.sizes[0] == 8);
    expect(arch.has(Point));
    expect(!arch.has(HitPoints));

    const p = Point{ .x = 1, .y = 2 };
    const v = Velocity{ .dir = 3, .magnitude = 4 };
    expect(arch.cursor == 0);
    arch.put(0, .{ p, v });
    expect(arch.cursor == 1);
    //print("arch type mem after first insert: {}{}{}{}{}\n", .{ arch.type_mem[0], arch.type_mem[1], arch.type_mem[2], arch.type_mem[3], arch.type_mem[4] });

    const bundle = arch.get_idx(0);
    print("bundle contents: {}\n", .{bundle});
    //print("bundle at 0: {}\n", .{@as(Point, bundle[0]).x});
}
