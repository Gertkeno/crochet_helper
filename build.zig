const Builder = @import("std").build.Builder;
const SDL2 = @import("lib/SDL.zig/Sdk.zig");

pub fn build(b: *Builder) void {
    const sdl2sdk = SDL2.init(b);
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("crochet_helper", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("date", "lib/zig-time/time.zig");

    sdl2sdk.link(exe, .dynamic);
    exe.addPackage(sdl2sdk.getNativePackage("sdl2"));
    exe.linkSystemLibrary("sdl2_image");

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
