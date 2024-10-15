const std = @import("std");

pub const Method = enum {
    GET,
    POST,
    PATCH,
    PUT,
    DELETE,
    OPTIONS,
    HEAD,
    CONNECT,
    TRACE,
    SEARCH,
    ALL,

    const Self = @This();

    pub fn fromString(str: []const u8) !Self {
        const MethodInfo = @typeInfo(Self);

        inline for (MethodInfo.Enum.fields) |field| {
            if (std.mem.eql(u8, str, field.name)) return @enumFromInt(field.value);
        }

        return error.NotValidMethod;
    }

    pub fn toString(this: Self) []const u8 {
        return @tagName(this);
    }
};

pub const Version = enum {
    V1p1,

    const Self = @This();

    pub fn fromString(str: []const u8) !Self {
        if (std.mem.eql(u8, str, "HTTP/1.1")) return .V1p1;

        return error.NotSupported;
    }

    pub fn toString(this: Self) []const u8 {
        return switch (this) {
            .V1p1 => "HTTP/1.1",
        };
    }
};
