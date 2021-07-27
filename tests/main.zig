const terminal = @import("zig-terminal");

pub fn main() !void {
    var term = terminal.Terminal.init();

    var haze = "Haze";

    try term.printWithAttributes(.{
        terminal.TextAttributes{
            .foreground = .red,
            .bold = true,
        },
        "Hello, World!\n",
        terminal.TextAttributes.Color.green,
        "Hello, World!\n",
        .yellow,
        "Hello, World!\n",
        .{
            .foreground = .blue,
            .bright = true,
            .bold = true,
            .underline = true,
            .reverse = false,
        },
        "Hello, World!\n",
        .magenta,
        terminal.format("Hello, {s}!\n", .{haze}),
        .reset,
        "Hello, World!\n",
    });
}
