const std = @import("std");
const builtin = @import("builtin");
const event = std.event;
const io = std.io;
const net = std.net;
const os = std.os;
const print = std.debug.print;
const time = std.time;
const mem = std.mem;

pub const io_mode = .evented;

const Error = error{
    Timeout,
};

fn tcpConnectToHost(allocator: mem.Allocator, name: []const u8, port: u16) !net.Stream {
    const list = try net.getAddressList(allocator, name, port);
    defer list.deinit();

    if (list.addrs.len == 0) return error.UnknownHostName;

    var buffer = try allocator.alloc(bool, 2);
    defer allocator.free(buffer);
    var chan: event.Channel(bool) = undefined;
    chan.init(buffer);
    defer chan.deinit();

    for (list.addrs) |addr| {
        _ = async sleep(&chan);
        var stream_frame = async connectToAddr(&chan, addr);
        const timed_out = await async chan.get();
        if (timed_out) continue;
        var stream = await stream_frame catch |err| switch (err) {
            error.ConnectionRefused => {
                continue;
            },
            else => return err,
        };
        defer stream.close();
    }

    return std.os.ConnectError.ConnectionRefused;
}

fn sleep(chan: *event.Channel(bool)) void {
    print("sleeping\n", .{});
    time.sleep(250 * time.ns_per_ms);
    chan.put(true);
    print("done sleeping\n", .{});
}

fn connectToAddr(chan: *event.Channel(bool), address: net.Address) !net.Stream {
    print("attempting to connect\n", .{});
    var stream = net.tcpConnectToAddress(address);
    chan.put(false);
    print("connected successfully\n", .{});
    return stream;
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    _ = try tcpConnectToHost(alloc, "google.com", 22);
}
