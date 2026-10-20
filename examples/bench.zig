//! Benchmark da pipeline por frame (exemplo, não parte da lib).
//!
//! Metodologia honesta: o programa mede o tempo de CADA fase com
//! `std.time.Timer` (aquecimento + 3 amostras, mediana reportada) e
//! imprime um checksum para impedir eliminação por otimização. O tempo
//! externo (`date +%s%N`) continua valendo como total do processo:
//!   t0=$(date +%s%N); zig build run-bench -Doptimize=ReleaseFast; t1=$(date +%s%N)
//!
//! As métricas estendidas (M153) vêm do próprio núcleo: contadores por
//! tipo de comando, bytes de texto, glifos, regiões sujas, crescimentos
//! de buffer e caminhos do rasterizador.

const std = @import("std");
const zyntra_ui = @import("zyntra_ui");

const FRAMES = 200;
const RECTS_PER_FRAME = 5000;
const TEXTS_PER_FRAME = 500;
const TEXT = "Hello, ZyntraUI! Benchmark 0123456789";
const SAMPLES = 3;
const WARMUP_FRAMES = 20;

/// Relógio monotônico (Zig 0.17: `std.time.Timer` não existe mais; o
/// relógio vive na interface `std.Io`).
const Clock = struct {
    io: std.Io,

    fn now(self: Clock) i96 {
        return std.Io.Clock.awake.now(self.io).nanoseconds;
    }

    fn since(self: Clock, t0: i96) u64 {
        const t = self.now();
        return @intCast(@max(0, t - t0));
    }
};

fn median3(a_in: u64, b_in: u64, c_in: u64) u64 {
    var a = a_in;
    var b = b_in;
    var c = c_in;
    if (a > b) std.mem.swap(u64, &a, &b);
    if (b > c) std.mem.swap(u64, &b, &c);
    if (a > b) std.mem.swap(u64, &a, &b);
    return b;
}

/// Uma passada da pipeline de comandos (fase 1).
fn buildFrame(
    ctx: *zyntra_ui.Context,
    backend: *zyntra_ui.NullRenderer,
    font: zyntra_ui.FontMetrics,
    f: u32,
) !u64 {
    var checksum: u64 = 0;
    ctx.beginFrame();
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
    return checksum;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 1920, 1080),
    });
    defer ctx.deinit();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const clock = Clock{ .io = threaded.io() };

    const font = zyntra_ui.FontMetrics.withSize(16);
    var backend = zyntra_ui.NullRenderer{};

    // Capacidade reservada antes do aquecimento: a fase 1 não deve
    // realocar (M153).
    try ctx.reserveDrawCommands(FRAMES * (RECTS_PER_FRAME + TEXTS_PER_FRAME), 0);
    try ctx.reserveTextBytes(FRAMES * TEXTS_PER_FRAME * TEXT.len);

    // Aquecimento (caches, ramos, alocadores).
    var w: u32 = 0;
    while (w < WARMUP_FRAMES) : (w += 1) {
        _ = try buildFrame(&ctx, &backend, font, w);
    }

    // 3 amostras da fase 1 (mediana reportada).
    var samples: [SAMPLES]u64 = undefined;
    var checksum: u64 = 0;
    for (0..SAMPLES) |s| {
        const t0 = clock.now();
        var f: u32 = 0;
        while (f < FRAMES) : (f += 1) {
            checksum +%= try buildFrame(&ctx, &backend, font, f + @as(u32, @intCast(s)) * FRAMES);
        }
        samples[s] = clock.since(t0);
    }
    const build_ns = median3(samples[0], samples[1], samples[2]);
    const total_cmds: u64 = FRAMES * (RECTS_PER_FRAME + TEXTS_PER_FRAME);
    std.debug.print("bench frames={d} cmds={d} checksum={d}\n", .{ FRAMES, total_cmds, checksum });
    std.debug.print(
        "bench timing build_median={d}us per_frame={d}ns per_cmd={d}ns\n",
        .{ build_ns / 1000, build_ns / FRAMES, build_ns / (total_cmds * SAMPLES) },
    );

    // Métricas estendidas do frame (M153).
    const m = ctx.frameMetrics();
    std.debug.print(
        "bench metrics cmds={d} visible={d} culled={d} rects={d} texts={d} bytes={d} growths={d}\n",
        .{
            m.commands_total, m.commands_visible, m.commands_culled,
            m.rects,          m.texts,            m.text_bytes,
            m.buffer_growths,
        },
    );

    // Fase 2 (M35): rasteriza os comandos do último frame num fb 800×600.
    // Reaproveita a draw list retida (sem reconstrução) para isolar o
    // custo do rasterizador.
    var fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 800, 600);
    defer fb.deinit(allocator);
    fb.clear(zyntra_ui.Color.rgb(0, 0, 0)); // fundo definido (alloc é lixo)
    const vp = zyntra_ui.Rect.init(0, 0, 800, 600);
    const RFRAMES = 50;
    var rdrawn: u64 = 0;
    var rt: u64 = 0;
    var r: u32 = 0;
    {
        const t0 = clock.now();
        while (r < RFRAMES) : (r += 1) {
            const st = try zyntra_ui.software.raster.render(&fb, ctx.drawCommands(), vp);
            rdrawn += st.drawn;
        }
        rt = clock.since(t0);
    }
    var pxsum: u64 = 0;
    for (fb.pixels) |b| pxsum +%= b;
    std.debug.print("raster frames={d} drawn={d} pxsum={d}\n", .{ RFRAMES, rdrawn, pxsum });
    std.debug.print(
        "raster timing={d}us per_frame={d}us fast={d} generic={d} pixels={d}\n",
        .{
            rt / 1000,
            rt / RFRAMES,
            fb.metrics.rect_fast_path,
            fb.metrics.rect_generic_path,
            fb.metrics.pixels_written,
        },
    );

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
