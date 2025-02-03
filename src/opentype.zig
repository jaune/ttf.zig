const std = @import("std");

const Reader = std.io.BufferedReader(4096, std.fs.File.Reader).Reader;
const FixedBufferReader = std.io.FixedBufferStream([]const u8).Reader;
const FixedBufferReaderNotConst = std.io.FixedBufferStream([]u8).Reader;

// ISO/IEC 14496-22:2019(E) -- 4.3 Data types
const endian = std.builtin.Endian.big;

// ISO/IEC 14496-22:2019(E) -- 4.5.1 Offset table
const OffsetTableHeader = struct {
    sfnt_version: SfntVersion,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
};

fn readOffsetTableHeader(reader: *Reader) !OffsetTableHeader {
    const sfnt_version_raw = try reader.readInt(u32, endian);

    // ISO/IEC 14496-22:2019(E) -- 4.5.1 Offset table
    const sfnt_version: SfntVersion = switch (sfnt_version_raw) {
        0x00010000 => .tt,
        0x4F54544F => .cff,
        else => {
            return error.UnsupportedSfntVersion;
        },
    };

    return .{
        .sfnt_version = sfnt_version,
        .num_tables = try reader.readInt(u16, endian),
        .search_range = try reader.readInt(u16, endian),
        .entry_selector = try reader.readInt(u16, endian),
        .range_shift = try reader.readInt(u16, endian),
    };
}

const SfntVersion = enum {
    tt,
    cff,
};

// ISO/IEC 14496-22:2019(E) -- 4.3 Data types
const Tag = [4]u8;

fn readTag(reader: *Reader) !Tag {
    return .{
        try reader.readInt(u8, endian),
        try reader.readInt(u8, endian),
        try reader.readInt(u8, endian),
        try reader.readInt(u8, endian),
    };
}

// ISO/IEC 14496-22:2019(E) -- 4.5.2 Table directory
const OffsetTableRecord = struct {
    table_tag: Tag,
    checksum: u32,
    offset: u32,
    length: u32,
};

fn readTableRecord(reader: *Reader) !OffsetTableRecord {
    return .{
        .table_tag = try readTag(reader),
        .checksum = try reader.readInt(u32, endian),
        .offset = try reader.readInt(u32, endian),
        .length = try reader.readInt(u32, endian),
    };
}

// ISO/IEC 14496-22:2019(E) -- 4.6.3 TTC header
const TTCHeader = struct {
    ttc_tag: Tag,
    major_version: u16,
    minor_version: u16,
    num_fonts: u32,
    offset_table: []u32,
    signature: ?struct {
        offset: u32,
        length: u32,
    },
};

const MandatoryOffsetTableRecords = struct {
    loca: OffsetTableRecord,
    glyf: OffsetTableRecord,
    maxp: OffsetTableRecord,
    head: OffsetTableRecord,
    cmap: OffsetTableRecord,
    hhea: OffsetTableRecord,
    hmtx: OffsetTableRecord,
};

pub fn readMandatoryOffsetTableRecords(file: std.fs.File) !MandatoryOffsetTableRecords {
    try file.seekTo(0);
    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    const ot = try readOffsetTableHeader(&reader);

    // std.log.debug("\nOffsetTable\n sfnt_version {}\n num_tables: {}\n search_range: {}\n entry_selector: {}\n range_shift: {}\n", .{
    //     ot.sfnt_version,
    //     ot.num_tables,
    //     ot.search_range,
    //     ot.entry_selector,
    //     ot.range_shift,
    // });

    if (ot.sfnt_version != .tt) {
        return error.OnlyTrueTypeSupported;
    }

    var maybe_glyf_table: ?OffsetTableRecord = null;
    var maybe_loca_table: ?OffsetTableRecord = null;
    var maybe_maxp_table: ?OffsetTableRecord = null;
    var maybe_head_table: ?OffsetTableRecord = null;
    var maybe_cmap_table: ?OffsetTableRecord = null;
    var maybe_hhea_table: ?OffsetTableRecord = null;
    var maybe_hmtx_table: ?OffsetTableRecord = null;

    var table_index: u16 = 0;

    while (table_index < ot.num_tables) {
        const table_record = try readTableRecord(&reader);

        // std.log.debug("{s}", .{table_record.table_tag});

        if (std.mem.eql(u8, "glyf", &table_record.table_tag)) {
            maybe_glyf_table = table_record;
        } else if (std.mem.eql(u8, "loca", &table_record.table_tag)) {
            maybe_loca_table = table_record;
        } else if (std.mem.eql(u8, "maxp", &table_record.table_tag)) {
            maybe_maxp_table = table_record;
        } else if (std.mem.eql(u8, "head", &table_record.table_tag)) {
            maybe_head_table = table_record;
        } else if (std.mem.eql(u8, "cmap", &table_record.table_tag)) {
            maybe_cmap_table = table_record;
        } else if (std.mem.eql(u8, "hhea", &table_record.table_tag)) {
            maybe_hhea_table = table_record;
        } else if (std.mem.eql(u8, "hmtx", &table_record.table_tag)) {
            maybe_hmtx_table = table_record;
        }

        table_index += 1;
    }

    return .{
        .loca = if (maybe_loca_table) |t| t else {
            return error.MissingLocaTable;
        },
        .glyf = if (maybe_glyf_table) |t| t else {
            return error.MissingGlyfTable;
        },
        .maxp = if (maybe_maxp_table) |t| t else {
            return error.MissingMaxpTable;
        },
        .head = if (maybe_head_table) |t| t else {
            return error.MissingHeadTable;
        },
        .cmap = if (maybe_cmap_table) |t| t else {
            return error.MissingCmapTable;
        },
        .hhea = if (maybe_hhea_table) |t| t else {
            return error.MissingHheaTable;
        },
        .hmtx = if (maybe_hmtx_table) |t| t else {
            return error.MissingHmtxTable;
        },
    };
}

