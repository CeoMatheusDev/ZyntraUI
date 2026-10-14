const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Módulo público da biblioteca. Consumidores usam `@import("zyntra_ui")`.
    const mod = b.addModule("zyntra_ui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Biblioteca estática instalável (núcleo atual + espaço para evolução).
    const lib = b.addLibrary(.{
        .name = "zyntra_ui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);

    // Exemplo mínimo executável (sem janela; valida init/begin/end/deinit).
    const example_exe = b.addExecutable(.{
        .name = "zyntra-minimal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/minimal.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zyntra_ui", .module = mod },
            },
        }),
    });
    b.installArtifact(example_exe);

    const run_example = b.step("run-example", "Executa o exemplo mínimo");
    const run_example_cmd = b.addRunArtifact(example_exe);
    run_example.dependOn(&run_example_cmd.step);
    run_example_cmd.step.dependOn(b.getInstallStep());

    // Testes unitários do módulo da biblioteca.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Executa os testes unitários");
    test_step.dependOn(&run_mod_tests.step);
}
