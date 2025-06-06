///If this is true, then the reflection api can be used
///If this is false, then uses of the reflection api will throw an error
///This value should be checked when before using the reflection api
pub const reflect_enabled: bool = true;

pub const Type = union(enum) {
    @"struct": Struct,
    @"enum": Enum,
    @"union": Union,
    int: Int,
    float: Float,
    bool: void,
    void: void,
    array: Array,
    enum_literal: void,
    pointer: Pointer,

    pub const Id = enum(u64) { _ };

    pub const Struct = struct {
        name: []const u8,
        size: u32,
        alignment: u32,
        layout: std.builtin.Type.ContainerLayout,
        fields: []const StructField,
        decls: []const Declaration,
        is_tuple: bool,
    };

    pub const StructField = struct {
        name: []const u8,
        offset: u32,
        type: *const Type,
        default_value: ?*const anyopaque,
        is_comptime: bool,
        alignment: u32,
    };

    pub const Enum = struct {
        name: []const u8,
        size: u32,
        alignment: u32,
        tag_type: *const Type,
        fields: []const EnumField,
        decls: []const Declaration,
        is_exhaustive: bool,
    };

    pub const EnumField = struct {
        name: []const u8,
        value: u64,
    };

    pub const Declaration = struct {
        name: []const u8,
        type: *const Type,
        value: *const anyopaque,
    };

    pub const Int = struct {
        signedness: std.builtin.Signedness,
        bits: u16,
    };

    pub const Float = struct {
        bits: u16,
    };

    pub const UnionField = struct {
        name: []const u8,
        type: *const Type,
        alignment: u32,
    };

    pub const Union = struct {
        name: []const u8,
        size: u32,
        alignment: u32,
        layout: std.builtin.Type.ContainerLayout,
        tag_type: ?*const Type,
        tag_offset: u32,
        fields: []const UnionField,
        decls: []const Declaration,
    };

    pub const Array = struct {
        len: usize,
        child: *const Type,
        sentinel: ?*const anyopaque,
    };

    pub const Pointer = struct {
        size: std.builtin.Type.Pointer.Size,
        is_const: bool,
        is_volatile: bool,
        alignment: u16,
        address_space: std.builtin.AddressSpace,
        child: *const Type,
        is_allowzero: bool,
        sentinel: ?*const anyopaque,
    };

    ///Returns a unique id for a type without initializing
    ///Any type info. Use this when type info is not needed
    pub fn id(comptime T: type) Id {
        _ = T;

        const static = struct {
            var value: u8 = 0;
        };

        return @as(Id, @enumFromInt(@intFromPtr(&static.value)));
    }

    ///Returns a pointer to the canonical Type info for T
    pub fn info(comptime T: type) *const Type {
        const Static = struct {
            pub const @"type": Type = infoValue(T);
        };

        return &Static.type;
    }

    pub inline fn infoValue(comptime T: type) Type {
        var type_data: Type = undefined;

        switch (@typeInfo(T)) {
            .@"struct" => |struct_info| {
                comptime var fields: [struct_info.fields.len]StructField = undefined;
                comptime var decls: [struct_info.decls.len]Declaration = undefined;

                inline for (&fields, struct_info.fields) |*struct_field, comptime_struct_field| {
                    struct_field.* = .{
                        .name = comptime_struct_field.name,
                        .offset = if (!comptime_struct_field.is_comptime) @offsetOf(T, comptime_struct_field.name) else 0,
                        .alignment = comptime_struct_field.alignment,
                        .default_value = comptime_struct_field.default_value_ptr,
                        .is_comptime = comptime_struct_field.is_comptime,
                        .type = info(comptime_struct_field.type),
                    };
                }

                inline for (&decls, struct_info.decls) |*struct_decl, comptime_struct_decl| {
                    const S = struct {
                        pub const value = @field(T, comptime_struct_decl.name);
                    };

                    struct_decl.* = .{
                        .name = comptime_struct_decl.name,
                        .type = info(@TypeOf(@field(T, comptime_struct_decl.name))),
                        .value = &S.value,
                    };
                }

                const decls_const = decls;
                const fields_const = fields;

                type_data = .{ .@"struct" = .{
                    .name = @typeName(T),
                    .size = @sizeOf(T),
                    .alignment = @alignOf(T),
                    .layout = struct_info.layout,
                    .fields = &fields_const,
                    .decls = &decls_const,
                    .is_tuple = struct_info.is_tuple,
                } };
            },
            .@"union" => |union_info| {
                comptime var fields: [union_info.fields.len]UnionField = undefined;

                //TODO: This is NOT a stable way to find the offset of the tag, and is not reliable in the long term
                comptime var data_end: usize = 0;

                inline for (&fields, union_info.fields) |*union_field, comptime_union_field| {
                    union_field.* = .{
                        .name = comptime_union_field.name,
                        .type = info(comptime_union_field.type),
                        .alignment = @alignOf(comptime_union_field.type),
                    };

                    data_end = @max(@sizeOf(comptime_union_field.type), data_end);
                }

                data_end = std.mem.alignForwardLog2(data_end, @alignOf(union_info.tag_type.?));

                const fields_const = fields;

                type_data = .{ .@"union" = .{
                    .name = @typeName(T),
                    .size = @sizeOf(T),
                    .alignment = @alignOf(T),
                    .layout = union_info.layout,
                    .tag_type = if (union_info.tag_type != null) info(union_info.tag_type.?) else null,
                    .tag_offset = @as(u32, @intCast(data_end)),
                    .fields = &fields_const,
                    .decls = &.{},
                } };
            },
            .@"enum" => |enum_info| {
                comptime var fields: [enum_info.fields.len]EnumField = undefined;

                inline for (&fields, enum_info.fields) |*enum_field, comptime_enum_field| {
                    enum_field.* = .{
                        .name = comptime_enum_field.name,
                        .value = comptime_enum_field.value,
                    };
                }

                const fields_const = fields;

                type_data = .{ .@"enum" = .{
                    .name = @typeName(T),
                    .size = @sizeOf(T),
                    .alignment = @alignOf(T),
                    .tag_type = info(enum_info.tag_type),
                    .fields = &fields_const,
                    .decls = &.{},
                    .is_exhaustive = enum_info.is_exhaustive,
                } };
            },
            .int => |int_info| {
                type_data = .{ .int = .{
                    .signedness = int_info.signedness,
                    .bits = int_info.bits,
                } };
            },
            .float => |float_info| {
                type_data = .{
                    .float = .{
                        .bits = float_info.bits,
                    },
                };
            },
            .bool => {
                type_data = .bool;
            },
            .void => {
                type_data = .void;
            },
            .array => |array_info| {
                type_data = .{
                    .array = .{
                        .len = array_info.len,
                        .child = info(array_info.child),
                        .sentinel = array_info.sentinel,
                    },
                };
            },
            .enum_literal => {
                type_data = .EnumLiteral;
            },
            .pointer => |pointer_info| {
                type_data = .{
                    .Pointer = .{
                        .size = pointer_info.size,
                        .is_const = pointer_info.is_const,
                        .is_volatile = pointer_info.is_volatile,
                        .alignment = pointer_info.alignment,
                        .address_space = pointer_info.address_space,
                        .child = info(pointer_info.child),
                        .is_allowzero = pointer_info.is_allowzero,
                        .sentinel = pointer_info.sentinel,
                    },
                };
            },
            .vector => {},
            .type => {},
            .@"fn" => {},
            else => {
                @compileLog(T);
                @compileError("Type is not supported");
            },
        }

        return type_data;
    }

    ///Returns the full, unambigious name of the type
    pub fn name(self: Type) []const u8 {
        return switch (self) {
            .@"struct" => |struct_info| struct_info.name,
            .@"enum" => |enum_info| enum_info.name,
            .@"union" => |union_info| union_info.name,
            else => "",
        };
    }

    ///Equivalent of @sizeOf(T) builtin
    pub fn size(self: Type) usize {
        switch (self) {
            .@"struct" => |struct_info| return struct_info.size,
            .@"enum" => |enum_info| return enum_info.size,
            .@"union" => |union_info| return union_info.size,
            else => unreachable,
        }
    }

    ///Equivalent of @alignOf(T) builtin
    pub fn alignment(self: Type) usize {
        switch (self) {
            .@"struct" => |struct_info| return struct_info.alignment,
            .@"enum" => |enum_info| return enum_info.alignment,
            .@"union" => |union_info| return union_info.alignment,
            else => unreachable,
        }
    }

    ///Returns true if self represents the type T
    pub fn is(self: *const Type, comptime T: type) bool {
        return self == info(T);
    }

    pub fn getDecl(self: *const Type, decl_name: []const u8) ?Declaration {
        switch (self.*) {
            .Struct => |struct_info| {
                for (struct_info.decls) |decl| {
                    if (std.mem.eql(u8, decl.name, decl_name)) {
                        return decl;
                    }
                }
            },
            else => return null,
        }

        return null;
    }

    pub fn getStructField(self: *const Type, field_name: []const u8) ?StructField {
        switch (self.*) {
            .Struct => |struct_info| {
                for (struct_info.fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        return field;
                    }
                }
            },
            else => unreachable,
        }

        return null;
    }

    pub fn getStructFieldValue(comptime T: type, value: *const anyopaque, field: StructField) *const T {
        const value_pointer = @as([*]const u8, @ptrCast(value)) + field.offset;

        return @as(*const T, @ptrCast(@alignCast(value_pointer)));
    }

    pub fn format(
        self: Type,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("name: {s}", .{self.name()});
    }
};

test {
    const expect = std.testing.expect;

    const ExampleStruct = struct {
        a: f32,
        b: u32,
        c: bool,
    };

    const type_info = Type.info(ExampleStruct);

    try expect(type_info == Type.info(ExampleStruct));

    std.log.warn("type_info.sizeOf() = {}", .{type_info.size()});

    try expect(type_info.is(ExampleStruct));
    try expect(type_info.size() == @sizeOf(ExampleStruct));
    try expect(type_info.alignment() == @alignOf(ExampleStruct));
    try expect(type_info.* == .@"struct");

    switch (type_info.*) {
        .@"struct" => |struct_info| {
            for (struct_info.fields) |field| {
                std.log.warn("field = {s}", .{field.name});

                std.log.warn("type(field) = {any}", .{field.type.*});
            }
        },
        else => unreachable,
    }
}

pub const Options = struct {
    //TODO: allow for reflection data to be disabled and set by quanta_options
};

const std = @import("std");
