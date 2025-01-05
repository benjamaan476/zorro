const std = @import("std");

const stdin_file = std.io.getStdIn().reader();
const stdout_file = std.io.getStdOut().writer();

var in_br = std.io.bufferedReader(stdin_file);
const stdin = in_br.reader();

var out_bw = std.io.bufferedWriter(stdout_file);
const stdout = out_bw.writer();

const config = struct {
    original_terminal: std.posix.termios = undefined,
    screen_rows: u16 = 0,
    screen_cols: u16 = 0,
};

const cursor = struct {
    row: u16,
    col: u16,
};

const buffer = struct {
    buf: []u8 = undefined,
    allocator: std.mem.Allocator,

    fn init(self: *buffer, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.buf = try self.allocator.alloc(u8, 16);
    }

    fn append(self: *buffer, app: []const u8) !void {
        const old_len = self.buf.len;
        const new = try self.allocator.realloc(self.buf, old_len + app.len);
        std.mem.copyForwards(u8, new[old_len..], app);

        self.buf = new;
    }

    fn print(self: buffer) void {
            std.debug.print("{s}", .{self.buf});
    }

    fn free(self: *buffer) void {
        self.allocator.free(self.buf);
    }
};

var editor: config = .{};

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

fn get_cursor() !cursor {
    try write("\x1b[6n");
    var buf: [32] u8 = undefined;
    const slice = try stdin.readUntilDelimiter(&buf, 'R');

    var splitter = std.mem.tokenizeScalar(u8, slice[2..], ';');
    const row = try std.fmt.parseInt(u16, splitter.next().?, 10);
    const col = try std.fmt.parseInt(u16, splitter.next().?, 10);
    return .{.row = row, .col = col};
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


fn process_keypress() bool {
    const byte = while(true) {
        const c = read();

        if(c != null) break c.?;
    } else '0';

    switch (byte) {
        ctrl('q') => return false,
        else => {
            if(std.ascii.isControl(byte)) {
                write("blah\r\n") catch return false;
            } else {
                write("chkl") catch return false;
                std.debug.print("H\r\n", .{});
            }
        },
    }
    return true;
}

fn draw() !void {
    for(0..editor.screen_cols - 1) |_| {
        try write("~\r\n");
    }
    try write("~");
}

fn refresh_screen() !void {
    _ = try write("\x1b[2J");
    _ = try write("\x1b[H");

    try draw();

    _ = try write("\x1b[H");
}

pub fn main() !void {

    try init();
    defer cleanup();
    errdefer error_cleanup();
    while (true) {
        try refresh_screen();
        if(!process_keypress()) break;
    }
}
