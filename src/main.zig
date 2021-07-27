const std = @import("std");

const math = std.math;
const meta = std.meta;
const fs = std.fs;

const assert = std.debug.assert;
const trait = meta.trait;

pub const TextAttributes = struct {
    pub const Color = enum {
        black,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        white,
    };

    foreground: Color = .white,

    bright: bool = false,
    bold: bool = false,
    underline: bool = false,
    reverse: bool = false,
};

pub fn FormatType(comptime fmt: []const u8, comptime Tuple: type) type {
    assert(trait.isTuple(Tuple));

    return struct {
        comptime format: []const u8 = fmt,
        args: Tuple,
    };
}

fn isFormat(comptime T: type) bool {
    return trait.is(.Struct)(T) and trait.hasFields(T, .{ "format", "args" });
}

pub fn format(comptime fmt: []const u8, args: anytype) FormatType(fmt, @TypeOf(args)) {
    return FormatType(fmt, @TypeOf(args)){
        .format = fmt,
        .args = args,
    };
}

const is_windows = std.Target.current.os.tag == .windows;

pub const Terminal = struct {
    pub const WinInterface = enum {
        ansi,
        winconsole,
    };

    pub const OtherInterface = enum {
        ansi,
    };

    pub const Interface = if (is_windows) WinInterface else OtherInterface;

    stdin: fs.File,
    stdout: fs.File,

    interface: Interface,
    enable_attributes: bool = true,
    current_attribute: TextAttributes = TextAttributes{},

    pub fn init() Terminal {
        const stdin = std.io.getStdIn();
        const stdout = std.io.getStdOut();

        var interface: Interface = .ansi;

        if (is_windows) {
            if (!std.os.isCygwinPty(stdin.handle) and !windows.tryPromoteVirtual(stdin, stdout)) {
                interface = .winconsole;
            }
        }

        return .{
            .stdin = stdin,
            .stdout = stdout,
            .interface = interface,
            .enable_attributes = stdout.supportsAnsiEscapeCodes(),
        };
    }

    pub fn enableAttributes(self: *Terminal) void {
        self.enable_attributes = true;
    }

    pub fn disableAttributes(self: *Terminal) void {
        self.enable_attributes = false;
    }

    pub fn applyAttribute(self: *Terminal, attr: TextAttributes) !void {
        self.current_attribute = attr;

        if (is_windows and self.interface == .winconsole) return try windows.applyAttribute(self, attr);

        return try ansi.applyAttribute(self, attr);
    }

    pub fn resetAttributes(self: *Terminal) !void {
        self.current_attribute = .{};

        if (is_windows and self.interface == .winconsole) return try windows.resetAttributes(self);

        return try ansi.resetAttributes(self);
    }

    pub fn switchToAltBuffer(self: *Terminal) !void {
        if (is_windows and self.interface == .winconsole) return try windows.switchToAltBuffer(self);

        return try ansi.switchToAltBuffer(self);
    }

    pub fn switchToMainBuffer(self: *Terminal) !void {
        if (is_windows and self.interface == .winconsole) return try windows.switchToMainBuffer(self);

        return try ansi.switchToMainBuffer(self);
    }

    pub fn cursorMoveUp(self: *Terminal, num: u16) !void {
        if (is_windows and self.interface == .winconsole) return try windows.cursorMoveUp(self, num);

        return try ansi.cursorMoveUp(self, num);
    }

    pub fn cursorMoveDown(self: *Terminal, num: u16) !void {
        if (is_windows and self.interface == .winconsole) return try windows.cursorMoveDown(self, num);

        return try ansi.cursorMoveDown(self, num);
    }

    pub fn cursorMoveRight(self: *Terminal, num: u16) !void {
        if (is_windows and self.interface == .winconsole) return try windows.cursorMoveRight(self, num);

        return try ansi.cursorMoveRight(self, num);
    }

    pub fn cursorMoveLeft(self: *Terminal, num: u16) !void {
        if (is_windows and self.interface == .winconsole) return try windows.cursorMoveLeft(self, num);

        return try ansi.cursorMoveLeft(self, num);
    }

    pub fn setCursorColumn(self: *Terminal, col: u16) !void {
        if (is_windows and self.interface == .winconsole) return try windows.setCursorColumn(self, col);

        return try ansi.setCursorColumn(self, col);
    }

    pub fn setCursorRow(self: *Terminal, row: u16) !void {
        if (is_windows and self.interface == .winconsole) return try windows.setCursorRow(self, row);

        return try ansi.setCursorRow(self, row);
    }

    pub fn setCursorPosition(self: *Terminal, x: u16, y: u16) !void {
        if (is_windows and self.interface == .winconsole) return try windows.setCursorPosition(self, x, y);

        return try ansi.setCursorPosition(self, x, y);
    }

    pub fn printWithAttributes(self: *Terminal, args: anytype) !void {
        comptime var i = 0;

        inline while (i < args.len) : (i += 1) {
            const arg = args[i];

            const T = @TypeOf(arg);
            const info = @typeInfo(T);

            switch (T) {
                TextAttributes => {
                    try self.applyAttribute(arg);
                    continue;
                },
                TextAttributes.Color => {
                    try self.applyAttribute(.{ .foreground = arg });
                    continue;
                },
                else => {
                    if (comptime trait.isZigString(T)) {
                        try self.stdout.writeAll(arg);
                        continue;
                    }

                    switch (info) {
                        .EnumLiteral => {
                            if (arg == .reset) {
                                try self.resetAttributes();
                            } else {
                                try self.applyAttribute(.{ .foreground = arg });
                            }

                            continue;
                        },
                        .Struct => {
                            if (comptime trait.isTuple(T) and arg.len == 2 and trait.isZigString(@TypeOf(arg[0])) and trait.isTuple(@TypeOf(arg[1]))) {
                                try self.writer().print(arg[0], arg[1]);
                                continue;
                            }

                            if (comptime isFormat(T)) {
                                try self.writer().print(arg.format, arg.args);
                                continue;
                            }

                            var attr = TextAttributes{};

                            const fields = meta.fields(T);
                            inline for (fields) |field| {
                                if (!@hasField(TextAttributes, field.name)) @compileError("Could not cast anonymous struct to TextAttributes, found extraneous field " ++ field.name);

                                @field(attr, field.name) = @field(arg, field.name);
                            }

                            try self.applyAttribute(attr);
                            continue;
                        },
                        else => {},
                    }
                },
            }

            @compileError("Expected a string, tuple, enum literal or TextAttribute, found " ++ @typeName(T));
        }
    }

    pub fn reader(self: Terminal) fs.File.Reader {
        return self.stdin.reader();
    }

    pub fn writer(self: Terminal) fs.File.Writer {
        return self.stdout.writer();
    }
};

