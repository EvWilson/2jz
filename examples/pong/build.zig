const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const demo = b.addExecutable("pong", "main.zig");
    demo.setTarget(target);
    demo.setBuildMode(mode);
    demo.linkSystemLibrary("c");
    demo.linkSystemLibrary("sdl2");
    demo.addPackagePath("ecs", "../../src/world.zig");
    demo.install();

    const run_demo = demo.run();
    run_demo.step.dependOn(b.getInstallStep());

    const run_step = b.step("demo", "Run the demo");
    run_step.dependOn(&run_demo.step);
}
