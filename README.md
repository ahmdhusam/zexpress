# ZExpress Web Server

An HTTP/1.1 server library for the Zig programming language. Designed with a focus on simplicity and efficiency, ZExpress uses the Chain of Responsibility design pattern, allowing for a dynamic chain of handlers to process requests.

## Installation

The Zig build system has the concept of modules, which are other source files written in Zig. Let’s make use of a module.

1. Create a new Zig project:

```shell
zig init-exe
```

2. Add ZExpress as a dependency in your `build.zig.zon` file:

```shell
zig fetch git+https://github.com/ahmdhusam/zexpress.git
```

3. Update your `build.zig` file to include ZExpress:

```zig
    // ... existing code ...

    const exe = b.addExecutable(.{
        .name = "your-project-name",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add ZExpress as a module
    const zexpress_module = b.dependency("zexpress", .{
        .target = target,
        .optimize = optimize,
    }).module("zexpress");
    exe.root_module.addImport("zexpress", zexpress_dep);

    // ... existing code ...
}
```

## Usage Example

Here's a simple example demonstrating how to use ZExpress:

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

    try app.use("/users", zexpress.Handler.init(&.{getMiddleware}, getHandler));
    // TODO: Name it set until the implementation of methods routers.
    try app.use("/users/set", .{ .middlewares = &.{setMiddleware}, .handler = setHandler });

    // New route with named parameter
    try app.use("/users/:userId", .{ .middlewares = &.{}, .handler = getUserHandler });

    try app.listen(8080, errorHandler);
}

const UserModel = struct { userId: u64, health: u8 };

fn errorHandler(err: anyerror, req: *zexpress.Req, res: *zexpress.Res) void {
    _ = req;

    // Has the responsibility to handle all errors.
    switch (err) {
         else => |errValue| {
            const errName = @errorName(errValue);
            const message = std.mem.replaceOwned(u8, res.allocator, errName, "_", " ") catch unreachable;

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

fn getUserHandler(req: *zexpress.Req, res: *zexpress.Res) !void {
    const userId = try std.fmt.parseInt(u64, req.params.get("userId").?, 10);
    
    if (STORAGE.get(userId)) |health| {
        _ = try res.setStatus(.Ok).json(.{
            .data = .{ .userId = userId, .health = health }
        });
    } else {
        _ = res.setStatus(.Not_Found);
        return error.User_Not_Found;
    }
}
```

This example sets up a simple server with three routes:
- `GET /users`: Retrieves all users and their health.
- `POST /users/set`: Sets a user's health.
- `GET /users/:userId`: Retrieves a specific user's health using a named parameter.

To run the example:

1. Save the code in `src/main.zig`
2. Run `zig build run`

The server will start on port 8080. You can test it using curl or any HTTP client.

Example requests:

```shell
# Get all users
curl http://localhost:8080/users

# Set a user's health
curl -X POST -H "Content-Type: application/json" -d '{"userId": 1, "health": 100}' http://localhost:8080/users/set

# Get a specific user's health
curl http://localhost:8080/users/1
```

In the last example, `1` is the `:userId` parameter, which can be accessed in the handler using `req.params.get("userId")`.


## Features

- Simple and efficient HTTP/1.1 server
- Middleware support
- JSON request and response handling
- Error handling

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
