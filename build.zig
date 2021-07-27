const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();

    const tests = b.addExecutable("test", "tests/main.zig");
    tests.addPackagePath("zig-terminal", "src/main.zig");
    tests.setBuildMode(mode);

    const run_tests = tests.run();

    const tests_step = b.step("test", "Run library tests");
    tests_step.dependOn(&run_tests.step);
}