// fn computeTableChecksum(uint32 *Table, length: u32 ) u32 {
//     var checksum: u32 = 0;

// // uint32 *Endptr = Table+((Length+3) & ~3) / sizeof(uint32);
// // while (Table < EndPtr)
// //  Sum += *Table++;

//     return checksum;
// }

const Version16Dot16 = struct {
    major: i16,
    minor: i16,
};

fn readVersion16Dot16(reader: FixedBufferReader) !Version16Dot16 {
    return .{
        .major = try reader.readInt(i16, endian),
        .minor = try reader.readInt(i16, endian),
    };
}

const MaximumProfileTable = struct {
    version: Version16Dot16,
    num_glyphs: u16,
};

const maximum_profile_table_size: usize = 32;

fn readMaximumProfileTable(file: std.fs.File, offset: OffsetTableRecord) !MaximumProfileTable {
    if (offset.length != maximum_profile_table_size) {
        std.log.debug("readHeadTable: InvalidHeadTableSize: given = {}, expected = {}", .{ offset.length, head_table_expected_length });
        return error.InvalidHeadTableSize;
    }

    var buffer: [maximum_profile_table_size]u8 = undefined;

    try file.seekTo(offset.offset);
    _ = try file.read(&buffer);

    var steam = std.io.FixedBufferStream([]const u8){ .buffer = &buffer, .pos = 0 };
    const reader = steam.reader();

    const version = try readVersion16Dot16(reader);

    if (version.major == 0 or version.major == 5) {
        // std.log.debug("maxp: version: 0.5", .{});
    } else if (version.major == 1 or version.major == 0) {
        // std.log.debug("maxp: version: 1.0", .{});
    } else {
        return error.UnsupportedMaxpTableVersion;
    }

    const num_glyphs = try reader.readInt(u16, endian);

    return .{
        .version = version,
        .num_glyphs = num_glyphs,
    };
}

const Fixed = struct {
    major: i16,
    minor: i16,
};

fn readFixed(reader: FixedBufferReader) !Fixed {
    return .{
        .major = try reader.readInt(i16, endian),
        .minor = try reader.readInt(i16, endian),
    };
}

const LongDateTime = struct {
    value: i64,
};

fn readLongDateTime(reader: FixedBufferReader) !LongDateTime {
    return .{
        .value = try reader.readInt(i64, endian),
    };
}

const HorizontalHeaderTable = struct {
    numberOfHMetrics: u16,
};

const horizontal_header_table_size: usize = 36;

fn readHorizontalHeaderTable(file: std.fs.File, offset: OffsetTableRecord) !HorizontalHeaderTable {
    if (offset.length != horizontal_header_table_size) {
        std.log.debug("readHorizontalHeaderTable: InvalidHeadTableSize: given = {}, expected = {}", .{ offset.length, horizontal_header_table_size });
        return error.InvalidHorizontalHeaderTableSize;
    }

    var buffer: [horizontal_header_table_size]u8 = undefined;

    try file.seekTo(offset.offset);
    _ = try file.read(&buffer);

    var steam = std.io.FixedBufferStream([]const u8){ .buffer = &buffer, .pos = 0 };
    const reader = steam.reader();

    const majorVersion = try reader.readInt(u16, endian); //Major version number of the horizontal header table — set to 1.
    const minorVersion = try reader.readInt(u16, endian); //Minor version number of the horizontal header table — set to 0.
    const ascender = try reader.readInt(i16, endian); //Typographic ascent—see remarks below.
    const descender = try reader.readInt(i16, endian); //Typographic descent—see remarks below.
    const lineGap = try reader.readInt(i16, endian); //Typographic line gap. Negative lineGap values are treated as zero in some legacy platform implementations.
    const advance_widthMax = try reader.readInt(u16, endian); //Maximum advance width value in 'hmtx' table.
    const minLeftSideBearing = try reader.readInt(i16, endian); //Minimum left sidebearing value in 'hmtx' table for glyphs with contours (empty glyphs should be ignored).
    const minRightSideBearing = try reader.readInt(i16, endian); //Minimum right sidebearing value; calculated as min(aw - (lsb + xMax - xMin)) for glyphs with contours (empty glyphs should be ignored).
    const xMaxExtent = try reader.readInt(i16, endian); //Max(lsb + (xMax - xMin)).
    const caretSlopeRise = try reader.readInt(i16, endian); //Used to calculate the slope of the cursor (rise/run); 1 for vertical.
    const caretSlopeRun = try reader.readInt(i16, endian); //0 for vertical.
    const caretOffset = try reader.readInt(i16, endian); //The amount by which a slanted highlight on a glyph needs to be shifted to produce the best appearance. Set to 0 for non-slanted fonts
    _ = try reader.readInt(i16, endian);
    _ = try reader.readInt(i16, endian);
    _ = try reader.readInt(i16, endian);
    _ = try reader.readInt(i16, endian);

    const metricDataFormat = try reader.readInt(i16, endian); //0 for current format.
    const numberOfHMetrics = try reader.readInt(u16, endian); //Number of hMetric entries in 'hmtx' table

    _ = majorVersion;
    _ = minorVersion;
    _ = ascender;
    _ = descender;
    _ = lineGap;
    _ = advance_widthMax;
    _ = minLeftSideBearing;
    _ = minRightSideBearing;
    _ = xMaxExtent;
    _ = caretSlopeRise;
    _ = caretSlopeRun;
    _ = caretOffset;
    _ = metricDataFormat;

    return .{
        .numberOfHMetrics = numberOfHMetrics,
    };
}

