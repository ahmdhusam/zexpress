const std = @import("std");
const net = std.net;
const Address = net.Address;
const Allocator = std.mem.Allocator;

pub const Req = @import("./req.zig").Req;
pub const Res = @import("./res.zig").Res;

pub const Middleware = *const fn (*Req, *Res) anyerror!void;
pub const Handler = *const fn (*Req, *Res) anyerror!void;
pub const ErrorHandler = *const fn (anyerror, *Req, *Res) void;

pub const Server = struct {
    allocator: Allocator,
    streamServer: net.Server = undefined,
    routes: std.StringHashMap(Route),
    options: Options,

    const Options = struct { reuse_port: bool };

    const Self = @This();

    pub fn init(alloc: Allocator, options: Options) !*Self {
        const this: *Self = try alloc.create(Self);

        this.* = .{
            .allocator = alloc,
            .routes = std.StringHashMap(Route).init(this.allocator),
            .options = options,
        };

        return this;
    }

    pub fn deinit(this: *Self) void {
        defer this.allocator.destroy(this);
        this.streamServer.deinit();
        this.routes.deinit();
    }

    pub fn use(this: *Self, path: []const u8, comptime route: Route) !void {
        try this.routes.put(path, route);
    }

    pub fn listen(this: *Self, port: u16, errorHandler: ErrorHandler) !void {
        const ip = try Address.parseIp4("127.0.0.1", port);
        this.streamServer = try ip.listen(.{ .reuse_port = this.options.reuse_port });

        try this.accept(errorHandler);
    }

    fn accept(this: *Self, errorHandler: ErrorHandler) !void {

        // TODO: Should make thread pool optional.
        var pool: *std.Thread.Pool = try this.allocator.create(std.Thread.Pool);
        defer this.allocator.destroy(pool);

        // TODO: Should pass n_jobs in global options.
        try pool.init(.{ .allocator = this.allocator, .n_jobs = 4 });
        defer pool.deinit();

        while (true) {
            const connection = try this.streamServer.accept();
            // TODO: Should pass buffer size in global options.
            const buffer = try this.allocator.alloc(u8, std.math.pow(usize, 1024, 2));
            // TODO: Should make thread pool optional.
            try pool.spawn(handle, .{ this, connection, buffer, errorHandler });
            // this.handle(connection, buffer, errorHandler);
        }
    }

    fn handle(this: *Self, connection: net.Server.Connection, buffer: []u8, errorHandler: ErrorHandler) void {
        defer {
            connection.stream.close();
            this.allocator.free(buffer);
        }

        const size = connection.stream.reader().read(buffer) catch unreachable;

        const req = Req.parse(this.allocator, buffer[0..size]) catch |err| {
            const er = @errorName(err);
            connection.stream.writer().print("HTTP/1.1 500 Internal Server Error\r\ncontent-length: {}\r\n\r\n{s}", .{ er.len, er }) catch unreachable;
            return;
        };
        defer req.deinit();

        const res = Res.init(this.allocator) catch unreachable;
        defer res.deinit();

        _ = res.setStatus(.Not_Found).setVersion(req.version);

        var pathIter = std.mem.split(u8, req.uri, "?");
        const path = pathIter.next() orelse @panic("path is required");
        // handlers
        if (this.routes.get(path)) |handlers| {
            _ = res.setStatus(.Ok);

            handlers.execute(req, res) catch |err| {
                errorHandler(err, req, res);
            };
        }

        response(connection, res) catch unreachable;
    }

    fn response(connection: net.Server.Connection, res: *Res) !void {
        const writer = connection.stream.writer();
        try writer.print("{s} {} {s}\r\n", .{ res.version.toString(), res.status.toNumber(), try res.status.toString() });

        var headersIter = res.headers.iterator();
        while (headersIter.next()) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
        }

        // end of headers
        try writer.print("\r\n", .{});

        if (res.body) |body| try writer.print("{s}", .{body});
    }
};

pub const Route = struct {
    handler: Handler,
    middlewares: []const Middleware,

    const Self = @This();

    pub fn init(handler: Handler, middlewares: []const Middleware) Self {
        return Route{ .handler = handler, .middlewares = middlewares };
    }

    fn execute(this: Self, req: *Req, res: *Res) !void {
        for (this.middlewares) |middleware| {
            try middleware(req, res);
        }

        try this.handler(req, res);
    }
};
