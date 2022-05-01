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

    return tcpConnectWithHE(list.addrs);
}

const AddrConfig = struct {
    preferred: ?net.Address,
    fallback: ?net.Address,
};

fn getAddrConfig(addrs: []net.Address) AddrConfig {
    var cfg = AddrConfig{
        .preferred = null,
        .fallback = null,
    };
    for (addrs) |addr| {
        switch (addr.any.family) {
            os.AF.INET => cfg.fallback = addr,
            os.AF.INET6 => cfg.preferred = addr,
            else => continue,
        }
    }
    return cfg;
}

fn tcpConnectWithHE(addrs: []net.Address) !net.Stream {
    if (addrs.len == 1) return tcpConnectToAddress(addrs[0]);

    var addrConfig = getAddrConfig(addrs);

    if (addrConfig.preferred) |addr| {
        return tcpConnectToAddress(addr) catch |err| switch (err) {
            error.NetworkUnreachable, error.ConnectionRefused, HappyEyeballsError.Timeout => {
                return tcpConnectToAddress(addrConfig.fallback.?);
            },
            else => return err,
        };
    } else {
        return tcpConnectToAddress(addrConfig.fallback.?);
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
    var passes: usize = 0;
    while (passes < max_passes) : (passes += 1) {
        if (std.io.is_async) {
            const loop = std.event.Loop.instance orelse return error.WouldBlock;
            loop.connect(sockfd, &address.any, address.getOsSockLen()) catch |err| {
                switch (err) {
                    error.WouldBlock, error.ConnectionPending => continue,
                    else => return err,
                }
            };
            loop.sleep(interval);
        } else {
            os.connect(sockfd, &address.any, address.getOsSockLen()) catch |err| {
                switch (err) {
                    error.WouldBlock, error.ConnectionPending => continue,
                    else => return err,
                }
            };
            time.sleep(interval);
            // TODO(jared): set sock flag back to blocking
        }

        return net.Stream{ .handle = sockfd };
    }

    return HappyEyeballsError.Timeout;
}

test "Use functioning IPv6" {
    // TODO(jared): Setup temp server that can respond to this within the test.
    // Currently, run `nc -v6l 1234` before running test.
    const ip6 = net.Address.initIp6(([1]u8{0} ** 15) ++ ([1]u8{1}), 1234, 0, 0);
    var addrs = [_]net.Address{ip6};
    var stream = try tcpConnectWithHE(addrs[0..]);
    defer stream.close();

    // TODO(jared): find better way to initialize IP address. The init value
    // does have meaning.
    var addr = net.Address.initIp4([1]u8{0} ** 4, 0);
    try os.getpeername(stream.handle, &addr.any, &addr.getOsSockLen());
    try std.testing.expect(addr.any.family == os.AF.INET6 and
        addr.in.sa.addr == ip6.in.sa.addr and
        addr.getPort() == 1234);
}

test "Fallback to IPv4" {
    // TODO(jared): Setup temp server that can respond to this within the test.
    // Currently, run `nc -vl 1234` before running test.
    const ip4 = net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 1234);
    // This is a documentation address (part of the 2001:DB8::/32 prefix) and
    // is not routable over the internet.
    const ip6 = net.Address.initIp6(([4]u8{
        0x20,
        0x01,
        0x0D,
        0xB8,
    }) ++ ([1]u8{0} ** 11) ++ ([1]u8{1}), 1234, 0, 0);
    var addrs = [_]net.Address{ ip6, ip4 };
    var stream = try tcpConnectWithHE(addrs[0..]);
    defer stream.close();

    // TODO(jared): find better way to initialize IP address. The init value
    // does have meaning.
    var addr = net.Address.initIp4([1]u8{0} ** 4, 0);
    try os.getpeername(stream.handle, &addr.any, &addr.getOsSockLen());
    try std.testing.expect(addr.any.family == os.AF.INET and
        addr.in.sa.addr == ip4.in.sa.addr and
        addr.getPort() == 1234);
}