const HorizontalMetrics = struct {
    advance_width: u16,
    lsb: i16,
};

const ReadAndAllocHorizontalMetricsOptions = struct {
    numberOfHMetrics: u16,
    num_glyphs: u16,
};

fn readAndAllocHorizontalMetrics(allocator: std.mem.Allocator, file: std.fs.File, offset: OffsetTableRecord, options: ReadAndAllocHorizontalMetricsOptions) ![]HorizontalMetrics {
    const expected_length = (options.numberOfHMetrics * 4) + ((options.num_glyphs - options.numberOfHMetrics) * 2);

    if (offset.length != expected_length) {
        std.log.err("readHorizontalMetricsTable: given = {}, expected = {}", .{ offset.length, expected_length });
        return error.InvalidHorizontalMetricsTableSize;
    }

    const buffer = try allocator.alloc(u8, expected_length);
    defer allocator.free(buffer);

    try file.seekTo(offset.offset);
    _ = try file.read(buffer);

    var steam = std.io.FixedBufferStream([]const u8){ .buffer = buffer, .pos = 0 };
    const reader = steam.reader();

    const metrics = try allocator.alloc(HorizontalMetrics, options.num_glyphs);
    errdefer allocator.free(metrics);

    for (metrics, 0..) |*m, glyph_index| {
        m.advance_width = if (glyph_index < options.numberOfHMetrics)
            try reader.readInt(u16, endian)
        else
            0;
        m.lsb = try reader.readInt(i16, endian);
    }

    return metrics;
}

pub const IndexToLocationFormat = enum {
    offset_16,
    offset_32,
};

const HeadTable = struct {
    unitsPerEm: u16,
    xMin: i16,
    yMin: i16,
    xMax: i16,
    yMax: i16,

    loca_format: IndexToLocationFormat, // 0 for short offsets (Offset16), 1 for long (Offset32).

};

const head_table_expected_length: usize = 54;

fn readHeadTable(file: std.fs.File, offset: OffsetTableRecord) !HeadTable {
    if (offset.length != head_table_expected_length) {
        std.log.debug("readHeadTable: InvalidHeadTableSize: given = {}, expected = {}", .{ offset.length, head_table_expected_length });
        return error.InvalidHeadTableSize;
    }

    var buffer: [head_table_expected_length]u8 = undefined;

    try file.seekTo(offset.offset);
    _ = try file.read(&buffer);

    var steam = std.io.FixedBufferStream([]const u8){ .buffer = &buffer, .pos = 0 };
    const reader = steam.reader();

    const majorVersion = try reader.readInt(u16, endian);
    const minorVersion = try reader.readInt(u16, endian);
    const fontRevision = try readFixed(reader);
    const checksumAdjustment = try reader.readInt(u32, endian);
    const magicNumber = try reader.readInt(u32, endian);
    const flags = try reader.readInt(u16, endian);
    const unitsPerEm = try reader.readInt(u16, endian);
    const created = try readLongDateTime(reader);
    const modified = try readLongDateTime(reader);
    const xMin = try reader.readInt(i16, endian);
    const yMin = try reader.readInt(i16, endian);
    const xMax = try reader.readInt(i16, endian);
    const yMax = try reader.readInt(i16, endian);
    const macStyle = try reader.readInt(u16, endian);
    const lowestRecPPEM = try reader.readInt(u16, endian);
    const fontDirectionHint = try reader.readInt(i16, endian);
    const indexToLocFormat = try reader.readInt(i16, endian);
    const glyphDataFormat = try reader.readInt(i16, endian);

    _ = majorVersion;
    _ = minorVersion;
    _ = fontRevision;
    _ = checksumAdjustment;
    _ = magicNumber;
    _ = flags;
    _ = created;
    _ = modified;
    _ = macStyle;
    _ = lowestRecPPEM;
    _ = fontDirectionHint;
    _ = glyphDataFormat;

    return .{
        .xMin = xMin,
        .yMin = yMin,
        .xMax = xMax,
        .yMax = yMax,

        .unitsPerEm = unitsPerEm,

        .loca_format = switch (indexToLocFormat) {
            0 => .offset_16,
            1 => .offset_32,
            else => {
                return error.UnsupportedIndexToLocFormat;
            },
        },
    };
}

