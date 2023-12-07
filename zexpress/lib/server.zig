const std = @import("std");
const net = std.net;
const StreamServer = net.StreamServer;
const Address = net.Address;
const Allocator = std.mem.Allocator;

pub const ServerOptions = StreamServer.Options;

pub const Req = @import("./req.zig").Req;
pub const Res = @import("./res.zig").Res;

pub const Middleware = *const fn (*Req, *Res) anyerror!void;
pub const Handler = *const fn (*Req, *Res) anyerror!void;
pub const ErrorHandler = *const fn (anyerror, *Req, *Res) void;

pub const Server = struct {
    allocator: Allocator,
    streamServer: StreamServer,
    routes: std.StringHashMap(Route),

    const Self = @This();

    pub fn init(alloc: Allocator, options: ServerOptions) !*Self {
        const this: *Self = try alloc.create(Self);
        this.allocator = alloc;
        this.routes = std.StringHashMap(Route).init(this.allocator);

        this.streamServer = StreamServer.init(options);

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
        const ip = try Address.resolveIp("0.0.0.0", port);
        try this.streamServer.listen(ip);

        try this.accept(errorHandler);
    }

    fn accept(this: *Self, errorHandler: ErrorHandler) !void {
        // TODO: Should pass buffer size in global options.
        const buffer = try this.allocator.alloc(u8, std.math.pow(usize, 1024, 2));
        defer this.allocator.free(buffer);

        // TODO: Should make thread pool optional.
        var pool: *std.Thread.Pool = try this.allocator.create(std.Thread.Pool);
        defer this.allocator.destroy(pool);

        // TODO: Should pass n_jobs in global options.
        try pool.init(.{ .allocator = this.allocator, .n_jobs = 4 });
        defer pool.deinit();

        while (true) {
            const connection = try this.streamServer.accept();

            // TODO: Should make thread pool optional.
            try pool.spawn(handle, .{ this, connection, buffer, errorHandler });
            // this.handle(connection, buffer, errorHandler);
        }
    }

    fn handle(this: *Self, connection: StreamServer.Connection, buffer: []u8, errorHandler: ErrorHandler) void {
        defer connection.stream.close();

        const size = connection.stream.reader().read(buffer) catch unreachable;

        const req = Req.parse(this.allocator, buffer[0..size]) catch |err| {
            const er = @errorName(err);
            connection.stream.writer().print("HTTP/1.1 500 Internal Server Error\r\ncontent-length: {}\r\n\r\n{s}", .{ er.len, er }) catch unreachable;
            return;
        };
        defer req.deinit();

        const res = Res.init(this.allocator) catch unreachable;
        defer res.deinit();

        _ = res.setVersion(req.version);

        // handlers
        if (this.routes.get(req.uri)) |handlers| {
            handlers.execute(req, res) catch |err| {
                errorHandler(err, req, res);
            };
        } else {
            res.status = .Not_Found;
        }

        response(connection, res) catch unreachable;
    }

    fn response(connection: StreamServer.Connection, res: *Res) !void {
        const writer = connection.stream.writer();
        try writer.print("{s} {} {s}\r\n", .{ res.version.toString(), res.status.toNumber(), res.status.toString() });

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
