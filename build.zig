const std = @import("std");
// const cimgui = @import("cimgui");
const shdc = @import("shdc");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opt_docking = b.option(bool, "docking", "Build with docking support") orelse false;

    // Get the matching Zig module name, C header search path and C library for
    // vanilla imgui vs the imgui docking branch.
    // const cimgui_conf = cimgui.getConfig(opt_docking);

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        //.with_sokol_imgui = true,
    });
    // const dep_cimgui = b.dependency("cimgui", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // inject the cimgui header search path into the sokol C library compile step
    // dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    const mod_main = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            //.{ .name = cimgui_conf.module_name, .module = dep_cimgui.module(cimgui_conf.module_name) },
        },
    });
    const mod_options = b.addOptions();
    mod_options.addOption(bool, "docking", opt_docking);
    mod_main.addOptions("build_options", mod_options);
    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    // extract shdc dependency from sokol dependency
    const dep_shdc = b.dependency("shdc", .{});

    // call shdc.createSourceFile() helper function, this returns a `!*Build.Step`:
    const shdc_step: *std.Build.Step = shdc.createSourceFile(b, .{
        .shdc_dep = dep_shdc,
        .input = "src/shaders/triangle.glsl",
        .output = "src/shaders/triangle.glsl.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .metal_macos = true,
            .hlsl5 = true,
            .wgsl = true,
        },
    }) catch @panic("shader compile step failed!");

    // add the shader compilation step as dependency to the build step
    // which requires the generated Zig source file

    const exe = b.addExecutable(.{
        .name = "demo",
        .root_module = mod_main,
    });

    exe.step.dependOn(shdc_step);

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    const shader_step = b.step("shaders", "Compile GLSL shaders only");
    shader_step.dependOn(shdc_step);
}