const ReadAndAllocGlyphOffsetsOptions = struct {
    num_glyphs: u16,
    loca_format: IndexToLocationFormat,
};

fn readAndAllocGlyphOffsets(allocator: std.mem.Allocator, file: std.fs.File, offset: OffsetTableRecord, options: ReadAndAllocGlyphOffsetsOptions) ![]u32 {
    const loca_table_size: usize = switch (options.loca_format) {
        .offset_16 => (options.num_glyphs + 1) * 2,
        .offset_32 => (options.num_glyphs + 1) * 4,
    };

    if (offset.length != loca_table_size) {
        std.log.debug("readHeadTable: InvalidHeadTableSize: given = {}, expected = {}", .{ offset.length, loca_table_size });
        return error.InvalidHeadTableSize;
    }

    const buffer: []u8 = try allocator.alloc(u8, offset.length);
    defer allocator.free(buffer);

    try file.seekTo(offset.offset);
    _ = try file.read(buffer);

    var steam = std.io.FixedBufferStream([]const u8){ .buffer = buffer, .pos = 0 };
    const reader = steam.reader();

    const glyph_offsets: []u32 = try allocator.alloc(u32, options.num_glyphs + 1);
    errdefer allocator.free(glyph_offsets);

    switch (options.loca_format) {
        .offset_16 => {
            for (glyph_offsets) |*glyph_offset| {
                glyph_offset.* = @as(u32, try reader.readInt(u16, endian)) * 2;
            }
        },
        .offset_32 => {
            for (glyph_offsets) |*glyph_offset| {
                glyph_offset.* = try reader.readInt(u32, endian);
            }
        },
    }

    return glyph_offsets;
}

const GlyphPoint = struct {
    x: i16,
    y: i16,
};

const GlyphTableRecordContours = struct {
    xMin: i16,
    yMin: i16,
    xMax: i16,
    yMax: i16,

    end_indices: []u16,
    points: []GlyphPoint,
};

const GlyphTableRecordComposite = struct {
    xMin: i16,
    yMin: i16,
    xMax: i16,
    yMax: i16,
};

const GlyphTableRecord = union(enum) {
    empty: void,
    contours: GlyphTableRecordContours,
    composite: GlyphTableRecordComposite,
};

