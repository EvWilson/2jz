const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    const bench = b.addExecutable("benchmark", "bench.zig");
    bench.setTarget(target);
    bench.setBuildMode(mode);
    bench.addPackagePath("ecs", "../src/world.zig");
    bench.install();

    const run_bench = bench.run();
    run_bench.step.dependOn(b.getInstallStep());

    const run_step = b.step("bench", "Run the benchmark");
    run_step.dependOn(&run_bench.step);
}
