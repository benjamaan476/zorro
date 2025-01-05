const std = @import("std");

const stdin_file = std.io.getStdIn().reader();
const stdout_file = std.io.getStdOut().writer();

var in_br = std.io.bufferedReader(stdin_file);
const stdin = in_br.reader();

var out_bw = std.io.bufferedWriter(stdout_file);
const stdout = out_bw.writer();

const Config = struct {
    original_terminal: std.posix.termios = undefined,
    screen_rows: u16 = 0,
    screen_cols: u16 = 0,
    cursor: Cursor = .{ .row = 0, .col = 0 },
};

const Cursor = struct {
    row: u16,
    col: u16,
};

const Buffer = std.ArrayList(u8);

var editor: Config = .{};

fn read() ?u8 {
    return stdin.readByte() catch return null;
}

fn write(out: []const u8) !void {
    _ = try std.posix.write(std.posix.STDOUT_FILENO, out);
}

fn cleanup() void {
    std.posix.tcsetattr(std.posix.STDIN_FILENO, std.posix.TCSA.FLUSH, editor.original_terminal) catch return;
    write("\x1b[2J") catch return;
    write("\x1b[H") catch return;
}

fn error_cleanup() void {
    _ = std.io.getStdErr().write("Error\r\n") catch return;
    cleanup();
}

fn ctrl(byte: u8) u8 {
    return byte & 0x1f;
}

fn setup_terminal(terminal: *std.posix.termios) !void {
    terminal.lflag.ECHO = false;
    terminal.lflag.ICANON = false;
    terminal.lflag.ISIG = false;
    terminal.lflag.IEXTEN = false;
    terminal.iflag.BRKINT = false;
    terminal.iflag.INPCK = false;
    terminal.iflag.ISTRIP = false;
    terminal.iflag.IXON = false;
    terminal.iflag.ICRNL = false;
    terminal.oflag.OPOST = false;
    terminal.cflag.CSIZE = std.posix.CSIZE.CS8;
    terminal.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    terminal.cc[@intFromEnum(std.posix.V.TIME)] = 1;
}

fn move_cursor(cursor: *Cursor, by: struct { x: i16, y: i16 }) void {
    cursor.col = @intCast(std.math.clamp(@as(i16, @intCast(cursor.col)) + by.x, 0, @as(i16, @intCast(editor.screen_cols - 1))));
    cursor.row = @intCast(std.math.clamp(@as(i16, @intCast(cursor.row)) + by.y, 0, @as(i16, @intCast(editor.screen_rows - 1))));
}

fn init() !void {
    var term = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    editor.original_terminal = term;

    var winsize: std.posix.winsize = undefined;
    _ = std.posix.system.ioctl(std.posix.STDIN_FILENO, std.posix.system.T.IOCGWINSZ, @intFromPtr(&winsize));

    editor.screen_rows = winsize.row;
    editor.screen_cols = winsize.col;

    try setup_terminal(&term);

    try std.posix.tcsetattr(std.posix.STDIN_FILENO, std.posix.TCSA.FLUSH, term);
}

const Key = enum {
    Left,
    Right,
    Up,
    Down,
    Del,
    Home,
    End,
    PageUp,
    PageDown,
    Exit,
};

const Character = union(enum) {
    key: Key,
    char: u8,
};

fn read_key() Character {
    const byte = while (true) {
        const c = read();

        if (c != null) break c.?;
    } else '0';

    switch (byte) {
        '\x1b' => {
            var seq: [3]u8 = undefined;
            seq[0] = read().?;
            seq[1] = read().?;
            if (seq[0] == '[') {
                if (seq[1] >= '0' and seq[1] <= '9') {
                    seq[2] = read().?;
                    if (seq[2] == '~') {
                        switch (seq[1]) {
                            '1', '7' => return .{ .key = Key.Home },
                            '4', '8' => return .{ .key = Key.End },
                            '5' => return .{ .key = Key.PageUp },
                            '6' => return .{ .key = Key.PageDown },
                            else => {},
                        }
                    }
                } else {
                    switch (seq[1]) {
                        'A' => return .{ .key = Key.Up },
                        'B' => return .{ .key = Key.Down },
                        'C' => return .{ .key = Key.Right },
                        'D' => return .{ .key = Key.Left },
                        else => {},
                    }
                }
            } else if (seq[0] == 'O') {
                switch (seq[1]) {
                    'H' => return .{ .key = Key.Home },
                    'F' => return .{ .key = Key.End },
                    else => {},
                }
            }
        },
        else => {},
    }
    return .{ .char = byte };
}