const GlyphTable = struct {
    area: std.heap.ArenaAllocator,

    records: []GlyphTableRecord,

    pub fn deinit(self: @This()) void {
        self.area.deinit();
    }

    pub const InitFromFileOptions = struct {
        glyph_offsets: []u32,
    };

    fn readRecord(allocator: std.mem.Allocator, reader: FixedBufferReaderNotConst) !GlyphTableRecord {
        const numberOfContours = try reader.readInt(i16, endian);

        const xMin = try reader.readInt(i16, endian);
        const yMin = try reader.readInt(i16, endian);
        const xMax = try reader.readInt(i16, endian);
        const yMax = try reader.readInt(i16, endian);

        var instructionLength: u16 = 0;

        if (numberOfContours < 0) {
            return .{
                .composite = .{
                    .xMin = xMin,
                    .yMin = yMin,
                    .xMax = xMax,
                    .yMax = yMax,
                },
            };
        }

        const end_indices = try allocator.alloc(u16, @intCast(numberOfContours));
        errdefer allocator.free(end_indices);

        var glyph_points_size: usize = 0;

        for (end_indices) |*end_index| {
            const v = try reader.readInt(u16, endian);
            end_index.* = v;
            glyph_points_size = v + 1;
        }

        if (glyph_points_size == 0) {
            return error.NoPoint;
        }

        instructionLength = try reader.readInt(u16, endian);

        try reader.skipBytes(instructionLength, .{});

        const GlyphCoordKind = enum(u2) {
            short_vector_positive,
            short_vector_negative,
            long_vector,
            is_same,
        };

        const GlyphFlags = struct {
            on_curve_point: bool,
            overlap_simple: bool,
            x_kind: GlyphCoordKind,
            y_kind: GlyphCoordKind,

            fn initFromInt(v: u8) @This() {
                return .{
                    .on_curve_point = v & 0x01 == 0x01,
                    .overlap_simple = v & 0x40 == 0x40,
                    .x_kind = switch (v & (0x02 | 0x10)) {
                        0x02 | 0x10 => .short_vector_positive,
                        0x02 => .short_vector_negative,
                        0x10 => .is_same,
                        else => .long_vector,
                    },
                    .y_kind = switch (v & (0x04 | 0x20)) {
                        0x04 | 0x20 => .short_vector_positive,
                        0x04 => .short_vector_negative,
                        0x20 => .is_same,
                        else => .long_vector,
                    },
                };
            }
        };

        const glyph_points = try allocator.alloc(GlyphPoint, glyph_points_size);
        errdefer allocator.free(glyph_points);

        const glyph_flags = try allocator.alloc(GlyphFlags, glyph_points_size);
        defer allocator.free(glyph_flags);

        var glyph_flags_index: usize = 0;

        while (glyph_flags_index < glyph_points_size) {
            const flags = try reader.readInt(u8, endian);
            const f = GlyphFlags.initFromInt(flags);
            const repeat: usize = if (flags & 0x08 == 0x08) @as(usize, @intCast(try reader.readInt(u8, endian))) + 1 else 1;

            for (0..repeat) |_| {
                glyph_flags[glyph_flags_index] = f;
                glyph_flags_index += 1;
            }
        }

        if (glyph_flags_index != glyph_points_size) {
            return error.GlyphHasMissingFlags;
        }

        var last_coord: i16 = 0;

        for (glyph_flags, glyph_points) |f, *p| {
            p.x = switch (f.x_kind) {
                .is_same => last_coord,
                .long_vector => try reader.readInt(i16, endian),
                .short_vector_negative => -@as(i16, @intCast(try reader.readInt(u8, endian))),
                .short_vector_positive => @intCast(try reader.readInt(u8, endian)),
            };
            last_coord = p.x;
        }

        last_coord = 0;

        for (glyph_flags, glyph_points) |f, *p| {
            p.y = switch (f.y_kind) {
                .is_same => last_coord,
                .long_vector => try reader.readInt(i16, endian),
                .short_vector_negative => -@as(i16, @intCast(try reader.readInt(u8, endian))),
                .short_vector_positive => @intCast(try reader.readInt(u8, endian)),
            };
            last_coord = p.y;
        }

        return .{
            .contours = .{
                .xMin = xMin,
                .yMin = yMin,
                .xMax = xMax,
                .yMax = yMax,
                .end_indices = end_indices,
                .points = glyph_points,
            },
        };
    }

    pub fn initFromFile(allocator: std.mem.Allocator, file: std.fs.File, offset: OffsetTableRecord, options: InitFromFileOptions) !@This() {
        if (options.glyph_offsets.len <= 1) {
            std.log.err("options.glyph_offsets.len > 1 {}", .{options.glyph_offsets.len > 1});
            return error.ZeroGlyph;
        }

        const buffer: []u8 = try allocator.alloc(u8, offset.length);
        defer allocator.free(buffer);

        try file.seekTo(offset.offset);
        _ = try file.read(buffer);

        var area = std.heap.ArenaAllocator.init(allocator);
        errdefer area.deinit();
        const area_allocator = area.allocator();

        const records = try area_allocator.alloc(GlyphTableRecord, options.glyph_offsets.len - 1);

        for (records, 0..) |*record, glyph_index| {
            const start = options.glyph_offsets[glyph_index];
            const end = options.glyph_offsets[glyph_index + 1];

            if (start == end) {
                record.* = .empty;
            } else if (start > end) {
                return error.StartAfterEnd;
            } else {
                var stream = std.io.fixedBufferStream(buffer[start..end]);
                const reader = stream.reader();

                const r = try readRecord(
                    area_allocator,
                    reader,
                );

                const cursor = try stream.getPos();

                if ((start + cursor) != end) {
                    // TODO: handle compisite
                    // std.log.warn("glyph_index: {}: cursor != end: cursor={} end={}", .{ glyph_index, (start + cursor), end });
                }

                record.* = r;
            }
        }

        return .{
            .area = area,
            .records = records,
        };
    }
};

pub const Font = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    head: HeadTable,

    horizontal_metrics: []HorizontalMetrics,
    geometries: GlyphTable,
    mapping: CharacterToGlyphIndexMappingTable,

    pub fn getHorizontalMetricsFromGlyphIndex(self: *const Self, index: u16) !HorizontalMetrics {
        return self.horizontal_metrics[index];
    }

    pub fn getGlyphIndexFromCodepoint(self: *const Self, codepoint: u21) !u16 {
        return self.mapping.getGlyphIndexFromCodepoint(codepoint);
    }

    pub fn getGlyphIndicesFromCodepoints(self: *const Self, codepoints: []const u21, indices: []u16) !void {
        return self.mapping.getGlyphIndicesFromCodepoints(codepoints, indices);
    }

    pub fn getGeometryFromGlyphIndex(self: *const Self, index: u16) !GlyphTableRecord {
        return self.geometries.records[index];
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.horizontal_metrics);
        self.geometries.deinit();
        self.mapping.deinit();
    }
};

