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

    const exe = b.addExecutable("crochet_helper", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("date", "lib/zig-time/time.zig");

    exe.linkLibC();
    if (target.toTarget().os.tag == .windows) {
        const wsdl2 = "SDL2-2.0.14/x86_64-w64-mingw32/";
        exe.addIncludeDir(wsdl2 ++ "include");

        exe.addLibPath(wsdl2 ++ "bin");
        exe.addObjectFile(wsdl2 ++ "lib/libSDL2.dll.a");
        exe.addObjectFile(wsdl2 ++ "lib/libSDL2main.a");
        exe.addObjectFile(wsdl2 ++ "lib/libSDL2_image.dll.a");
    } else {
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("SDL2_image");
    }

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
