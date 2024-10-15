const std = @import("std");
const Allocator = std.mem.Allocator;
const shared = @import("./shared.zig");
const Method = shared.Method;
const Version = shared.Version;

pub const Res = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: Allocator,
    version: Version = undefined,
    _status: Status = undefined,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8 = null,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        const arena: *std.heap.ArenaAllocator = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);

        arena.* = std.heap.ArenaAllocator.init(allocator);

        const this: *Self = try arena.allocator().create(Self);
        this.arena = arena;
        this.allocator = this.arena.allocator();
        this.headers = std.StringHashMap([]const u8).init(this.allocator);
        this.body = null;

        return this;
    }

    pub fn deinit(this: *Self) void {
        const alloc = this.arena.child_allocator;
        const arena = this.arena;

        defer alloc.destroy(arena);
        this.arena.deinit();
    }

    pub fn setVersion(this: *Self, version: Version) *Self {
        this.version = version;
        return this;
    }

    pub fn status(this: *Self, _status: Status) *Self {
        this._status = _status;
        return this;
    }

    pub fn json(this: *Self, value: anytype) !*Self {
        const typeInfo = @typeInfo(@TypeOf(value));
        comptime if (!(typeInfo == .Struct or typeInfo == .Pointer)) {
            @compileError("value should be of type Struct or Pointer.");
        };

        _ = try this.setBody(try std.json.stringifyAlloc(this.allocator, value, .{}));
        try this.setHeader("content-type", "application/json");

        return this;
    }

    pub fn setBody(this: *Self, content: []const u8) !*Self {
        try this.setHeader("content-length", try std.fmt.allocPrint(this.allocator, "{}", .{content.len}));
        this.body = content;
        return this;
    }

    pub fn setHeader(this: *Self, key: []const u8, value: []const u8) !void {
        try this.headers.put(key, value);
    }
};

pub const Status = enum(u16) {
    Continue = 100,
    Switching_Protocols = 101,
    Processing = 102,
    Earlyhints = 103,
    Ok = 200,
    Created = 201,
    Accepted = 202,
    Non_Authoritative_Information = 203,
    No_Content = 204,
    Reset_Content = 205,
    Partial_Content = 206,
    Ambiguous = 300,
    Moved_Permanently = 301,
    Found = 302,
    See_Other = 303,
    Not_Modified = 304,
    Temporary_Redirect = 307,
    Permanent_Redirect = 308,
    Bad_Request = 400,
    Unauthorized = 401,
    Payment_Required = 402,
    Forbidden = 403,
    Not_Found = 404,
    Method_Not_Allowed = 405,
    Not_Acceptable = 406,
    Proxy_Authentication_Required = 407,
    Request_Timeout = 408,
    Conflict = 409,
    Gone = 410,
    Length_Required = 411,
    Precondition_Failed = 412,
    Payload_Too_Large = 413,
    Uri_Too_Long = 414,
    Unsupported_Media_Type = 415,
    Requested_Range_Not_Satisfiable = 416,
    Expectation_Failed = 417,
    I_Am_A_Teapot = 418,
    Misdirected = 421,
    Unprocessable_Entity = 422,
    Failed_Dependency = 424,
    Precondition_Required = 428,
    Too_Many_Requests = 429,
    Internal_Server_Error = 500,
    Not_Implemented = 501,
    Bad_Gateway = 502,
    Service_Unavailable = 503,
    Gateway_Timeout = 504,
    Http_Version_Not_Supported = 505,

    const Self = @This();

    pub fn toNumber(this: Self) u16 {
        return @intFromEnum(this);
    }

    pub fn toString(this: *Self) ![]const u8 {
        switch (this.*) {
            inline else => |v| {
                const res: *Res = @alignCast(@fieldParentPtr("_status", this));

                const name = try std.mem.replaceOwned(u8, res.allocator, @tagName(v), "_", " ");

                return name;
            },
        }
    }
};