pub fn read(allocator: std.mem.Allocator, path: []const u8) !Font {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const offset_tables = try readMandatoryOffsetTableRecords(file);

    const head = try readHeadTable(file, offset_tables.head);
    const maxp = try readMaximumProfileTable(file, offset_tables.maxp);
    const hhea = try readHorizontalHeaderTable(file, offset_tables.hhea);

    if (maxp.num_glyphs == 0) {
        return error.ZeroGlyph;
    }

    const glyph_offsets = try readAndAllocGlyphOffsets(allocator, file, offset_tables.loca, .{
        .num_glyphs = maxp.num_glyphs,
        .loca_format = head.loca_format,
    });
    defer allocator.free(glyph_offsets);

    const horizontal_metrics = try readAndAllocHorizontalMetrics(allocator, file, offset_tables.hmtx, .{
        .numberOfHMetrics = hhea.numberOfHMetrics,
        .num_glyphs = maxp.num_glyphs,
    });
    errdefer allocator.free(horizontal_metrics);

    const cmap_headers = try readAndAllocCharacterToGlyphIndexMappingTableHeaders(allocator, file, offset_tables.cmap);
    defer allocator.free(cmap_headers);

    var maybe_unicode_cmap_header: ?CharacterToGlyphIndexMappingTableHeader = null;

    for (cmap_headers) |cmap_header| {
        if (cmap_header.platform_id == 0 and cmap_header.format != .unsupported) {
            maybe_unicode_cmap_header = cmap_header;
        }
    }

    const unicode_cmap_header = if (maybe_unicode_cmap_header) |h| h else {
        return error.NoUnicodeMapping;
    };

    const geometries = try GlyphTable.initFromFile(
        allocator,
        file,
        offset_tables.glyf,
        .{
            .glyph_offsets = glyph_offsets,
        },
    );
    errdefer geometries.deinit();

    const mapping = try readAndAllocCharacterToGlyphIndexMappingTable(allocator, file, unicode_cmap_header);

    return .{
        .allocator = allocator,
        .head = head,
        .horizontal_metrics = horizontal_metrics,
        .geometries = geometries,
        .mapping = mapping,
    };
}

fn readAndAllocCharacterToGlyphIndexMappingTable(allocator: std.mem.Allocator, file: std.fs.File, header: CharacterToGlyphIndexMappingTableHeader) !CharacterToGlyphIndexMappingTable {
    switch (header.format) {
        .format_4 => {
            var cmap = try CharacterToGlyphIndexMappingFormat4Table.initFromFile(allocator, file, header);
            errdefer cmap.deinit();

            return CharacterToGlyphIndexMappingTable.init(allocator, @TypeOf(cmap), cmap);
        },
        .format_12 => {
            var cmap = try CharacterToGlyphIndexMappingFormat12Table.initFromFile(allocator, file, header);
            errdefer cmap.deinit();

            return CharacterToGlyphIndexMappingTable.init(allocator, @TypeOf(cmap), cmap);
        },
        else => {
            return error.UnsupportedMappingFormat;
        },
    }
}

const CharacterToGlyphIndexMappingTableHeader = struct {
    const Format = enum {
        unsupported,
        format_4,
        format_12,
    };

    platform_id: u16,
    encoding_id: u16,
    offset: u32,
    format: Format = .unsupported,
};

// fn CharacterToGlyphIndexMappingTableHeaderBoundedArray(num: usize) type {
//     return std.BoundedArray(CharacterToGlyphIndexMappingTableHeader, num);
// }

fn readAndAllocCharacterToGlyphIndexMappingTableHeaders(allocator: std.mem.Allocator, file: std.fs.File, offset: OffsetTableRecord) ![]CharacterToGlyphIndexMappingTableHeader {
    std.log.warn("TODO: CharacterToGlyphIndexMappingTableHeader check offset.length", .{});

    try file.seekTo(offset.offset);
    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    const version = try reader.readInt(u16, endian);

    if (version != 0) {
        return error.CmapInvalidVersion;
    }

    const numTables = try reader.readInt(u16, endian);
    const headers = try allocator.alloc(CharacterToGlyphIndexMappingTableHeader, numTables);
    errdefer allocator.free(headers);

    var i: u16 = 0;
    while (i < numTables) {
        const platform_id = try reader.readInt(u16, endian);
        const encoding_id = try reader.readInt(u16, endian);
        const subtable_offset = try reader.readInt(u32, endian);

        headers[i] = .{
            .platform_id = platform_id,
            .encoding_id = encoding_id,
            .offset = offset.offset + subtable_offset,
            .format = .unsupported,
        };

        i += 1;
    }

    for (headers) |*header| {
        header.format = try readCharacterToGlyphIndexMappingFormat(file, header.offset);
    }

    return headers;
}

fn readCharacterToGlyphIndexMappingFormat(file: std.fs.File, offset: u64) !CharacterToGlyphIndexMappingTableHeader.Format {
    try file.seekTo(offset);

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    const format = try reader.readInt(u16, endian);

    return switch (format) {
        4 => {
            return .format_4;
        },
        12 => {
            return .format_12;
        },
        else => {
            return .unsupported;
        },
    };
}