pub const windows = struct {
    const win = std.os.windows;

    const HANDLE = win.HANDLE;
    const WINAPI = win.WINAPI;

    extern "kernel32" fn GetConsoleMode(hConsole: HANDLE, mode: *u16) callconv(WINAPI) c_int;
    extern "kernel32" fn SetConsoleMode(hConsole: HANDLE, mode: u16) callconv(WINAPI) c_int;
    extern "kernel32" fn GetConsoleScreenBufferInfo(hConsole: HANDLE, consoleScreenBufferInfo: *win.CONSOLE_SCREEN_BUFFER_INFO) callconv(WINAPI) c_int;
    extern "kernel32" fn SetConsoleTextAttribute(hConsole: HANDLE, attributes: u16) callconv(WINAPI) c_int;
    extern "kernel32" fn SetConsoleCursorPosition(hConsole: HANDLE, cursorPosition: win.COORD) callconv(WINAPI) c_int;

    var last_attribute: u16 = 0;

    const FG_RED = win.FOREGROUND_RED;
    const FG_GREEN = win.FOREGROUND_GREEN;
    const FG_BLUE = win.FOREGROUND_BLUE;
    const FG_INTENSE = win.FOREGROUND_INTENSITY;
    const TXT_REVERSE = 0x4000;
    const TXT_UNDERSCORE = 0x8000;

    const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
    const ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
    const DISABLE_NEWLINE_AUTO_RETURN = 0x0008;

    const stdout_mode_request = ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN;
    const stdin_mode_request = ENABLE_VIRTUAL_TERMINAL_INPUT;

    fn tryPromoteVirtual(stdin: std.fs.File, stdout: std.fs.File) bool {
        var stdout_mode: u16 = 0;
        var stdin_mode: u16 = 0;

        if (GetConsoleMode(stdout.handle, &stdout_mode) == 0) return false;
        if (GetConsoleMode(stdin.handle, &stdin_mode) == 0) return false;

        if (stdout_mode & stdout_mode_request == stdout_mode_request and stdin_mode & stdin_mode_request == stdin_mode_request) return true;

        const new_stdout_mode = stdout_mode | stdout_mode_request;
        const new_stdin_mode = stdin_mode | stdin_mode_request;

        if (SetConsoleMode(stdout.handle, new_stdout_mode) == 0) return false;
        if (SetConsoleMode(stdin.handle, new_stdin_mode) == 0) return false;

        return true;
    }

    fn attrToWord(attr: TextAttributes) u16 {
        var base = if (attr.bright or attr.bold) FG_INTENSE else 0;

        if (attr.reverse) base |= TXT_REVERSE;
        if (attr.underline) base |= TXT_UNDERSCORE;

        return switch (attr.foreground) {
            .black => base,
            .red => base | FG_RED,
            .green => base | FG_GREEN,
            .yellow => base | FG_RED | FG_GREEN,
            .blue => base | FG_BLUE,
            .magenta => base | FG_RED | FG_BLUE,
            .cyan => base | FG_GREEN | FG_BLUE,
            .white => base | FG_RED | FG_GREEN | FG_BLUE,
        };
    }

    pub fn applyAttribute(term: *const Terminal, attr: TextAttributes) !void {
        if (windows.SetConsoleTextAttribute(term.stdin.handle, attrToWord(attr)) != 0) {
            return error.Unexpected;
        }
    }

    pub fn resetAttributes(term: *const Terminal) !void {
        try applyAttribute(term, .{});
    }

    pub fn switchToAltBuffer(_: *const Terminal) !void {}
    pub fn switchToMainBuffer(_: *const Terminal) !void {}

    pub fn cursorMoveUp(term: *const Terminal, n: u16) !void {
        var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

        if (GetConsoleScreenBufferInfo(term.stdout.handle, &info) == 0) return error.Unexpected;

        var cursor = info.dwCursorPosition;
        cursor.Y -= n;

        if (SetConsoleCursorPosition(term.stdout.handle, cursor) == 0) return error.Unexpected;
    }

    pub fn cursorMoveDown(term: *const Terminal, n: u16) !void {
        var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

        if (GetConsoleScreenBufferInfo(term.stdout.handle, &info) == 0) return error.Unexpected;

        var cursor = info.dwCursorPosition;
        cursor.Y += n;

        if (SetConsoleCursorPosition(term.stdout.handle, cursor) == 0) return error.Unexpected;
    }

    pub fn cursorMoveRight(term: *const Terminal, n: u16) !void {
        var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

        if (GetConsoleScreenBufferInfo(term.stdout.handle, &info) == 0) return error.Unexpected;

        var cursor = info.dwCursorPosition;
        cursor.X += n;

        if (SetConsoleCursorPosition(term.stdout.handle, cursor) == 0) return error.Unexpected;
    }

    pub fn cursorMoveLeft(term: *const Terminal, n: u16) !void {
        var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

        if (GetConsoleScreenBufferInfo(term.stdout.handle, &info) == 0) return error.Unexpected;

        var cursor = info.dwCursorPosition;
        cursor.X -= n;

        if (SetConsoleCursorPosition(term.stdout.handle, cursor) == 0) return error.Unexpected;
    }

    pub fn setCursorColumn(term: *const Terminal, col: u16) !void {
        var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

        if (GetConsoleScreenBufferInfo(term.stdout.handle, &info) == 0) return error.Unexpected;

        var cursor = info.dwCursorPosition;
        cursor.X = col;

        if (SetConsoleCursorPosition(term.stdout.handle, cursor) == 0) return error.Unexpected;
    }

    pub fn setCursorRow(term: *const Terminal, row: u16) !void {
        var info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;

        if (GetConsoleScreenBufferInfo(term.stdout.handle, &info) == 0) return error.Unexpected;

        var cursor = info.dwCursorPosition;
        cursor.Y = row;

        if (SetConsoleCursorPosition(term.stdout.handle, cursor) == 0) return error.Unexpected;
    }

    pub fn setCursorPosition(term: *const Terminal, x: u16, y: u16) !void {
        const cursor = win.COORD{
            .X = x,
            .Y = y,
        };

        if (SetConsoleCursorPosition(term.stdout.handle, cursor) == 0) return error.Unexpected;
    }
};

