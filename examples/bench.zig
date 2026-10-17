//! Benchmark da pipeline por frame (exemplo, não parte da lib).
//!
//! Metodologia honesta: este programa NÃO mede tempo internamente (evita
//! APIs instáveis); meça por fora, ex.:
//!   t0=$(date +%s%N); zig build run-bench -Doptimize=ReleaseFast; t1=$(date +%s%N)
//! e divida pelo total de comandos impresso no checksum.
//! O checksum impresso impede eliminação por otimização (além dos
//! syscalls do alocador, que já são efeitos observáveis).

const std = @import("std");
const zyntra_ui = @import("zyntra_ui");

const FRAMES = 200;
const RECTS_PER_FRAME = 5000;
const TEXTS_PER_FRAME = 500;
const TEXT = "Hello, ZyntraUI! Benchmark 0123456789";

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 1920, 1080),
    });
    defer ctx.deinit();

    const font = zyntra_ui.FontMetrics.withSize(16);
    var backend = zyntra_ui.NullRenderer{};
    var checksum: u64 = 0;

    var f: u32 = 0;
    while (f < FRAMES) : (f += 1) {
        ctx.beginFrame();
        // Entrada sintética intercalada (custo realista de eventos).
        const fi: f32 = @floatFromInt(f);
        try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(fi, fi) } });

        var i: u32 = 0;
        while (i < RECTS_PER_FRAME) : (i += 1) {
            const x: f32 = @floatFromInt((i * 37 + f) % 2000);
            const y: f32 = @floatFromInt((i * 53) % 1200);
            try ctx.draw.rectFilled(
                ctx.allocator,
                zyntra_ui.Rect.init(x, y, 120, 40),
                zyntra_ui.Color.rgb(70, 110, 180),
            );
        }
        var t: u32 = 0;
        while (t < TEXTS_PER_FRAME) : (t += 1) {
            const x: f32 = @floatFromInt((t * 91) % 1800);
            try ctx.draw.pushText(
                ctx.allocator,
                zyntra_ui.Vec2.init(x, 100),
                zyntra_ui.Color.rgb(255, 255, 255),
                font,
                TEXT,
            );
        }
        const stats = try backend.submit(ctx.drawCommands(), ctx.viewport);
        checksum +%= stats.visible + stats.culled + @as(u32, @intCast(ctx.pendingEvents().len));
        ctx.endFrame();
    }

    const total_cmds: u64 = FRAMES * (RECTS_PER_FRAME + TEXTS_PER_FRAME);
    std.debug.print("bench frames={d} cmds={d} checksum={d}\n", .{ FRAMES, total_cmds, checksum });

    // Fase 2 (M35): rasteriza os comandos do último frame num fb 800×600.
    // Reaproveita a draw list retida (sem reconstrução) para isolar o
    // custo do rasterizador.
    var fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 800, 600);
    defer fb.deinit(allocator);
    fb.clear(zyntra_ui.Color.rgb(0, 0, 0)); // fundo definido (alloc é lixo)
    const vp = zyntra_ui.Rect.init(0, 0, 800, 600);
    const RFRAMES = 50;
    var rdrawn: u64 = 0;
    var r: u32 = 0;
    while (r < RFRAMES) : (r += 1) {
        const st = try zyntra_ui.software.raster.render(&fb, ctx.drawCommands(), vp);
        rdrawn += st.drawn;
    }
    var pxsum: u64 = 0;
    for (fb.pixels) |b| pxsum +%= b;
    std.debug.print("raster frames={d} drawn={d} pxsum={d}\n", .{ RFRAMES, rdrawn, pxsum });

    // TreeView: 2048 nós, viewport de poucas linhas e scroll no meio.
    // Mede a navegação sob demanda em uma árvore maior que o viewport.
    const TREE_NODES = 2048;
    const TREE_FRAMES = 100;
    var nodes: [TREE_NODES]zyntra_ui.TreeItem = undefined;
    for (&nodes) |*node| {
        node.* = .{ .label = "node", .children = &[_]zyntra_ui.TreeItem{} };
    }
    var tree_selected: usize = TREE_NODES / 2;
    const tree_style = zyntra_ui.Theme.darkDefault().treeViewStyle();
    var tree_scroll: f32 = @as(f32, @floatFromInt(TREE_NODES / 2)) * tree_style.item_height;
    var tree_checksum: u64 = 0;
    var tf: usize = 0;
    while (tf < TREE_FRAMES) : (tf += 1) {
        ctx.beginFrame();
        const result = try zyntra_ui.widgets.tree_view.beginTreeView(
            &ctx,
            zyntra_ui.Id.fromString("bench:treeview"),
            zyntra_ui.Rect.init(0, 0, 320, 240),
            &nodes,
            &tree_selected,
            &tree_scroll,
            tree_style,
        );
        tree_checksum +%= @as(u64, @intCast(ctx.drawCommands().len)) + @as(u64, @intCast(result.selected));
        ctx.endFrame();
    }
    std.debug.print("treeview frames={d} nodes={d} checksum={d}\n", .{ TREE_FRAMES, TREE_NODES, tree_checksum });
}