const CharacterToGlyphIndexMappingTable = struct {
    const Error = error{
        MissingGlyphIndex,
        OutOfBoundsGlyphIndex,
        SlicesSizeMismatch,
    };

    context: *const anyopaque,
    allocator: std.mem.Allocator,

    deinitFn: *const fn (self: *const @This()) void,
    getGlyphIndexFromCodepointFn: *const fn (self: *const @This(), codepoint: u21) Error!u16,
    getGlyphIndicesFromCodepointsFn: *const fn (self: *const @This(), codepoints: []const u21, indices: []u16) Error!void,

    pub inline fn getGlyphIndexFromCodepoint(self: *const @This(), codepoint: u21) Error!u16 {
        return self.getGlyphIndexFromCodepointFn(self, codepoint);
    }

    pub inline fn getGlyphIndicesFromCodepoints(self: *const @This(), codepoints: []const u21, indices: []u16) Error!void {
        return self.getGlyphIndicesFromCodepointsFn(self, codepoints, indices);
    }

    pub inline fn deinit(self: *const @This()) void {
        self.deinitFn(self);
    }

    pub fn init(allocator: std.mem.Allocator, comptime T: type, c: T) !CharacterToGlyphIndexMappingTable {
        const Functions = struct {
            fn getGlyphIndexFromCodepointFn(p: *const CharacterToGlyphIndexMappingTable, codepoint: u21) CharacterToGlyphIndexMappingTable.Error!u16 {
                const t: *const T = @ptrCast(@alignCast(p.context));

                return T.getGlyphIndexFromCodepoint(t, codepoint);
            }

            fn deinitFn(p: *const CharacterToGlyphIndexMappingTable) void {
                const t: *const T = @ptrCast(@alignCast(p.context));

                T.deinit(t);

                p.allocator.destroy(t);
            }

            fn getGlyphIndicesFromCodepointsFn(p: *const CharacterToGlyphIndexMappingTable, codepoints: []const u21, indices: []u16) CharacterToGlyphIndexMappingTable.Error!void {
                const t: *const T = @ptrCast(@alignCast(p.context));

                return T.getGlyphIndicesFromCodepoints(t, codepoints, indices);
            }
        };

        const context = try allocator.create(T);

        context.* = c;

        return .{
            .allocator = allocator,
            .context = context,
            .deinitFn = Functions.deinitFn,
            .getGlyphIndexFromCodepointFn = Functions.getGlyphIndexFromCodepointFn,
            .getGlyphIndicesFromCodepointsFn = Functions.getGlyphIndicesFromCodepointsFn,
        };
    }
};

const CharacterToGlyphIndexMappingFormat12Table = struct {
    const Segment = struct {
        startCharCode: u32,
        endCharCode: u32,
        startGlyphID: u32,
    };

    allocator: std.mem.Allocator,
    segments: []Segment,

    pub fn getGlyphIndexFromCodepoint(self: *const @This(), code: u21) CharacterToGlyphIndexMappingTable.Error!u16 {
        for (self.segments) |segment| {
            if (code >= segment.startCharCode and code <= segment.endCharCode) {
                return @intCast(segment.startGlyphID + (code - segment.startCharCode));
            }
        }
        return error.MissingGlyphIndex;
    }

    pub fn getGlyphIndicesFromCodepoints(self: *const @This(), codepoints: []const u21, indices: []u16) CharacterToGlyphIndexMappingTable.Error!void {
        if (codepoints.len != indices.len) {
            return error.SlicesSizeMismatch;
        }

        for (codepoints, indices) |codepoint, *index| {
            index.* = try self.getGlyphIndexFromCodepoint(codepoint);
        }
    }

    pub fn deinit(self: *const @This()) void {
        self.allocator.free(self.segments);
    }

    pub fn initFromFile(allocator: std.mem.Allocator, file: std.fs.File, header: CharacterToGlyphIndexMappingTableHeader) !CharacterToGlyphIndexMappingFormat12Table {
        if (header.format != .format_12) {
            return error.NotMatchingFormat;
        }

        try file.seekTo(header.offset);

        var buf_reader = std.io.bufferedReader(file.reader());
        var reader = buf_reader.reader();

        if (try reader.readInt(u16, endian) != 12) {
            return error.NotMatchingFormat;
        }

        if (try reader.readInt(u16, endian) != 0) {
            return error.InvalidFormatMissingreserved;
        }

        const length = try reader.readInt(u32, endian);
        const language = try reader.readInt(u32, endian);
        const numGroups = try reader.readInt(u32, endian);

        const expected_length = 4 + (3 * 4) + (numGroups * 3 * 4);

        if (expected_length != length) {
            std.log.err("InvalidLength: given = {}, expected = {}", .{ length, expected_length });
            return error.InvalidLength;
        }

        _ = language;

        const segments = try allocator.alloc(Segment, numGroups);
        errdefer allocator.free(segments);

        var i: u32 = 0;
        while (i < numGroups) {
            segments[i] = .{
                .startCharCode = try reader.readInt(u32, endian),
                .endCharCode = try reader.readInt(u32, endian),
                .startGlyphID = try reader.readInt(u32, endian),
            };
            i += 1;
        }

        return .{
            .allocator = allocator,
            .segments = segments,
        };
    }
};

