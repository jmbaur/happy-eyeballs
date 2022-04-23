const std = @import("std");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) unreachable;
    }
    const alloc = gpa.allocator();
    var addrList = try std.net.getAddressList(alloc, "localhost", 22);
    defer addrList.deinit();
    std.debug.print("{v}\n", .{addrList.addrs});
}
