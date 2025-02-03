const std = @import("std");

const opentype = @import("./opentype.zig");
const svg_renderer = @import("./svg_renderer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip arg 0
    const font_path = args.next() orelse {
        return error.MissingArgument1;
    };
    const output_path = args.next() orelse {
        return error.MissingArgument2;
    };

    const font = try opentype.read(allocator, font_path);
    defer font.deinit();

    const max_length = 20;

    var wtf8 = (try std.unicode.Wtf8View.init("Hello world!")).iterator();

    var codepoints = try std.BoundedArray(u21, max_length).init(0);

    while (wtf8.nextCodepoint()) |codepoint| {
        try codepoints.append(codepoint);
    }

    try svg_renderer.writeFile(&font, codepoints.slice(), output_path);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
