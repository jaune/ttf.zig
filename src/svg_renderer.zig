const std = @import("std");
const opentype = @import("./opentype.zig");

pub fn writeFile(font: *const opentype.Font, codepoints: []const u21, path: []const u8) !void {
    var glyph_indices_array = try std.BoundedArray(u16, 128).init(codepoints.len);

    const glyph_indices = glyph_indices_array.slice();

    try font.getGlyphIndicesFromCodepoints(codepoints, glyph_indices);

    const svg = try std.fs.cwd().createFile(
        path,
        .{ .read = false },
    );
    defer svg.close();

    var svg_buffer: [2048]u8 = undefined;

    try svg.writeAll("<svg width=\"500\" height=\"500\" xmlns=\"http://www.w3.org/2000/svg\">\n");

    const unitsPerEm_f32: f32 = @as(f32, @floatFromInt(font.head.unitsPerEm)) / 32.0;

    var pen: f32 = 0;

    for (glyph_indices) |glyph_index| {
        const metrics = try font.getHorizontalMetricsFromGlyphIndex(glyph_index);
        const geometry = try font.getGeometryFromGlyphIndex(glyph_index);

        switch (geometry) {
            .contours => |contours| {
                pen += @as(f32, @floatFromInt(metrics.lsb));

                const width: f32 = @floatFromInt(contours.xMax - contours.xMin);
                const height: f32 = @floatFromInt(contours.yMax - contours.yMin);
                const x: f32 = pen;
                const y: f32 = @as(f32, @floatFromInt(contours.yMax));

                if (metrics.advance_width == 0) {
                    pen += width;
                } else {
                    pen += @as(f32, @floatFromInt(metrics.advance_width));
                }

                // const rsb = @as(i16, @intCast(metrics.advance_width)) - (metrics.lsb + xMax - xMin);

                // pen -= @as(f32, @floatFromInt(rsb));

                try svg.writeAll(try std.fmt.bufPrint(
                    &svg_buffer,
                    "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" />\n",
                    .{
                        x / unitsPerEm_f32,
                        250 + (-1 * y / unitsPerEm_f32),
                        width / unitsPerEm_f32,
                        height / unitsPerEm_f32,
                    },
                ));
            },
            else => {},
        }
    }

    try svg.writeAll("</svg>\n");
}
