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

    // Exemplo integrado executável (M69: mini-app compondo toolbar,
    // tabbar, table e statusbar em frames compartilhados).
    const app_exe = b.addExecutable(.{
        .name = "zyntra-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/app.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zyntra_ui", .module = mod },
            },
        }),
    });
    b.installArtifact(app_exe);

    const run_app = b.step("run-app", "Executa o exemplo integrado (mini-app)");
    const run_app_cmd = b.addRunArtifact(app_exe);
    run_app.dependOn(&run_app_cmd.step);
    run_app_cmd.step.dependOn(b.getInstallStep());

    // Exemplo de UI com reserva, virtualização e cache de texto.
    const ui_perf_exe = b.addExecutable(.{
        .name = "zyntra-ui-perf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/ui_perf.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zyntra_ui", .module = mod },
            },
        }),
    });
    b.installArtifact(ui_perf_exe);

    const run_ui_perf = b.step("run-ui-perf", "Executa o exemplo de UI otimizada");
    const run_ui_perf_cmd = b.addRunArtifact(ui_perf_exe);
    run_ui_perf.dependOn(&run_ui_perf_cmd.step);
    run_ui_perf_cmd.step.dependOn(b.getInstallStep());

    // Exemplo do viewport 3D (renderizador em software + widget).
    const viewport3d_exe = b.addExecutable(.{
        .name = "zyntra-viewport3d",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/viewport3d.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zyntra_ui", .module = mod },
            },
        }),
    });
    b.installArtifact(viewport3d_exe);

    const run_viewport3d = b.step("run-viewport3d", "Executa o exemplo do viewport 3D");
    const run_viewport3d_cmd = b.addRunArtifact(viewport3d_exe);
    run_viewport3d.dependOn(&run_viewport3d_cmd.step);
    run_viewport3d_cmd.step.dependOn(b.getInstallStep());

    // Benchmark da pipeline por frame (medir por fora; ver examples/bench.zig).
    const bench_exe = b.addExecutable(.{
        .name = "zyntra-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zyntra_ui", .module = mod },
            },
        }),
    });
    b.installArtifact(bench_exe);

    const run_bench = b.step("run-bench", "Executa o benchmark da pipeline");
    const run_bench_cmd = b.addRunArtifact(bench_exe);
    run_bench.dependOn(&run_bench_cmd.step);
    run_bench_cmd.step.dependOn(b.getInstallStep());

    // Testes unitários do módulo da biblioteca.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    // O teste de sincronia de versão lê build.zig.zon em runtime:
    // declará-lo como entrada invalida o cache quando só o zon muda.
    run_mod_tests.addFileInput(b.path("build.zig.zon"));
    // O teste da tag de fetch (M70) lê README.md em runtime: mesma
    // razão para declará-lo como entrada.
    run_mod_tests.addFileInput(b.path("README.md"));

    const test_step = b.step("test", "Executa os testes unitários");
    test_step.dependOn(&run_mod_tests.step);
}
