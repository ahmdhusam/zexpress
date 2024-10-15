const std = @import("std");
const Allocator = std.mem.Allocator;
const shared = @import("./shared.zig");
const Method = shared.Method;
const Version = shared.Version;

pub const Req = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: Allocator,
    httpStaticString: []const u8,
    method: Method,
    uri: []const u8,
    version: Version,
    headers: std.StringHashMap([]const u8),
    bodyString: ?[]const u8 = null,
    params: Params = undefined,

    const Self = @This();
    pub const Params = std.StringHashMap([]const u8);

    fn init(allocator: Allocator, httpStaticString: []u8) !*Self {
        const arena: *std.heap.ArenaAllocator = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);

        arena.* = std.heap.ArenaAllocator.init(allocator);

        const this: *Self = try arena.allocator().create(Self);
        this.arena = arena;
        this.allocator = this.arena.allocator();
        this.httpStaticString = httpStaticString;
        this.headers = std.StringHashMap([]const u8).init(this.allocator);
        this.bodyString = null;

        return this;
    }

    pub fn deinit(this: *Self) void {
        const alloc = this.arena.child_allocator;
        const arena = this.arena;

        defer alloc.destroy(arena);
        this.arena.deinit();
    }

    pub fn parse(allocator: Allocator, httpStaticString: []u8) !*Self {
        const this = try init(allocator, httpStaticString);
        errdefer this.deinit();

        var httpIter = std.mem.split(u8, httpStaticString, "\r\n\r\n");

        var headersIter = std.mem.split(u8, httpIter.next() orelse return error.RequiredContext, "\r\n");

        const body = httpIter.next() orelse "";

        if (!std.mem.eql(u8, body, "")) this.bodyString = body;

        try this.parseContext(headersIter.next() orelse return error.ParseFailed);

        while (headersIter.next()) |header| {
            if (std.mem.eql(u8, header, "")) break;

            var headerIter = std.mem.split(u8, header, ":");

            const key = headerIter.next() orelse continue;
            var value = headerIter.next() orelse continue;
            if (value[0] == ' ') value = value[1..];

            try this.headers.put(key, value);
        }

        return this;
    }

    pub fn bodyAs(this: *Self, comptime T: type) !T {
        const typeInfo = @typeInfo(T);
        comptime if (typeInfo != .Pointer) @compileError("T Should be Pointer");

        const bodyString = this.bodyString orelse return error.RequiredBody;

        if (T == []const u8 or T == []u8) return bodyString;

        return switch (typeInfo) {
            .Pointer => (try std.json.parseFromSlice(T, this.allocator, bodyString, .{})).value,
            else => error.NotSupported,
        };
    }

    pub fn getHeader(this: *Self, key: []const u8) ?[]const u8 {
        return this.headers.get(key);
    }

    fn parseContext(this: *Self, ctxStr: []const u8) !void {
        var ctxIter = std.mem.split(u8, ctxStr, " ");

        try this.setMethod(ctxIter.next() orelse return error.RequiredMethod);
        this.setURI(ctxIter.next() orelse return error.RequiredURI);
        try this.setVersion(ctxIter.next() orelse return error.RequiredVersion);
    }

    fn setMethod(this: *Self, str: []const u8) !void {
        this.method = try Method.fromString(str);
    }

    fn setURI(this: *Self, str: []const u8) void {
        this.uri = str;
    }

    fn setVersion(this: *Self, str: []const u8) !void {
        this.version = try Version.fromString(str);
    }

    pub fn setParams(this: *Self, params: Params) void {
        this.params = params;
    }
};