fn process_keypress() bool {
    const char = read_key();
    switch (char) {
        .key => |*key| {
            switch (key.*) {
                .Left => move_cursor(&editor.cursor, .{ .x = -1, .y = 0 }),
                .Right => move_cursor(&editor.cursor, .{ .x = 1, .y = 0 }),
                .Up => move_cursor(&editor.cursor, .{ .x = 0, .y = -1 }),
                .Down => move_cursor(&editor.cursor, .{ .x = 0, .y = 1 }),
                .Home => move_cursor(&editor.cursor, .{ .x = -@as(i16, @intCast(editor.screen_cols)), .y = 0 }),
                .End => move_cursor(&editor.cursor, .{ .x = @as(i16, @intCast(editor.screen_cols)), .y = 0 }),
                .PageUp => move_cursor(&editor.cursor, .{ .x = 0, .y = -@as(i16, @intCast(editor.screen_rows)) }),
                .PageDown => move_cursor(&editor.cursor, .{ .x = 0, .y = @intCast(editor.screen_rows) }),
                .Del => {},
                .Exit => return false,
            }
        },
        .char => |c| {
            switch (c) {
                ctrl('q') => return false,
                's', 'j' => move_cursor(&editor.cursor, .{ .x = 0, .y = 1 }),
                'w', 'k' => move_cursor(&editor.cursor, .{ .x = 0, .y = -1 }),
                'a', 'h' => move_cursor(&editor.cursor, .{ .x = -1, .y = 0 }),
                'd', 'l' => move_cursor(&editor.cursor, .{ .x = 1, .y = 0 }),
                else => {},
            }
        },
    }
    return true;
}

const ConsoleCommand = enum {
    clear_screen,
    clear_line,
    reset_cursor,
    hide_cursor,
    show_cursor,

    pub fn format(self: ConsoleCommand, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        const out = switch (self) {
            .clear_screen => "\x1b[2J",
            .clear_line => "\x1b[K",
            .reset_cursor => "\x1b[H",
            .hide_cursor => "\x1b[?25l",
            .show_cursor => "\x1b[?25h",
        };

        try writer.print("{s}", .{out});
    }
};

fn draw(buf: *Buffer) !void {
    for (0..editor.screen_rows - 1) |y| {
        try buf.writer().print("{s}", .{ConsoleCommand.clear_line});
        if (y == editor.screen_rows / 3) {
            const message: []const u8 = "zorro editor -- version: 0.0.1";
            try buf.writer().print("{s: ^[1]}", .{ message, editor.screen_cols });
        } else {
            try buf.writer().writeAll("~\r\n");
        }
    }
    try buf.writer().writeAll("~");
}

fn refresh_screen() !void {
    var buffer = Buffer.init(std.heap.page_allocator);
    try buffer.writer().print("{s}", .{ConsoleCommand.hide_cursor});
    try buffer.writer().print("{s}", .{ConsoleCommand.clear_screen});
    try draw(&buffer);
    try buffer.writer().print("\x1b[{d};{d}H", .{ editor.cursor.row + 1, editor.cursor.col + 1 });
    try buffer.writer().print("{s}", .{ConsoleCommand.show_cursor});

    try write(buffer.items);
    buffer.clearAndFree();
}

pub fn main() !void {
    try init();
    defer cleanup();
    errdefer error_cleanup();
    while (true) {
        try refresh_screen();
        if (!process_keypress()) break;
    }
}
