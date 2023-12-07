## ZExpress Web Server

An HTTP/1.1 server library for the Zig programming language. It is designed with a focus on simplicity and efficiency, The library uses the Chain of Responsibility design pattern, which allows for a dynamic chain of handlers to process requests.

## Install

The Zig build system has the concept of modules, which are other source files written in Zig. Let’s make use of a module.

From a new folder, run the following commands.

```shell
zig init-exe
git clone https://github.com/ahmdhusam/zexpress.git ./src/libs/
```

Your directory structure should be as follows.

```shell
.
├── build.zig
└── src
    ├── libs
    │   ├── README.md
    │   └── zexpress
    │       ├── index.zig
    │       └── lib
    │           ├── req.zig
    │           ├── res.zig
    │           ├── server.zig
    │           └── shared.zig
    └── main.zig

5 directories, 8 files
```

To your newly made `build.zig`, add the following lines.

```zig
const zexpress = b.addModule("zexpress", .{ .source_file = .{ .path = "src/libs/zexpress/index.zig" } });
exe.addModule("zexpress", zexpress);
```

Now when run via `zig build`, `@import` inside your `main.zig` will work with the string “zexpress”. This means that main has the zexpress package.

Place the following inside your `main.zig` and run `zig build run`.

```zig
const std = @import("std");
const zexpress = @import("zexpress");

var STORAGE: std.AutoHashMap(u64, u8) = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    STORAGE = std.AutoHashMap(u64, u8).init(allocator);

    const app = try zexpress.Server.init(allocator, .{ .reuse_port = true });
    defer app.deinit();

    try app.use("/users", .{ .middlewares = &.{getMiddleware}, .handler = getHandler });
    try app.use("/users/set", .{ .middlewares = &.{setMiddleware}, .handler = setHandler });

    try app.listen(8080, errorHandler);
}

const UserModel = struct { userId: u64, health: u8 };

fn errorHandler(err: anyerror, req: *zexpress.Req, res: *zexpress.Res) void {
    _ = req;

    // Has the responsibility to handle all errors.
    switch (err) {
        else => {
            var errName = @errorName(err);
            const message = std.mem.replaceScalar(u8, @constCast(errName), '_', ' ');

            _ = res.json(.{ .status = res.status.toNumber(), .message = message }) catch unreachable;
        },
    }
}

fn setMiddleware(req: *zexpress.Req, res: *zexpress.Res) !void {
    if (req.method != .POST) {
        _ = res.setStatus(.Not_Found);
        return error.Not_Found;
    }

    const body = try req.bodyAs(*const UserModel);

    if (body.health > 100) {
        _ = res.setStatus(.Bad_Request);
        return error.health_should_be_less_than_or_eql_100;
    }
}

fn setHandler(req: *zexpress.Req, res: *zexpress.Res) !void {
    const body = try req.bodyAs(*const UserModel);

    try STORAGE.put(body.userId, body.health);

    _ = try res.setStatus(.Ok).json(.{ .message = "The health was successfully stored." });
}

fn getMiddleware(req: *zexpress.Req, res: *zexpress.Res) !void {
    if (req.method != .GET) {
        _ = res.setStatus(.Not_Found);
        return error.Not_Found;
    }
}

fn getHandler(req: *zexpress.Req, res: *zexpress.Res) !void {
    // It's optional to run the deinit method.
    var list = std.ArrayList(UserModel).init(req.allocator);

    var usersIter = STORAGE.iterator();

    while (usersIter.next()) |user| {
        try list.append(.{ .userId = user.key_ptr.*, .health = user.value_ptr.* });
    }

    _ = try res.setStatus(.Ok).json(.{ .data = try list.toOwnedSlice() });
}

```
