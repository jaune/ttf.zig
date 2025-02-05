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

    try svg.writeAll("<svg width=\"1000\" height=\"1000\" xmlns=\"http://www.w3.org/2000/svg\">\n");

    const unitsPerEm_f32: f32 = @as(f32, @floatFromInt(font.head.unitsPerEm)) / 300.0;

    var pen: f32 = 0;

    for (glyph_indices) |glyph_index| {
        const metrics = try font.getHorizontalMetricsFromGlyphIndex(glyph_index);
        const geometry = try font.getGeometryFromGlyphIndex(glyph_index);

        switch (geometry) {
            .contours => |contours| {
                // pen -= @as(f32, @floatFromInt(metrics.lsb));

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
                    "<g transform=\"translate({d:.5}, {d:.5}) \">\n",
                    .{
                        x / unitsPerEm_f32,
                        250 + (-1 * y / unitsPerEm_f32),
                    },
                ));

                var start: u16 = 0;

                // var p_x: i16 = 0;
                // var p_y: i16 = 0;

                var was_on_curve: bool = false;

                var path_x: i16 = 0;
                var path_y: i16 = 0;

                var start_x: i16 = 0;
                var start_y: i16 = 0;

                for (contours.end_indices) |end| {
                    try svg.writeAll("<path d=\"");

                    for (start..(end + 1)) |pi| {
                        const p0 = contours.points[pi];

                        if (pi == start) {
                            path_x += p0.x;
                            path_y += p0.y;

                            try svg.writeAll(try std.fmt.bufPrint(
                                &svg_buffer,
                                "M{d:.5} {d:.5} ",
                                .{
                                    @as(f32, @floatFromInt(path_x)) / unitsPerEm_f32,
                                    @as(f32, @floatFromInt(path_y)) / unitsPerEm_f32,
                                },
                            ));

                            start_x = path_x;
                            start_y = path_y;
                            was_on_curve = p0.on_curve;
                        } else {
                            if (was_on_curve and p0.on_curve) {
                                path_x += p0.x;
                                path_y += p0.y;

                                try svg.writeAll(try std.fmt.bufPrint(
                                    &svg_buffer,
                                    "L{d:.5} {d:.5} ",
                                    .{
                                        @as(f32, @floatFromInt(path_x)) / unitsPerEm_f32,
                                        @as(f32, @floatFromInt(path_y)) / unitsPerEm_f32,
                                    },
                                ));
                                was_on_curve = true;
                            } else if (!was_on_curve and p0.on_curve) {
                                try svg.writeAll(try std.fmt.bufPrint(
                                    &svg_buffer,
                                    "Q{d:.5} {d:.5} {d:.5} {d:.5} ",
                                    .{
                                        @as(f32, @floatFromInt(path_x)) / unitsPerEm_f32,
                                        @as(f32, @floatFromInt(path_y)) / unitsPerEm_f32,
                                        @as(f32, @floatFromInt(path_x + p0.x)) / unitsPerEm_f32,
                                        @as(f32, @floatFromInt(path_y + p0.y)) / unitsPerEm_f32,
                                    },
                                ));

                                path_x += p0.x;
                                path_y += p0.y;
                                was_on_curve = true;
                            } else if (!was_on_curve and !p0.on_curve) {
                                const virtual_x: i16 = path_x + @divFloor(p0.x, 2);
                                const virtual_y: i16 = path_y + @divFloor(p0.y, 2);

                                try svg.writeAll(try std.fmt.bufPrint(
                                    &svg_buffer,
                                    "Q{d:.5} {d:.5} {d:.5} {d:.5} ",
                                    .{
                                        @as(f32, @floatFromInt(path_x)) / unitsPerEm_f32,
                                        @as(f32, @floatFromInt(path_y)) / unitsPerEm_f32,
                                        @as(f32, @floatFromInt(virtual_x)) / unitsPerEm_f32,
                                        @as(f32, @floatFromInt(virtual_y)) / unitsPerEm_f32,
                                    },
                                ));

                                path_x += p0.x;
                                path_y += p0.y;
                                was_on_curve = false;
                            } else {
                                path_x += p0.x;
                                path_y += p0.y;
                                was_on_curve = false;
                            }
                        }

                        if (end == pi and !p0.on_curve) {
                            try svg.writeAll(try std.fmt.bufPrint(
                                &svg_buffer,
                                "Q{d:.5} {d:.5} {d:.5} {d:.5} ",
                                .{
                                    @as(f32, @floatFromInt(path_x)) / unitsPerEm_f32,
                                    @as(f32, @floatFromInt(path_y)) / unitsPerEm_f32,
                                    @as(f32, @floatFromInt(start_x)) / unitsPerEm_f32,
                                    @as(f32, @floatFromInt(start_y)) / unitsPerEm_f32,
                                },
                            ));
                        }
                    }

                    try svg.writeAll("z\" ");

                    try svg.writeAll("fill=\"black\"  />\n");

                    // for (start..(end + 1)) |pi| {
                    //     const p = contours.points[pi];
                    //     p_x += p.x;
                    //     p_y += p.y;

                    //     if (pi != start) {
                    //         const previous_p = contours.points[pi - 1];

                    //         if (!previous_p.on_curve and !p.on_curve) {
                    //             try svg.writeAll(try std.fmt.bufPrint(
                    //                 &svg_buffer,
                    //                 "<circle cx=\"{d:.5}\" cy=\"{d:.5}\" r=\"4\" {s} />\n",
                    //                 .{
                    //                     @as(f32, @floatFromInt(p_x - @divFloor(p.x, 2))) / unitsPerEm_f32,
                    //                     @as(f32, @floatFromInt(p_y - @divFloor(p.y, 2))) / unitsPerEm_f32,
                    //                     "fill=\"#0f0\"",
                    //                 },
                    //             ));
                    //         }
                    //     }

                    //     try svg.writeAll(try std.fmt.bufPrint(
                    //         &svg_buffer,
                    //         "<circle cx=\"{d:.5}\" cy=\"{d:.5}\" r=\"4\" {s} flags=\"x={},y={}\" />\n",
                    //         .{
                    //             @as(f32, @floatFromInt(p_x)) / unitsPerEm_f32,
                    //             @as(f32, @floatFromInt(p_y)) / unitsPerEm_f32,
                    //             if (p.on_curve) "fill=\"#f0f\"" else "fill=\"#f00\"",
                    //             p.flags.x_kind,
                    //             p.flags.y_kind,
                    //         },
                    //     ));
                    // }

                    start = end + 1;
                }

                try svg.writeAll("</g>\n");

                try svg.writeAll(try std.fmt.bufPrint(
                    &svg_buffer,
                    "<rect x=\"{d:.5}\" y=\"{d:.5}\" width=\"{d:.5}\" height=\"{d:.5}\" fill=\"#FF00FF22\" />\n",
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
