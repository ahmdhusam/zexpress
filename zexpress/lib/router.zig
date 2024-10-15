const std = @import("std");
const Allocator = std.mem.Allocator;
const Req = @import("req.zig").Req;
const Res = @import("res.zig").Res;
const Params = Req.Params;

pub const Middleware = *const fn (*Req, *Res) anyerror!void;
pub const HandlerFn = *const fn (*Req, *Res) anyerror!void;

pub const Handler = struct {
    handlerFn: HandlerFn,
    middlewares: []const Middleware,

    const Self = @This();

    pub fn init(middlewares: []const Middleware, handlerFn: HandlerFn) Self {
        return Self{ .middlewares = middlewares, .handlerFn = handlerFn };
    }

    pub fn execute(this: Self, req: *Req, res: *Res) !void {
        for (this.middlewares) |middleware| {
            try middleware(req, res);
        }

        try this.handlerFn(req, res);
    }
};

pub const Router = struct {
    allocator: Allocator,
    root: *Node,

    const Route = struct {
        handler: Handler,
        params: Params,
    };

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return .{ .allocator = allocator, .root = try Node.init(allocator) };
    }

    pub fn deinit(this: *const Self) void {
        this.root.deinit(this.allocator);
        this.allocator.destroy(this.root);
    }

    pub fn addRoute(this: *const Self, path: []const u8, handler: Handler) !void {
        try this.root.addRoute(this.allocator, path, handler);
    }

    pub fn matchRoute(this: *const Self, path: []const u8) !Route {
        return this.root.matchRoute(this.allocator, path);
    }
};

const Node = struct {
    routes: std.StringHashMap(*Self),
    paramName: ?[]const u8 = null,
    handler: ?Handler = null,

    const Self = @This();

    fn init(allocator: Allocator) !*Self {
        const this = try allocator.create(Self);
        this.* = .{ .routes = std.StringHashMap(*Self).init(allocator) };

        return this;
    }

    fn deinit(this: *Self, allocator: Allocator) void {
        defer this.routes.deinit();

        var it = this.routes.iterator();
        while (it.next()) |entry| {
            const nodePtr: *Self = entry.value_ptr.*;
            nodePtr.deinit(allocator);
            allocator.destroy(nodePtr);
        }
    }

    fn addRoute(this: *Self, allocator: Allocator, path: []const u8, handler: Handler) !void {
        var current = this;
        var pathIter = std.mem.split(u8, std.mem.trim(u8, path, "/"), "/");

        while (pathIter.next()) |segment| {
            if (segment.len == 0) continue;

            if (segment[0] == ':') {
                current = try current.addParamNode(allocator, segment[1..]);
            } else {
                current = try current.addStaticNode(allocator, segment);
            }
        }

        current.handler = handler;
    }

    fn addParamNode(this: *Self, allocator: Allocator, paramName: []const u8) !*Self {
        if (this.routes.get("*")) |node| {
            return node;
        }

        this.paramName = paramName;
        const newNode = try Self.init(allocator);
        try this.routes.put("*", newNode);

        return newNode;
    }

    fn addStaticNode(this: *Self, allocator: Allocator, segment: []const u8) !*Self {
        if (this.routes.get(segment)) |node| {
            return node;
        }

        const newNode = try Self.init(allocator);
        try this.routes.put(segment, newNode);

        return newNode;
    }

    fn matchRoute(this: *Self, allocator: Allocator, path: []const u8) !Router.Route {
        var current = this;
        var params = Params.init(allocator);
        errdefer params.deinit();

        var pathIter = std.mem.split(u8, std.mem.trim(u8, path, "/"), "/");

        while (pathIter.next()) |segment| {
            if (segment.len == 0) continue;

            if (current.routes.get(segment)) |next| {
                current = next;
            } else if (current.routes.get("*")) |paramNode| {
                // Match named parameter
                if (current.paramName) |name| {
                    try params.put(name, segment);
                }
                current = paramNode;
            } else {
                return error.RouteNotFound;
            }
        }

        if (current.handler) |handler|
            return .{ .handler = handler, .params = params };

        return error.RouteNotFound;
    }
};