const CharacterToGlyphIndexMappingFormat4Table = struct {
    const Segment = struct {
        startCode: u16,
        endCode: u16,
        idDelta: i16 = 0,
        idRangeOffset: u16 = 0,
        idRangeIndex: u16 = 0,
    };

    allocator: std.mem.Allocator,

    search_range: u16,
    entry_selector: u16,
    range_shift: u16,

    segments: []Segment,
    glyph_ids: []u16,

    pub fn getGlyphIndexFromCodepoint(self: *const @This(), code: u21) CharacterToGlyphIndexMappingTable.Error!u16 {
        const code_i32: i32 = @intCast(code);

        for (self.segments) |segment| {
            if (code >= segment.startCode and code <= segment.endCode) {
                if (segment.idRangeOffset == 0) {
                    var v = code_i32 + segment.idDelta;

                    if (v < 0) {
                        v += 65536;
                    }

                    return @intCast(v);
                } else {
                    const i = segment.idRangeIndex + (code - segment.startCode);

                    if (i >= self.glyph_ids.len) {
                        return error.OutOfBoundsGlyphIndex;
                    }

                    return self.glyph_ids[i];
                }
            }
        }
        return error.MissingGlyphIndex;
    }

    pub fn getGlyphIndicesFromCodepoints(self: *const @This(), codepoints: []const u21, indices: []u16) CharacterToGlyphIndexMappingTable.Error!void {
        if (codepoints.len != indices.len) {
            return error.SlicesSizeMismatch;
        }

        for (codepoints, indices) |codepoint, *index| {
            index.* = try self.getGlyphIndexFromCodepoint(codepoint);
        }
    }

    pub fn deinit(self: *const @This()) void {
        self.allocator.free(self.segments);
        self.allocator.free(self.glyph_ids);
    }

    pub fn initFromFile(allocator: std.mem.Allocator, file: std.fs.File, header: CharacterToGlyphIndexMappingTableHeader) !CharacterToGlyphIndexMappingFormat4Table {
        std.debug.assert(header.format == .format_4);

        try file.seekTo(header.offset);

        var buf_reader = std.io.bufferedReader(file.reader());
        var reader = buf_reader.reader();

        std.debug.assert(try reader.readInt(u16, endian) == 4);

        const length = try reader.readInt(u16, endian);
        const language = try reader.readInt(u16, endian);
        const segCountX2 = try reader.readInt(u16, endian);
        const file_search_range = try reader.readInt(u16, endian);
        const file_entry_selector = try reader.readInt(u16, endian);
        const file_range_shift = try reader.readInt(u16, endian);

        _ = language;

        const segCount = segCountX2 / 2;

        const sp2 = std.math.floorPowerOfTwo(u16, segCount);
        const comuputed_search_range = sp2 * 2;

        if (file_search_range != comuputed_search_range) {
            return error.InvalidSearchRange;
        }

        const comuputed_entry_selector = std.math.log2_int(u16, sp2);

        if (file_entry_selector != comuputed_entry_selector) {
            return error.InvalidEntrySelector;
        }

        const comuputed_range_shift = 2 * segCount - comuputed_search_range;

        if (file_range_shift != comuputed_range_shift) {
            return error.InvalidRangeShift;
        }

        const segments = try allocator.alloc(Segment, segCount);
        errdefer allocator.free(segments);

        for (segments) |*segment| {
            segment.endCode = try reader.readInt(u16, endian);
        }

        std.debug.assert(try reader.readInt(u16, endian) == 0); // reserved

        for (segments) |*segment| {
            segment.startCode = try reader.readInt(u16, endian);
        }

        for (segments) |*segment| {
            segment.idDelta = try reader.readInt(i16, endian);
        }

        var glyph_ids_size: usize = 0;
        var seg_index: u16 = 0;

        for (segments) |*segment| {
            const idRangeOffset = try reader.readInt(u16, endian);

            segment.idRangeOffset = idRangeOffset;

            if (idRangeOffset != 0) {
                glyph_ids_size += (segment.endCode - segment.startCode) + 1;
                segment.idRangeIndex = (idRangeOffset / 2) - (segCount - seg_index);
            }

            seg_index += 1;
        }

        const no_array_length: usize = 16 + (segCount * 8);
        const expected_length = no_array_length + (glyph_ids_size * 2);

        if (expected_length != length) {
            std.log.err("InvalidLength: given = {}, expected = {}", .{ length, expected_length });
            return error.InvalidLength;
        }

        const glyph_ids = try allocator.alloc(u16, glyph_ids_size);
        errdefer allocator.free(glyph_ids);

        for (glyph_ids) |*glyph_id| {
            glyph_id.* = try reader.readInt(u16, endian);
        }

        return .{
            .allocator = allocator,
            .search_range = comuputed_search_range,
            .entry_selector = comuputed_entry_selector,
            .range_shift = comuputed_range_shift,
            .segments = segments,
            .glyph_ids = glyph_ids,
        };
    }
};
