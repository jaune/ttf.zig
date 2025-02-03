const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-ttf",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_step = b.step("run_all", "Run the app");

    const font_paths = [_][]const u8{
        "./fonts/Roboto/static/Roboto-Regular.ttf",
        "./fonts/Inter/static/Inter_18pt-Regular.ttf",
    };

    for (font_paths) |font_path| {
        const run_cmd = b.addRunArtifact(exe);

        run_cmd.step.dependOn(b.getInstallStep());

        run_cmd.addArg(font_path);

        run_cmd.addArg(try std.fmt.allocPrint(b.allocator, "./out/{s}.svg", .{std.fs.path.basename(font_path)}));

        run_step.dependOn(&run_cmd.step);
    }
}