pub const ansi = struct {
    fn attrToSgr(attr: TextAttributes) u16 {
        const base: u16 = if (attr.bright) 90 else 30;

        return switch (attr.foreground) {
            .black => base,
            .red => base + 1,
            .green => base + 2,
            .yellow => base + 3,
            .blue => base + 4,
            .magenta => base + 5,
            .cyan => base + 6,
            .white => base + 7,
        };
    }

    pub fn applyAttribute(term: *const Terminal, attr: TextAttributes) !void {
        try term.stdout.writeAll("\x1b[0;");

        if (attr.reverse) try term.stdout.writeAll("7;");
        if (attr.underline) try term.stdout.writeAll("4;");
        if (attr.bold) try term.stdout.writeAll("1;");
        try term.stdout.writer().print("{d}m", .{attrToSgr(attr)});
    }

    pub fn resetAttributes(term: *const Terminal) !void {
        try term.stdout.writeAll("\x1b[0m");
    }

    pub fn switchToAltBuffer(term: *const Terminal) !void {
        try term.stdout.writeAll("\x1b[?1049h");
    }

    pub fn switchToMainBuffer(term: *const Terminal) !void {
        try term.stdout.writeAll("\x1b[?1049l");
    }

    pub fn cursorMoveUp(term: *const Terminal, n: u16) !void {
        try term.stdout.writeAll("\x1b[{d}A", n);
    }

    pub fn cursorMoveDown(term: *const Terminal, n: u16) !void {
        try term.stdout.writeAll("\x1b[{d}B", n);
    }

    pub fn cursorMoveRight(term: *const Terminal, n: u16) !void {
        try term.stdout.writeAll("\x1b[{d}C", n);
    }

    pub fn cursorMoveLeft(term: *const Terminal, n: u16) !void {
        try term.stdout.writeAll("\x1b[{d}D", n);
    }

    pub fn setCursorColumn(term: *const Terminal, col: u16) !void {
        try term.stdout.writeAll("\x1b[{d}G", col);
    }

    pub fn setCursorRow(term: *const Terminal, row: u16) !void {
        try term.stdout.writeAll("\x1b[{d}f", row);
    }

    pub fn setCursorPosition(term: *const Terminal, x: u16, y: u16) !void {
        try term.stdout.writeAll("\x1b[{d};{d}H", y, x);
    }
};
