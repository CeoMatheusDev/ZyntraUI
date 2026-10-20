//! ZyntraUI — exemplo: UI com reserva, lista virtualizada e cache de
//! texto (exemplo, não parte da lib).
//!
//! Demonstra três recursos novos (M153–M155):
//! 1. Reserva antecipada de capacidade (`Context.reserveDrawCommands`):
//!    o frame não realoca (0 crescimentos de buffer).
//! 2. Lista grande VIRTUALIZADA: só os itens visíveis são construídos e
//!    medidos (`layout.virtual.fixedRange`).
//! 3. Cache opcional de texto (`text.cache.TextCache`): o mesmo rótulo é
//!    medido muitas vezes por frame; o cache evita a medição repetida.
//!
//! O cache é do APP: a biblioteca não o usa por padrão (o ganho é
//! medido aqui).

const std = @import("std");
const zyntra_ui = @import("zyntra_ui");

const ITEMS = 10_000;
const VISIBLE_ROWS = 12;
const ROW_H: f32 = 18.0;
const CACHE_ENTRIES = 64;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 640, 480),
    });
    defer ctx.deinit();

    const theme = zyntra_ui.Theme.darkDefault();
    const font = zyntra_ui.FontMetrics.withSize(12);
    const style = theme.textInputStyle();

    // 1) Reserva antecipada: o frame de 10k linhas não realoca.
    try ctx.reserveDrawCommands(ITEMS, 64 * 1024);

    // 3) Cache de texto (bounded).
    var cache = try zyntra_ui.TextCache.init(allocator, CACHE_ENTRIES);
    defer cache.deinit();

    const scroll: f32 = 0;
    var checksum: u64 = 0;
    var drawn_items: usize = 0;

    // 2) A lista é virtualizada: só a faixa visível é desenhada.
    const list_bounds = zyntra_ui.Rect.init(8, 8, 320, ROW_H * VISIBLE_ROWS);
    const range = zyntra_ui.layout.virtual.fixedRange(
        ITEMS,
        ROW_H,
        scroll,
        list_bounds.h,
        2,
    );
    drawn_items = range.len();

    ctx.beginFrame();
    try ctx.draw.rectFilled(allocator, list_bounds, theme.listViewStyle().bg);

    var i = range.start;
    while (i < range.end) : (i += 1) {
        // O rótulo do item (medido com o cache).
        var label_buf: [32]u8 = undefined;
        const label = try std.fmt.bufPrint(&label_buf, "Item {d}", .{i});
        const m = try cache.measure(
            label,
            .{ .metrics = font },
            0,
        );
        checksum +%= @as(u64, @intFromFloat(m.width));

        const y = list_bounds.y + @as(f32, @floatFromInt(i - range.start)) * ROW_H;
        _ = try zyntra_ui.widgets.label.label(
            &ctx,
            zyntra_ui.Id.fromString("ui_perf:item"),
            zyntra_ui.Rect.init(list_bounds.x + 4, y, list_bounds.w - 8, ROW_H),
            label,
            theme.textInputStyle().text,
            font,
            false,
        );
    }
    const metrics = ctx.frameMetrics();
    ctx.endFrame();

    // Uma segunda passada mede o MESMO texto (cache quente).
    var hot: u64 = 0;
    i = range.start;
    while (i < range.end) : (i += 1) {
        var label_buf: [32]u8 = undefined;
        const label = try std.fmt.bufPrint(&label_buf, "Item {d}", .{i});
        const m = try cache.measure(label, .{ .metrics = font }, 0);
        hot +%= @as(u64, @intFromFloat(m.width));
    }

    std.debug.print(
        "ui_perf items={d} visiveis={d} primeiro={d} ultimo={d} cmds={d} growths={d} cache_hits={d} cache_misses={d} width={d}\n",
        .{
            ITEMS,
            drawn_items,
            range.start,
            range.end,
            metrics.commands_total,
            metrics.buffer_growths,
            cache.hits,
            cache.misses,
            checksum,
        },
    );
    std.debug.assert(checksum == hot); // a segunda passada mede igual

    // 4) Confirma que a lista inteira NÃO foi desenhada (virtualização).
    std.debug.assert(metrics.commands_total < ITEMS);
    std.debug.assert(metrics.buffer_growths == 0);
    _ = style;
}
