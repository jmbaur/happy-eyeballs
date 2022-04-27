const std = @import("std");
const builtin = @import("builtin");
const net = std.net;
const os = std.os;
const time = std.time;
const mem = std.mem;

// pub const io_mode = .evented;

const happy_eyeballs_timeout = 300 * time.ns_per_ms;

const HappyEyeballsError = error{
    Timeout,
};

fn tcpConnectToHost(allocator: mem.Allocator, name: []const u8, port: u16) !net.Stream {
    const list = try net.getAddressList(allocator, name, port);
    defer list.deinit();

    if (list.addrs.len == 0) return error.UnknownHostName;

    for (list.addrs) |addr| {
        var stream = tcpConnectToAddress(addr) catch |err| switch (err) {
            error.ConnectionRefused, HappyEyeballsError.Timeout => continue,
            else => return err,
        };
        defer stream.close();
    }

    return std.os.ConnectError.ConnectionRefused;
}

fn tcpConnectToAddress(address: net.Address) !net.Stream {
    const nonblock = os.SOCK.NONBLOCK;
    const sock_flags = os.SOCK.STREAM | nonblock |
        (if (builtin.target.os.tag == .windows) 0 else os.SOCK.CLOEXEC);
    const sockfd = try os.socket(address.any.family, sock_flags, os.IPPROTO.TCP);
    errdefer os.closeSocket(sockfd);

    const interval = 50 * time.ns_per_ms;
    const max_passes = happy_eyeballs_timeout / interval;
    var passes: u8 = 0;
    while (passes < max_passes) : (passes += 1) {
        if (std.io.is_async) {
            const loop = std.event.Loop.instance orelse return error.WouldBlock;
            loop.connect(sockfd, &address.any, address.getOsSockLen()) catch |err| {
                switch (err) {
                    error.WouldBlock, error.ConnectionPending => continue,
                    else => return err,
                }
            };
        } else {
            os.connect(sockfd, &address.any, address.getOsSockLen()) catch |err| {
                switch (err) {
                    error.WouldBlock, error.ConnectionPending => continue,
                    else => return err,
                }
            };
            // TODO(jared): set sock flag back to blocking
        }

        return net.Stream{ .handle = sockfd };
    }

    return HappyEyeballsError.Timeout;
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    _ = tcpConnectToHost(alloc, "google.com", 22) catch |err| {
        std.debug.print("{}", .{err});
    };
}
