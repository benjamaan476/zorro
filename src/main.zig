const std = @import("std");

const stdin_file = std.io.getStdIn().reader();
var br = std.io.bufferedReader(stdin_file);
const stdin = br.reader();

fn read() ?u8 {
    return stdin.readByte() catch return null;
}

pub fn main() !void {
    var term = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    term.lflag.ECHO = false;

    try std.posix.tcsetattr(std.posix.STDIN_FILENO, std.posix.TCSA.FLUSH, term);
    while (read()) |byte| {
        if (byte == 'q') break;

        std.debug.print("Read byte: {}, \\0b{b}\n", .{ byte, byte });
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const global = struct {
        fn testOne(input: []const u8) anyerror!void {
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(global.testOne, .{});
}
