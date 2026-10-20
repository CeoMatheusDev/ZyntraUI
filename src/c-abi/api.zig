//! ZyntraUI — API C opcional (c-abi/api).
//!
//! Ownership e lifetime:
//! - `zyntra_context_create` aloca o `Context` no `page_allocator`
//!   interno e entrega um handle opaco; o chamador passa a deter o
//!   handle e DEVE chamar `zyntra_context_destroy` exatamente uma vez.
//! - O alocador interno pertence à camada C-ABI (não é o do chamador);
//!   buffers de eventos/desenho vivem e morrem com o handle.
//! - Todos os ponteiros de saída devem ser não-nulos; ponteiros nulos
//!   retornam `invalid_argument` sem tocar memória.
//! - Handles nulos retornam `invalid_argument` (destroy é null-safe).
//! - Slices/strings Zig NUNCA cruzam a fronteira: listas de texto vão como
//!   `ZyntraStr` (ptr + len, tamanho fixo) emprestados só na chamada, que os
//!   widgets copiam para a `DrawList`.
//! Threading: um handle, uma thread por vez (sem lock interno).
//!
//! Símbolos exportados com ABI C estável (`export ... callconv(.c)`).

const std = @import("std");
const context_mod = @import("../core/context.zig");
const types_mod = @import("../core/types.zig");
const event_mod = @import("../event/event.zig");
const metrics_mod = @import("../text/metrics.zig");
const software_mod = @import("../software/raster.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const label_mod = @import("../widgets/label.zig");
const button_mod = @import("../widgets/button.zig");
const checkbox_mod = @import("../widgets/checkbox.zig");
const switch_mod = @import("../widgets/switch.zig");
const slider_mod = @import("../widgets/slider.zig");
const progress_mod = @import("../widgets/progress.zig");
const separator_mod = @import("../widgets/separator.zig");
const radio_mod = @import("../widgets/radio.zig");
const tab_bar_mod = @import("../widgets/tab_bar.zig");
const list_view_mod = @import("../widgets/list_view.zig");
const panel_mod = @import("../widgets/panel.zig");
const menu_mod = @import("../widgets/menu.zig");
const table_mod = @import("../widgets/table.zig");
const tree_mod = @import("../widgets/tree_view.zig");
const text_input_mod = @import("../widgets/text_input.zig");
const textarea_mod = @import("../widgets/textarea.zig");
const combo_mod = @import("../widgets/combo.zig");
const splitter_mod = @import("../widgets/splitter.zig");
const spinner_mod = @import("../widgets/spinner.zig");
const groupbox_mod = @import("../widgets/groupbox.zig");
const tooltip_mod = @import("../widgets/tooltip.zig");
const scroll_mod = @import("../widgets/scroll.zig");
const popup_mod = @import("../widgets/popup.zig");
const modal_mod = @import("../widgets/modal.zig");
const drag_ghost_mod = @import("../widgets/drag_ghost.zig");
const dnd_mod = @import("../dnd/service.zig");
const toolbar_mod = @import("../widgets/toolbar.zig");
const statusbar_mod = @import("../widgets/statusbar.zig");
const layout_mod = @import("../layout/layout.zig");
const graph_view_mod = @import("../widgets/graph_view.zig");
const graph_mod = @import("../graph/view.zig");
const timeline_view_mod = @import("../widgets/timeline_view.zig");
const timeline_mod = @import("../timeline/view.zig");
const inspector_view_mod = @import("../widgets/inspector_view.zig");
const inspector_mod = @import("../inspector/view.zig");
const anim_mod = @import("../anim/anim.zig");
const commands_mod = @import("../draw/commands.zig");
const image_mod = @import("../draw/image.zig");
const scale_mod = @import("../core/scale.zig");
const ime_mod = @import("../text/ime.zig");
const atlas_mod = @import("../text/atlas.zig");
const bitmap_mod = @import("../text/bitmap.zig");
const text_layout_mod = @import("../text/layout.zig");
const text_block_mod = @import("../widgets/text_block.zig");
const path_mod = @import("../draw/path.zig");
const svg_mod = @import("../draw/svg.zig");
const image_widget_mod = @import("../widgets/image.zig");
const vp3d_math = @import("../viewport3d/math.zig");
const vp3d_camera = @import("../viewport3d/camera.zig");
const vp3d_mesh = @import("../viewport3d/mesh.zig");
const vp3d_raster = @import("../viewport3d/raster.zig");
const vp3d_pick = @import("../viewport3d/pick.zig");
const vp3d_grid = @import("../viewport3d/grid.zig");
const dock_layout_mod = @import("../dock/layout.zig");
const dock_view_mod = @import("../widgets/dock_view.zig");
const ct = @import("types.zig");

/// Handle opaco. O layout real (`Context`) nunca é exposto.
pub const ZyntraContext = opaque {};

const Ctx = context_mod.Context;

fn toCtx(h: *ZyntraContext) *Ctx {
    return @ptrCast(@alignCast(h));
}

fn mapErr(err: context_mod.ContextError) ct.ZyntraResult {
    return switch (err) {
        error.InvalidArgument => .invalid_argument,
        error.OutOfMemory => .out_of_memory,
        error.InvalidEvent => .invalid_event,
        error.InvalidCommand => .invalid_command,
    };
}

fn checkHandle(h: ?*ZyntraContext) !*ZyntraContext {
    return h orelse return error.InvalidArgument;
}

fn toRect(rect: ct.ZyntraRect) types_mod.Rect {
    return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
}

fn toVec2(v: ct.ZyntraVec2) types_mod.Vec2 {
    return .{ .x = v.x, .y = v.y };
}

fn toColor(c: ct.ZyntraColor) types_mod.Color {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

fn fromColor(c: types_mod.Color) ct.ZyntraColor {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

fn fromRect(r: types_mod.Rect) ct.ZyntraRect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

fn cStr(s: []const u8) ct.ZyntraStr {
    return .{ .ptr = if (s.len == 0) null else s.ptr, .len = s.len };
}

/// Define o alfa global dos comandos SEGUINTES (0..1): o que for
/// desenhado depois sai atenuado (fade). Vale até o próximo alfa ou o
/// fim do frame. Valores acima de 1 são tratados como 1.
pub export fn zyntra_draw_alpha(handle: ?*ZyntraContext, factor: f32) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    if (!std.math.isFinite(factor) or factor < 0) return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.pushAlpha(ctx.allocator, factor));
}

/// Registra a fonte de bitmap global (M144): o atlas MONOESPAÇADO é
/// usado por TODOS os widgets do contexto. `size` é o tamanho de fonte
/// usado pelos widgets: o avanço do atlas precisa ser igual ao das
/// métricas desse tamanho (senão a medida e o desenho divergiriam).
pub export fn zyntra_context_set_bitmap_font(
    handle: ?*ZyntraContext,
    atlas: ?*ZyntraFontAtlas,
    size: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const a = atlas orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const state = toFontAtlas(a);
    state.refresh();
    const bf = bitmap_mod.BitmapFont.init(&state.view) catch return .invalid_argument;
    if (!bf.matches(metrics_mod.FontMetrics.withSize(size))) return .invalid_argument;
    toCtx(h).setBitmapFont(bf);
    return .ok;
}

/// Remove a fonte de bitmap global do contexto (volta ao texto normal).
pub export fn zyntra_context_clear_bitmap_font(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).setBitmapFont(null);
    return .ok;
}

/// Desenha uma imagem RGBA8 (pixels emprestados do chamador) em `rect`.
/// `stride` é a distância em bytes entre linhas; `tint` modula RGBA.
/// Os pixels precisam viver até o backend consumir o frame.
pub export fn zyntra_draw_image(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    pixels: ?[*]const u8,
    width: u32,
    height: u32,
    stride: u32,
    tint: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    return drawImageRegion(handle, rect, pixels, width, height, stride, 0, 0, width, height, tint);
}

/// Desenha uma região inteira da imagem (sprite/atlas) em `rect`.
pub export fn zyntra_draw_image_region(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    pixels: ?[*]const u8,
    width: u32,
    height: u32,
    stride: u32,
    src_x: u32,
    src_y: u32,
    src_w: u32,
    src_h: u32,
    tint: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    return drawImageRegion(handle, rect, pixels, width, height, stride, src_x, src_y, src_w, src_h, tint);
}

fn drawImageRegion(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    pixels: ?[*]const u8,
    width: u32,
    height: u32,
    stride: u32,
    src_x: u32,
    src_y: u32,
    src_w: u32,
    src_h: u32,
    tint: ct.ZyntraColor,
) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const px = pixels orelse return .invalid_argument;
    if (width == 0 or height == 0) return .invalid_argument;
    const row_bytes = @as(u64, width) * image_mod.bytes_per_pixel;
    if (row_bytes > std.math.maxInt(u32)) return .invalid_argument;
    if (@as(u64, stride) < row_bytes) return .invalid_argument;
    const region = image_mod.Region.init(src_x, src_y, src_w, src_h);
    if (!region.isValidFor(width, height)) return .invalid_argument;
    const ctx = toCtx(h);
    const cmd = commands_mod.DrawCommand{ .image = .{
        .rect = toRect(rect),
        .src = region,
        .pixels = px,
        .width = width,
        .height = height,
        .stride = stride,
        .tint = toColor(tint),
    } };
    return pushDraw(ctx.draw.push(ctx.allocator, cmd));
}

/// Erros possíveis ao enfileirar um comando na `DrawList`.
const DrawError = error{ OutOfMemory, InvalidCommand, InvalidUtf8, InvalidMetrics };

/// Traduz o erro de um comando de desenho para o código C (o comando
/// rejeitado NÃO entra na lista).
fn pushDraw(result: DrawError!void) ct.ZyntraResult {
    result catch |err| return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.InvalidCommand => .invalid_command,
        error.InvalidUtf8 => .invalid_text,
        error.InvalidMetrics => .invalid_argument,
    };
    return .ok;
}

pub export fn zyntra_version_major() callconv(.c) u32 {
    return types_mod.version_major;
}

pub export fn zyntra_version_minor() callconv(.c) u32 {
    return types_mod.version_minor;
}

pub export fn zyntra_version_patch() callconv(.c) u32 {
    return types_mod.version_patch;
}

/// Sufixo de pré-lançamento (`""` quando estável). Ponteiro para
/// armazenamento estático — válido para sempre, sem free.
pub export fn zyntra_version_prerelease() callconv(.c) [*:0]const u8 {
    return types_mod.version_prerelease;
}

// ---------------------------------------------------------------------------
// Docking: modelo, consultas e área interativa (M113)
// ---------------------------------------------------------------------------
// O layout de docking (`dock.layout.DockLayout`) é um array fixo de nós; a
// fronteira C o expõe como um handle opaco alocado no `page_allocator`
// interno (como `ZyntraFramebuffer`). O chamador cria com `zyntra_dock_create`
// e destrói com `zyntra_dock_destroy` exatamente uma vez; todos os mutadores e
// consultas operam sobre esse handle. Nada é exposto do layout interno.

/// Handle opaco do atlas de glifos (M139). Nunca desreferenciar, copiar
/// o struct interno (não existe na fronteira) ou liberar com `free`.
///
/// O atlas é construído pelo CHAMADOR em três passos:
/// 1. `zyntra_font_atlas_create` (dimensões do atlas e padding);
/// 2. `zyntra_font_atlas_add_glyph` por glifo — devolve a região
///    (x, y) onde o chamador rasteriza o bitmap;
/// 3. `zyntra_font_atlas_set_image` aponta o atlas para a imagem
///    RGBA8 (emprestada) já rasterizada.
///
/// O handle é destruído com `zyntra_font_atlas_destroy` exatamente uma vez.
pub const ZyntraFontAtlas = opaque {};

/// Estado interno do atlas de glifos (nunca cruza a fronteira).
const FontAtlas = struct {
    builder: atlas_mod.Builder,
    /// Glifos ordenados por codepoint (busca binária).
    glyphs: std.ArrayList(atlas_mod.Glyph) = .empty,
    /// Imagem do atlas (emprestada do chamador).
    image: image_mod.Image = .{},
    /// Vista estável do atlas (ponteiro válido enquanto o handle vive):
    /// é o que a fonte de bitmap global referencia.
    view: atlas_mod.FontAtlas = .{},

    fn deinit(self: *FontAtlas, gpa: std.mem.Allocator) void {
        self.builder.deinit(gpa);
        self.glyphs.deinit(gpa);
        self.image = .{};
        self.view = .{};
    }

    /// Atualiza a vista depois de mutações (glifos/imagem).
    fn refresh(self: *FontAtlas) void {
        self.view = .{ .image = self.image, .glyphs = self.glyphs.items, .scale = 1 };
    }
};

fn toFontAtlas(h: *ZyntraFontAtlas) *FontAtlas {
    return @ptrCast(@alignCast(h));
}

/// Cria um atlas de glifos vazio (`width`×`height` em pixels do atlas e
/// `padding` entre glifos). O atlas é construído pelo chamador:
/// `zyntra_font_atlas_add_glyph` reserva a região de cada glifo e
/// `zyntra_font_atlas_set_image` aponta para a imagem já rasterizada.
pub export fn zyntra_font_atlas_create(
    width: u32,
    height: u32,
    padding: u32,
    out: ?*?*ZyntraFontAtlas,
) callconv(.c) ct.ZyntraResult {
    const o = out orelse return .invalid_argument;
    if (width == 0 or height == 0) return .invalid_argument;
    const gpa = std.heap.page_allocator;
    const atlas = gpa.create(FontAtlas) catch return .out_of_memory;
    atlas.* = .{ .builder = atlas_mod.Builder.init(width, height, padding) };
    o.* = @ptrCast(atlas);
    return .ok;
}

/// Destrói o atlas (o chamador DEVE chamar exatamente uma vez).
pub export fn zyntra_font_atlas_destroy(atlas: ?*ZyntraFontAtlas) callconv(.c) ct.ZyntraResult {
    const a = atlas orelse return .invalid_argument;
    const gpa = std.heap.page_allocator;
    const state = toFontAtlas(a);
    state.deinit(gpa);
    gpa.destroy(state);
    return .ok;
}

/// Reserva a região de um glifo e devolve (x, y) no atlas: o chamador
/// rasteriza ali o bitmap do glifo. `advance`/`bearing_y` são em pixels
/// LÓGICOS (avanço horizontal e deslocamento vertical do bitmap em
/// relação à linha de base; negativo = acima da base).
pub export fn zyntra_font_atlas_add_glyph(
    atlas: ?*ZyntraFontAtlas,
    codepoint: u32,
    width: u32,
    height: u32,
    advance: f32,
    bearing_y: f32,
    out_x: ?*u32,
    out_y: ?*u32,
) callconv(.c) ct.ZyntraResult {
    const a = atlas orelse return .invalid_argument;
    const ox = out_x orelse return .invalid_argument;
    const oy = out_y orelse return .invalid_argument;
    if (codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF)) {
        return .invalid_argument;
    }
    const gpa = std.heap.page_allocator;
    const state = toFontAtlas(a);
    // Duplicado? (a tabela do estado é ordenada por codepoint)
    {
        var k: usize = 0;
        while (k < state.glyphs.items.len and state.glyphs.items[k].codepoint < codepoint) k += 1;
        if (k < state.glyphs.items.len and state.glyphs.items[k].codepoint == codepoint) {
            return .invalid_argument;
        }
    }
    const glyph = state.builder.addGlyph(gpa, @intCast(codepoint), width, height, .{
        .advance = advance,
        .bearing_y = bearing_y,
        .height = @floatFromInt(height),
    }) catch |err| return switch (err) {
        error.AtlasFull => .invalid_argument,
        error.InvalidMetrics => .invalid_argument,
        error.InvalidGlyph => .invalid_argument,
        error.DuplicateGlyph => .invalid_argument,
        error.OutOfMemory => .out_of_memory,
        error.InvalidUtf8 => .invalid_text,
        error.InvalidCommand => .invalid_command,
    };
    // Mantém a tabela ordenada por codepoint (busca binária).
    var idx: usize = 0;
    while (idx < state.glyphs.items.len and state.glyphs.items[idx].codepoint < glyph.codepoint) {
        idx += 1;
    }
    state.glyphs.insert(gpa, idx, glyph) catch return .out_of_memory;
    // A tabela do builder não é usada na fronteira C (a tabela
    // ordenada do estado é) — libera o crescimento dela.
    state.builder.entries.clearRetainingCapacity();
    state.refresh();
    ox.* = glyph.region.x;
    oy.* = glyph.region.y;
    return .ok;
}

/// Define a imagem do atlas (pixels RGBA8 emprestados do chamador).
/// `stride` é a distância em bytes entre linhas.
pub export fn zyntra_font_atlas_set_image(
    atlas: ?*ZyntraFontAtlas,
    pixels: ?[*]const u8,
    width: u32,
    height: u32,
    stride: u32,
) callconv(.c) ct.ZyntraResult {
    const a = atlas orelse return .invalid_argument;
    const px = pixels orelse return .invalid_argument;
    if (width == 0 or height == 0) return .invalid_argument;
    const row_bytes = @as(u64, width) * image_mod.bytes_per_pixel;
    if (row_bytes > std.math.maxInt(u32)) return .invalid_argument;
    if (@as(u64, stride) < row_bytes) return .invalid_argument;
    const needed = @as(u64, stride) * height;
    if (needed > std.math.maxInt(usize)) return .invalid_argument;
    const state = toFontAtlas(a);
    state.image = .{
        .width = width,
        .height = height,
        .stride = stride,
        // O comprimento real é desconhecido na fronteira: o chamador
        // garante que o buffer cobre `stride * height` bytes.
        .pixels = @as([*]const u8, px)[0..@intCast(needed)],
    };
    state.refresh();
    return .ok;
}

/// Largura (pixels lógicos) de um trecho com os AVANÇOS do atlas.
pub export fn zyntra_font_atlas_measure(
    atlas: ?*ZyntraFontAtlas,
    utf8: ?[*]const u8,
    utf8_len: usize,
    out_width: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const a = atlas orelse return .invalid_argument;
    const out = out_width orelse return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const text: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const state = toFontAtlas(a);
    out.* = state.view.measure(text) catch |err| return switch (err) {
        error.InvalidUtf8 => .invalid_text,
        error.InvalidMetrics => .invalid_argument,
        error.OutOfMemory => .out_of_memory,
        error.InvalidGlyph => .invalid_argument,
        error.DuplicateGlyph => .invalid_argument,
        error.AtlasFull => .invalid_argument,
        error.InvalidCommand => .invalid_command,
    };
    return .ok;
}

/// Altura de linha do atlas (ascente + descida, em pixels lógicos).
pub export fn zyntra_font_atlas_line_height(
    atlas: ?*ZyntraFontAtlas,
    out_height: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const a = atlas orelse return .invalid_argument;
    const out = out_height orelse return .invalid_argument;
    out.* = toFontAtlas(a).view.lineHeight();
    return .ok;
}

/// Desenha um trecho de texto com o atlas: cada glifo vira um blit da
/// sua região. `pos` é o canto superior-esquerdo do texto.
pub export fn zyntra_font_atlas_draw_run(
    handle: ?*ZyntraContext,
    atlas: ?*ZyntraFontAtlas,
    utf8: ?[*]const u8,
    utf8_len: usize,
    pos: ct.ZyntraVec2,
    tint: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const a = atlas orelse return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const text: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const ctx = toCtx(h);
    const state = toFontAtlas(a);
    const view = state.view;
    const baseline = ct.ZyntraVec2{
        .x = pos.x,
        .y = pos.y + view.ascent(),
    };
    atlas_mod.drawRun(&ctx.draw, ctx.allocator, &view, text, toVec2(baseline), toColor(tint)) catch |err| return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.InvalidUtf8 => .invalid_text,
        error.InvalidMetrics => .invalid_argument,
        error.InvalidGlyph => .invalid_argument,
        error.DuplicateGlyph => .invalid_argument,
        error.AtlasFull => .invalid_argument,
        error.InvalidCommand => .invalid_command,
    };
    return .ok;
}

/// Rótulo desenhado com o atlas de glifos (fonte real). O texto sai
/// como blits — visível até no rasterizador de referência.
pub export fn zyntra_widget_label_atlas(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    utf8: ?[*]const u8,
    utf8_len: usize,
    color: ct.ZyntraColor,
    atlas: ?*ZyntraFontAtlas,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const a = atlas orelse return .invalid_argument;
    if (id == 0) return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const text: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const ctx = toCtx(h);
    const state = toFontAtlas(a);
    const view = state.view;
    const layout = text_layout_mod.Layout.fromAtlas(&view) catch return .invalid_argument;
    const baseline = ct.ZyntraVec2{
        .x = bounds.x,
        .y = bounds.y + view.ascent(),
    };
    layout.draw(&ctx.draw, ctx.allocator, text, toVec2(baseline), toColor(color)) catch |err| return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.InvalidCommand => .invalid_command,
        error.InvalidUtf8 => .invalid_text,
        error.InvalidMetrics => .invalid_argument,
        error.InvalidGlyph => .invalid_argument,
        error.InvalidArgument => .invalid_argument,
    };
    return .ok;
}

/// Handle opaco do layout de docking. Nunca desreferenciar, copiar o struct
/// interno (não existe na fronteira) ou liberar com `free`.
pub const ZyntraDock = opaque {};

const Dock = dock_layout_mod.DockLayout;

fn toDock(h: *ZyntraDock) *Dock {
    return @ptrCast(@alignCast(h));
}

fn checkDock(h: ?*ZyntraDock) !*ZyntraDock {
    return h orelse error.InvalidArgument;
}

/// Orientação de um split a partir do valor de `ZyntraOrientation`
/// (`ZYNTRA_HORIZONTAL`/`ZYNTRA_VERTICAL`); fora da faixa ⇒ `null`.
fn toDockOrientation(v: i32) ?dock_layout_mod.DockOrientation {
    const o = std.enums.fromInt(ct.ZyntraOrientation, v) orelse return null;
    return switch (o) {
        .horizontal => .horizontal,
        .vertical => .vertical,
    };
}

fn fromDockZone(z: dock_layout_mod.DockZone) ct.ZyntraDockZone {
    return switch (z) {
        .left => .left,
        .right => .right,
        .top => .top,
        .bottom => .bottom,
        .center => .center,
    };
}

fn fromDockGroup(g: dock_layout_mod.DockGroup) ct.ZyntraDockGroup {
    var out: ct.ZyntraDockGroup = .{};
    @memcpy(&out.panes, &g.panes);
    out.count = g.count;
    out.active = g.active;
    return out;
}

fn fromDockDrop(d: dock_view_mod.DockDrop) ct.ZyntraDockDrop {
    return .{
        .pane = d.pane,
        .target = d.target,
        .zone = fromDockZone(d.zone),
        .rect = fromRect(d.rect),
    };
}

/// Cria um layout de docking com um único painel (`pane`) no `page_allocator`
/// interno. `out` não pode ser nulo.
pub export fn zyntra_dock_create(
    pane: u16,
    out: ?*?*ZyntraDock,
) callconv(.c) ct.ZyntraResult {
    const o = out orelse return .invalid_argument;
    const gpa = std.heap.page_allocator;
    const dock = gpa.create(Dock) catch return .out_of_memory;
    dock.* = .{};
    dock_layout_mod.dockInit(dock, pane);
    o.* = @ptrCast(dock);
    return .ok;
}

/// Destrói o layout de docking (NULL é seguro).
pub export fn zyntra_dock_destroy(handle: ?*ZyntraDock) callconv(.c) void {
    const h = handle orelse return;
    std.heap.page_allocator.destroy(toDock(h));
}

/// Reinicia o layout como um único painel `pane`.
pub export fn zyntra_dock_init(handle: ?*ZyntraDock, pane: u16) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    dock_layout_mod.dockInit(toDock(h), pane);
    return .ok;
}

/// Divide a folha `leaf` em dois lados: o grupo original fica em um lado e
/// `pane` no outro, com `orientation` (`ZYNTRA_HORIZONTAL`/`_VERTICAL`) e
/// `ratio` em [0,1] (clampado). `out_leaf` recebe o índice da folha nova.
/// Folha inválida ou capacidade esgotada ⇒ `ZYNTRA_INVALID_ARGUMENT`.
pub export fn zyntra_dock_split(
    handle: ?*ZyntraDock,
    leaf: u8,
    orientation: i32,
    ratio: f32,
    pane: u16,
    out_leaf: ?*u8,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    const o = out_leaf orelse return .invalid_argument;
    const orient = toDockOrientation(orientation) orelse return .invalid_argument;
    const idx = dock_layout_mod.dockSplit(toDock(h), leaf, orient, ratio, pane) catch return .invalid_argument;
    o.* = @intCast(idx);
    return .ok;
}

/// Ajusta a proporção do split `node` (clampada; no-op se não for split).
pub export fn zyntra_dock_set_ratio(
    handle: ?*ZyntraDock,
    node: u8,
    ratio: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    dock_layout_mod.dockSetRatio(toDock(h), node, ratio);
    return .ok;
}

/// Anexa `pane` como aba da folha `leaf`. `out_added` (opcional) recebe se
/// houve mudança (grupo cheio/duplicado ⇒ no-op, `false`).
pub export fn zyntra_dock_add_tab(
    handle: ?*ZyntraDock,
    leaf: u8,
    pane: u16,
    out_added: ?*bool,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    const added = dock_layout_mod.dockAddTab(toDock(h), leaf, pane);
    if (out_added) |o| o.* = added;
    return .ok;
}

/// Ativa a aba `tab` da folha `leaf`. `out_set` (opcional) recebe se houve
/// mudança (folha inválida/aba fora da faixa ⇒ no-op, `false`).
pub export fn zyntra_dock_set_active_tab(
    handle: ?*ZyntraDock,
    leaf: u8,
    tab: u8,
    out_set: ?*bool,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    const set = dock_layout_mod.dockSetActiveTab(toDock(h), leaf, tab);
    if (out_set) |o| o.* = set;
    return .ok;
}

/// Remove o painel `pane` (aba ou grupo inteiro; dissolve o split se for a
/// última aba). `out_removed` (opcional) recebe se houve mudança.
pub export fn zyntra_dock_remove_pane(
    handle: ?*ZyntraDock,
    pane: u16,
    out_removed: ?*bool,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    const removed = dock_layout_mod.dockRemovePane(toDock(h), pane);
    if (out_removed) |o| o.* = removed;
    return .ok;
}

/// Grupo (abas + ativa) da folha `leaf`; nó não-folha/índice inválido ⇒
/// `ZYNTRA_INVALID_ARGUMENT`.
pub export fn zyntra_dock_group(
    handle: ?*ZyntraDock,
    leaf: u8,
    out_group: ?*ct.ZyntraDockGroup,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    const o = out_group orelse return .invalid_argument;
    const g = dock_layout_mod.dockGroup(toDock(h), leaf) orelse return .invalid_argument;
    o.* = fromDockGroup(g);
    return .ok;
}

/// Divisórias do layout (pré-ordem) dentro de `bounds`, com `divider` px
/// entre os lados. `out` pode ser NULL com `out_len == 0` (só a contagem);
/// `out_len` menor que o número de splits ⇒ `ZYNTRA_INVALID_ARGUMENT`.
pub export fn zyntra_dock_splits(
    handle: ?*ZyntraDock,
    bounds: ct.ZyntraRect,
    divider: f32,
    out: ?[*]ct.ZyntraDockSplitInfo,
    out_len: usize,
    out_count: ?*usize,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    const count = out_count orelse return .invalid_argument;
    var scratch: [Dock.max_panes]dock_layout_mod.DockSplitInfo = undefined;
    const n = dock_layout_mod.dockSplits(toDock(h), toRect(bounds), divider, &scratch) catch return .invalid_argument;
    if (out) |dst| {
        if (out_len < n) return .invalid_argument;
        for (scratch[0..n], 0..) |info, i| {
            dst[i] = .{
                .node = info.node,
                .orientation = @intCast(@backingInt(info.orientation)),
                .ratio = info.ratio,
                .rect = fromRect(info.rect),
                .divider = fromRect(info.divider),
            };
        }
    } else if (out_len != 0) return .invalid_argument;
    count.* = n;
    return .ok;
}

/// Grupos (nó + abas/ativo + rect) em pré-ordem das folhas, dentro de
/// `bounds`, com `divider` px entre os lados. `out` pode ser NULL com
/// `out_len == 0` (só a contagem); `out_len` menor que o número de grupos ⇒
/// `ZYNTRA_INVALID_ARGUMENT`.
pub export fn zyntra_dock_panes(
    handle: ?*ZyntraDock,
    bounds: ct.ZyntraRect,
    divider: f32,
    out: ?[*]ct.ZyntraDockPaneInfo,
    out_len: usize,
    out_count: ?*usize,
) callconv(.c) ct.ZyntraResult {
    const h = checkDock(handle) catch return .invalid_argument;
    const count = out_count orelse return .invalid_argument;
    var scratch: [Dock.max_panes]dock_layout_mod.DockPaneInfo = undefined;
    const n = dock_layout_mod.dockPanes(toDock(h), toRect(bounds), divider, &scratch) catch return .invalid_argument;
    if (out) |dst| {
        if (out_len < n) return .invalid_argument;
        for (scratch[0..n], 0..) |info, i| {
            dst[i] = .{
                .node = info.node,
                .group = fromDockGroup(info.group),
                .rect = fromRect(info.rect),
            };
        }
    } else if (out_len != 0) return .invalid_argument;
    count.* = n;
    return .ok;
}

/// Estilo de docking do tema embutido (`kind`: `ZYNTRA_THEME_DARK`/`_LIGHT`).
pub export fn zyntra_style_dock(kind: i32, out_style: ?*ct.ZyntraDockStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.dockStyle();
    return .ok;
}

/// Área de docking interativa: desenha fundo/divisórias, trata o arraste das
/// divisórias e o drop de painéis, e devolve os grupos (nó + abas/ativo +
/// rect) em `panes`. `dragging` é o painel arrastado (`-1` = nenhum) e
/// `edge_frac` a fração de borda que dispara uma zona (0..0.5).
/// `panes` é do chamador e precisa comportar `ZYNTRA_DOCK_MAX_PANES` entradas
/// (NULL + `panes_len == 0` desenha sem escrever). `out_result` é opcional.
pub export fn zyntra_widget_dock_view(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    dock: ?*ZyntraDock,
    panes: ?[*]ct.ZyntraDockPaneInfo,
    panes_len: usize,
    dragging: i64,
    edge_frac: f32,
    style: ?*const ct.ZyntraDockStyle,
    out_result: ?*ct.ZyntraDockViewResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const d = checkDock(dock) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    if (panes == null and panes_len > 0) return .invalid_argument;
    if (panes != null and panes_len == 0) return .invalid_argument;
    if (dragging < -1 or dragging > 0xFFFF) return .invalid_argument;

    var scratch: [Dock.max_panes]dock_layout_mod.DockPaneInfo = undefined;
    const cap: usize = if (panes) |_| @min(panes_len, scratch.len) else scratch.len;
    const options: dock_view_mod.DockViewOptions = .{
        .dragging = if (dragging < 0) null else @as(u16, @intCast(dragging)),
        .edge_frac = edge_frac,
    };
    const res = dock_view_mod.dockView(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toDock(d),
        toRect(bounds),
        scratch[0..cap],
        st.*,
        options,
    ) catch |err| {
        if (err == error.OutOfBuffer) return .invalid_argument;
        return mapWidgetErr(err);
    };

    if (panes) |dst| {
        for (scratch[0..res.pane_count], 0..) |info, i| {
            dst[i] = .{
                .node = info.node,
                .group = fromDockGroup(info.group),
                .rect = fromRect(info.rect),
            };
        }
    }
    if (out_result) |o| o.* = .{
        .pane_count = res.pane_count,
        .split_count = res.split_count,
        .changed = res.changed,
        .has_drop = res.drop != null,
        .has_dropped = res.dropped != null,
        .hovered = fromIndex(res.hovered),
        .dragging = fromIndex(res.dragging),
        .drop = if (res.drop) |dd| fromDockDrop(dd) else .{},
        .dropped = if (res.dropped) |dd| fromDockDrop(dd) else .{},
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Draw moderno API function declarations (M114)
// ---------------------------------------------------------------------------
/// Preenchimento em gradiente radial: `color0` no centro, `color1` na borda,
/// contido em `rect`.
pub export fn zyntra_draw_gradient_radial(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    radius: f32,
    color0: ct.ZyntraColor,
    color1: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.rectGradientRadial(
        ctx.allocator,
        toRect(rect),
        radius,
        toColor(color0),
        toColor(color1),
    ));
}

/// Preenchimento em gradiente cônico: `color0` no ângulo `start_angle`
/// (radianos desde +X, anti-horário), `color1` em `start_angle + sweep`.
pub export fn zyntra_draw_gradient_conic(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    center: ct.ZyntraVec2,
    start_angle: f32,
    sweep: f32,
    color0: ct.ZyntraColor,
    color1: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.rectGradientConic(
        ctx.allocator,
        toRect(rect),
        toVec2(center),
        start_angle,
        sweep,
        toColor(color0),
        toColor(color1),
    ));
}

pub export fn zyntra_context_create(viewport: ct.ZyntraRect, out_handle: ?*?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const out = out_handle orelse return .invalid_argument;
    if (viewport.w < 0 or viewport.h < 0) return .invalid_argument;
    const gpa = std.heap.page_allocator;
    const ctx = gpa.create(Ctx) catch return .out_of_memory;
    ctx.* = Ctx.init(gpa, .{
        .viewport = .{ .x = viewport.x, .y = viewport.y, .w = viewport.w, .h = viewport.h },
    }) catch |err| {
        gpa.destroy(ctx);
        return mapErr(err);
    };
    out.* = @ptrCast(ctx);
    return .ok;
}

pub export fn zyntra_context_destroy(handle: ?*ZyntraContext) callconv(.c) void {
    const h = handle orelse return;
    const ctx = toCtx(h);
    const gpa = std.heap.page_allocator;
    ctx.deinit();
    gpa.destroy(ctx);
}

pub export fn zyntra_context_begin_frame(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    if (ctx.isFrameActive()) return .invalid_state;
    ctx.beginFrame();
    return .ok;
}

pub export fn zyntra_context_end_frame(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    if (!ctx.isFrameActive()) return .invalid_state;
    ctx.endFrame();
    return .ok;
}

pub export fn zyntra_context_frame_index(handle: ?*ZyntraContext, out_index: ?*u64) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_index orelse return .invalid_argument;
    out.* = toCtx(h).frame_index;
    return .ok;
}

pub export fn zyntra_context_set_viewport(handle: ?*ZyntraContext, viewport: ct.ZyntraRect) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).setViewport(.{ .x = viewport.x, .y = viewport.y, .w = viewport.w, .h = viewport.h }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Define a escala DPI da superfície: pixels de dispositivo por pixel
/// lógico (1 = 100%, 2 = 200%). Fator precisa ser finito e > 0.
pub export fn zyntra_context_set_scale(handle: ?*ZyntraContext, factor: f32) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    if (!std.math.isFinite(factor) or factor <= 0) return .invalid_argument;
    toCtx(h).setScale(.{ .factor = factor }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Lê a escala DPI vigente.
pub export fn zyntra_context_get_scale(handle: ?*ZyntraContext, out_factor: ?*f32) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_factor orelse return .invalid_argument;
    out.* = toCtx(h).scale.factor;
    return .ok;
}

/// Define o viewport a partir de um rect em pixels de DISPOSITIVO
/// (convertido para pixels lógicos pela escala vigente).
pub export fn zyntra_context_set_device_viewport(
    handle: ?*ZyntraContext,
    device_rect: ct.ZyntraRect,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).setDeviceViewport(toRect(device_rect)) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Movimento do mouse em pixels de DISPOSITIVO (convertido para
/// lógicos pela escala vigente).
pub export fn zyntra_context_push_device_mouse_move(
    handle: ?*ZyntraContext,
    pos: ct.ZyntraVec2,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).pushDeviceEvent(.{ .mouse_move = .{ .pos = toVec2(pos) } }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Botão do mouse em pixels de DISPOSITIVO.
pub export fn zyntra_context_push_device_mouse_button(
    handle: ?*ZyntraContext,
    button: u8,
    pressed: bool,
    pos: ct.ZyntraVec2,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const btn: event_mod.MouseButton = switch (button) {
        0 => .left,
        1 => .right,
        2 => .middle,
        else => return .invalid_argument,
    };
    toCtx(h).pushDeviceEvent(.{ .mouse_button = .{
        .button = btn,
        .pressed = pressed,
        .pos = toVec2(pos),
    } }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Roda do mouse em pixels de DISPOSITIVO.
pub export fn zyntra_context_push_device_mouse_wheel(
    handle: ?*ZyntraContext,
    dx: f32,
    dy: f32,
    pos: ct.ZyntraVec2,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).pushDeviceEvent(.{ .mouse_wheel = .{
        .dx = dx,
        .dy = dy,
        .pos = toVec2(pos),
    } }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

pub export fn zyntra_context_push_mouse_move(handle: ?*ZyntraContext, pos: ct.ZyntraVec2) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).pushEvent(.{ .mouse_move = .{ .pos = .{ .x = pos.x, .y = pos.y } } }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

pub export fn zyntra_context_push_mouse_button(
    handle: ?*ZyntraContext,
    button: u8,
    pressed: bool,
    pos: ct.ZyntraVec2,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const btn: event_mod.MouseButton = switch (button) {
        0 => .left,
        1 => .right,
        2 => .middle,
        else => return .invalid_argument,
    };
    toCtx(h).pushEvent(.{
        .mouse_button = .{ .button = btn, .pressed = pressed, .pos = .{ .x = pos.x, .y = pos.y } },
    }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Evento de roda: `dx`/`dy` em unidades de linha (o widget multiplica pela
/// velocidade configurada). Posição e deltas não-finitos ⇒
/// `ZYNTRA_INVALID_EVENT`.
pub export fn zyntra_context_push_mouse_wheel(
    handle: ?*ZyntraContext,
    dx: f32,
    dy: f32,
    pos: ct.ZyntraVec2,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).pushEvent(.{
        .mouse_wheel = .{ .dx = dx, .dy = dy, .pos = .{ .x = pos.x, .y = pos.y } },
    }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Tecla normalizada (`key` é um valor de `ZyntraKey`; `modifiers` usa as
/// máscaras `ZYNTRA_MOD_*`, bits reservados ⇒ inválido). Teclas vão para o
/// widget focado; widgets focáveis também tratam Tab para trocar de foco.
pub export fn zyntra_context_push_key(
    handle: ?*ZyntraContext,
    key: i32,
    pressed: bool,
    modifiers: u8,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const k = std.enums.fromInt(ct.ZyntraKey, key) orelse return .invalid_argument;
    if (modifiers & ~ct.key_modifiers_mask != 0) return .invalid_argument;
    toCtx(h).pushEvent(.{ .key = .{
        .key = @fromBackingInt(@intCast(@backingInt(k))),
        .pressed = pressed,
        .modifiers = @bitCast(modifiers),
    } }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Texto digitado: um codepoint Unicode por chamada (fora de
/// `0..0x10FFFF` ou substituto ⇒ `ZYNTRA_INVALID_EVENT`, como as posições
/// não-finitas dos eventos de mouse).
pub export fn zyntra_context_push_text(handle: ?*ZyntraContext, codepoint: u32) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).pushEvent(.{ .text = .{ .codepoint = codepoint } }) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

/// Coloca o foco no widget `id` (`0` limpa o foco) — teclado e Tab operam
/// sobre o focado.
pub export fn zyntra_context_focus(handle: ?*ZyntraContext, id: ct.ZyntraId) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    ctx.focus_owner = if (id == 0) null else id_mod.Id.fromU64(id);
    return .ok;
}

/// Informa se o widget `id` é o dono do foco neste momento.
pub export fn zyntra_context_has_focus(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    out_focused: ?*bool,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_focused orelse return .invalid_argument;
    out.* = toCtx(h).hasFocus(id_mod.Id.fromU64(id));
    return .ok;
}

pub export fn zyntra_context_push_quit(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).pushEvent(.quit) catch |err| {
        return mapErr(err);
    };
    return .ok;
}

pub export fn zyntra_context_pending_events(handle: ?*ZyntraContext, out_len: ?*usize) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_len orelse return .invalid_argument;
    out.* = toCtx(h).pendingEvents().len;
    return .ok;
}

/// Marca a região que mudou neste frame (une com o acumulado; rect vazio
/// é no-op). `begin_frame` limpa o acumulado.
pub export fn zyntra_context_mark_dirty(handle: ?*ZyntraContext, rect: ct.ZyntraRect) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).mark_dirty(toRect(rect));
    return .ok;
}

/// Zera a região suja acumulada (nada mais a repintar).
pub export fn zyntra_context_clear_dirty(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    toCtx(h).clear_dirty();
    return .ok;
}

/// Lê a região suja acumulada no frame atual (vazia quando nada mudou).
pub export fn zyntra_context_dirty_rect(handle: ?*ZyntraContext, out_rect: ?*ct.ZyntraRect) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_rect orelse return .invalid_argument;
    const r = toCtx(h).dirty_rect;
    out.* = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    return .ok;
}

pub export fn zyntra_draw_count(handle: ?*ZyntraContext, out_len: ?*usize) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_len orelse return .invalid_argument;
    out.* = toCtx(h).drawCommands().len;
    return .ok;
}

/// Limpa o viewport com cor sólida (normalmente o primeiro comando).
pub export fn zyntra_draw_clear(handle: ?*ZyntraContext, color: ct.ZyntraColor) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.clear(ctx.allocator, toColor(color)));
}

/// Define o clip retangular (scissor) para os comandos seguintes.
pub export fn zyntra_draw_clip(handle: ?*ZyntraContext, rect: ct.ZyntraRect) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.clip(ctx.allocator, toRect(rect)));
}

/// Remove o clip retangular (volta a desenhar no viewport inteiro).
pub export fn zyntra_draw_clip_reset(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.clip(ctx.allocator, null));
}

pub export fn zyntra_draw_rect_filled(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    color: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.rectFilled(ctx.allocator, toRect(rect), toColor(color)));
}

/// Moldura retangular de `thickness` px virada para dentro.
pub export fn zyntra_draw_rect_outline(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    color: ct.ZyntraColor,
    thickness: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.rectOutline(ctx.allocator, toRect(rect), toColor(color), thickness));
}

/// Reta de `thickness` px entre `p0` e `p1`.
pub export fn zyntra_draw_line(
    handle: ?*ZyntraContext,
    p0: ct.ZyntraVec2,
    p1: ct.ZyntraVec2,
    color: ct.ZyntraColor,
    thickness: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.line(
        ctx.allocator,
        toVec2(p0),
        toVec2(p1),
        toColor(color),
        thickness,
    ));
}

/// Reta tracejada entre `p0` e `p1`: `dash_len` px de traço alternando
/// com `gap_len` px de vazio.
pub export fn zyntra_draw_line_dashed(
    handle: ?*ZyntraContext,
    p0: ct.ZyntraVec2,
    p1: ct.ZyntraVec2,
    color: ct.ZyntraColor,
    thickness: f32,
    dash_len: f32,
    gap_len: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.lineDashed(
        ctx.allocator,
        toVec2(p0),
        toVec2(p1),
        toColor(color),
        thickness,
        dash_len,
        gap_len,
    ));
}

pub export fn zyntra_draw_circle_filled(
    handle: ?*ZyntraContext,
    center: ct.ZyntraVec2,
    radius: f32,
    color: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.circleFilled(ctx.allocator, toVec2(center), radius, toColor(color)));
}

/// Círculo com contorno de `thickness` px.
pub export fn zyntra_draw_circle_outline(
    handle: ?*ZyntraContext,
    center: ct.ZyntraVec2,
    radius: f32,
    color: ct.ZyntraColor,
    thickness: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.circleOutline(ctx.allocator, toVec2(center), radius, toColor(color), thickness));
}

/// Círculo tracejado: `dash_len` px ligados, `gap_len` px desligados.
pub export fn zyntra_draw_circle_dashed(
    handle: ?*ZyntraContext,
    center: ct.ZyntraVec2,
    radius: f32,
    color: ct.ZyntraColor,
    thickness: f32,
    dash_len: f32,
    gap_len: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.circleDashed(ctx.allocator, toVec2(center), radius, toColor(color), thickness, dash_len, gap_len));
}

/// Retângulo de cantos arredondados (`radius` clampado a `min(w,h)/2`);
/// o backend de referência usa SDF com bordas anti-serrilhadas.
pub export fn zyntra_draw_rect_rounded(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    radius: f32,
    color: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.rectRounded(ctx.allocator, toRect(rect), radius, toColor(color)));
}

/// Preenchimento em gradiente linear: `color0` em `p0`, `color1` em `p1`,
/// contido em `rect` (projeção no eixo clampada a [0,1]).
pub export fn zyntra_draw_rect_gradient(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    p0: ct.ZyntraVec2,
    p1: ct.ZyntraVec2,
    color0: ct.ZyntraColor,
    color1: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.rectGradient(
        ctx.allocator,
        toRect(rect),
        toVec2(p0),
        toVec2(p1),
        toColor(color0),
        toColor(color1),
    ));
}

/// Sombra projetada da silhueta arredondada `rect` (deslocada por `offset`,
/// atenuada em `blur` px). Não desenha a forma: desenhe-a por cima.
pub export fn zyntra_draw_rect_shadow(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    radius: f32,
    offset: ct.ZyntraVec2,
    blur: f32,
    color: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.rectShadow(
        ctx.allocator,
        toRect(rect),
        radius,
        toVec2(offset),
        blur,
        toColor(color),
    ));
}

/// Backdrop blur: desfoca o que JÁ foi desenhado dentro de `rect`
/// (ordem importa; `radius` < 0.5 é no-op).
pub export fn zyntra_draw_blur(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    radius: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    return pushDraw(ctx.draw.backdropBlur(ctx.allocator, toRect(rect), radius));
}

/// Enfileira texto UTF-8 com CÓPIA para a arena da DrawList: o chamador
/// pode liberar/reutilizar `utf8` logo após o retorno. `utf8_len == 0`
/// emite um run vazio válido (requer ponteiro qualquer, inclusive NULL).
/// `size` usa métricas fallback (`withSize`); backends com shaping
/// próprio medem de novo.
pub export fn zyntra_draw_text(
    handle: ?*ZyntraContext,
    pos: ct.ZyntraVec2,
    color: ct.ZyntraColor,
    size: f32,
    utf8: ?[*]const u8,
    utf8_len: usize,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const bytes: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const ctx = toCtx(h);
    ctx.pushText(
        .{ .x = pos.x, .y = pos.y },
        .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a },
        metrics_mod.FontMetrics.withSize(size),
        bytes,
    ) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
        error.InvalidCommand => return .invalid_command,
        error.InvalidUtf8 => return .invalid_text,
        error.InvalidMetrics => return .invalid_argument,
    };
    return .ok;
}

/// Mede um texto UTF-8 com as métricas fallback (`withSize`): devolve a
/// largura/altura em pixels lógicos. `utf8_len == 0` aceita ponteiro NULL
/// (texto vazio mede 0). Cópia nenhuma: só mede.
pub export fn zyntra_text_measure(
    utf8: ?[*]const u8,
    utf8_len: usize,
    size: f32,
    out_width: ?*f32,
    out_height: ?*f32,
) callconv(.c) ct.ZyntraResult {
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const w_out = out_width orelse return .invalid_argument;
    const h_out = out_height orelse return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const bytes: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const m = metrics_mod.measure(bytes, metrics_mod.FontMetrics.withSize(size)) catch |err| switch (err) {
        error.InvalidUtf8 => return .invalid_text,
        error.InvalidMetrics => return .invalid_argument,
    };
    w_out.* = m.width;
    h_out.* = m.height;
    return .ok;
}

/// Quantos bytes do início de `utf8` cabem em `max_width` (corte em
/// fronteira de codepoint; o resto é descartado pelo chamador).
pub export fn zyntra_text_truncate(
    utf8: ?[*]const u8,
    utf8_len: usize,
    size: f32,
    max_width: f32,
    out_bytes: ?*usize,
) callconv(.c) ct.ZyntraResult {
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (!std.math.isFinite(max_width) or max_width < 0) return .invalid_argument;
    const out = out_bytes orelse return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const bytes: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const kept = metrics_mod.truncateToWidth(bytes, metrics_mod.FontMetrics.withSize(size), max_width) catch |err| switch (err) {
        error.InvalidUtf8 => return .invalid_text,
        error.InvalidMetrics, error.InvalidArgument => return .invalid_argument,
    };
    out.* = kept;
    return .ok;
}

// ---------------------------------------------------------------------------
// Pixels: framebuffer de software e rasterização (M106)
// ---------------------------------------------------------------------------

/// Handle opaco do framebuffer de software (backend de referência). O
/// layout real (`software.raster.SoftwareFramebuffer`) nunca é exposto.
pub const ZyntraFramebuffer = opaque {};

const Fb = software_mod.SoftwareFramebuffer;

fn toFb(h: *ZyntraFramebuffer) *Fb {
    return @ptrCast(@alignCast(h));
}

fn checkFb(h: ?*ZyntraFramebuffer) !*ZyntraFramebuffer {
    return h orelse error.InvalidArgument;
}

fn mapRenderErr(err: anyerror) ct.ZyntraResult {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.InvalidCommand => .invalid_command,
        error.InvalidArgument => .invalid_argument,
        else => .invalid_state,
    };
}

/// Cria um framebuffer `width`×`height` em RGBA no `page_allocator`
/// interno. Dimensão 0 ou > 8192 ⇒ `ZYNTRA_INVALID_ARGUMENT`.
pub export fn zyntra_framebuffer_create(
    width: u32,
    height: u32,
    out_handle: ?*?*ZyntraFramebuffer,
) callconv(.c) ct.ZyntraResult {
    const out = out_handle orelse return .invalid_argument;
    const gpa = std.heap.page_allocator;
    const fb = gpa.create(Fb) catch return .out_of_memory;
    fb.* = Fb.init(gpa, width, height) catch |err| {
        gpa.destroy(fb);
        return switch (err) {
            error.OutOfMemory => .out_of_memory,
            error.InvalidArgument => .invalid_argument,
        };
    };
    out.* = @ptrCast(fb);
    return .ok;
}

/// Destrói o framebuffer (NULL é seguro).
pub export fn zyntra_framebuffer_destroy(handle: ?*ZyntraFramebuffer) callconv(.c) void {
    const h = handle orelse return;
    const fb = toFb(h);
    const gpa = std.heap.page_allocator;
    fb.deinit(gpa);
    gpa.destroy(fb);
}

/// Tamanho atual em pixels (útil quando o layout é dirigido por dados).
pub export fn zyntra_framebuffer_size(
    handle: ?*ZyntraFramebuffer,
    out_width: ?*u32,
    out_height: ?*u32,
) callconv(.c) ct.ZyntraResult {
    const h = checkFb(handle) catch return .invalid_argument;
    const w_out = out_width orelse return .invalid_argument;
    const h_out = out_height orelse return .invalid_argument;
    const fb = toFb(h);
    w_out.* = fb.w;
    h_out.* = fb.h;
    return .ok;
}

/// Preenche o framebuffer inteiro com `color` (source-over: alfa parcial
/// mistura com o que já está lá; alfa 0 é no-op).
pub export fn zyntra_framebuffer_fill(handle: ?*ZyntraFramebuffer, color: ct.ZyntraColor) callconv(.c) ct.ZyntraResult {
    const h = checkFb(handle) catch return .invalid_argument;
    const fb = toFb(h);
    fb.fillRect(.{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(fb.w),
        .h = @floatFromInt(fb.h),
    }, null, toColor(color));
    return .ok;
}

/// Lê um pixel em RGBA. Fora dos limites ⇒ `ZYNTRA_INVALID_ARGUMENT`.
pub export fn zyntra_framebuffer_pixel(
    handle: ?*ZyntraFramebuffer,
    x: u32,
    y: u32,
    out_color: ?*ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkFb(handle) catch return .invalid_argument;
    const out = out_color orelse return .invalid_argument;
    const fb = toFb(h);
    if (x >= fb.w or y >= fb.h) return .invalid_argument;
    const px = fb.get(x, y);
    out.* = .{ .r = px[0], .g = px[1], .b = px[2], .a = px[3] };
    return .ok;
}

/// Rasteriza a `DrawList` do frame atual no framebuffer, cobrindo o
/// viewport do contexto (clampado ao tamanho do framebuffer). `out_stats`
/// é opcional (contadores de submetidos/desenhados/cullados).
pub export fn zyntra_framebuffer_render(
    fb_handle: ?*ZyntraFramebuffer,
    ctx_handle: ?*ZyntraContext,
    out_stats: ?*ct.ZyntraRenderStats,
) callconv(.c) ct.ZyntraResult {
    const h = checkFb(fb_handle) catch return .invalid_argument;
    const ch = checkHandle(ctx_handle) catch return .invalid_argument;
    const fb = toFb(h);
    const ctx = toCtx(ch);
    const stats = software_mod.render(fb, ctx.drawCommands(), ctx.viewport) catch |err| return mapRenderErr(err);
    if (out_stats) |s| s.* = stats;
    return .ok;
}

/// Repintura parcial: rasteriza só a interseção de `region` com o
/// viewport (clampado ao framebuffer). O resto do framebuffer fica como
/// estava — o mesmo caminho do `render_region` da API Zig.
pub export fn zyntra_framebuffer_render_region(
    fb_handle: ?*ZyntraFramebuffer,
    ctx_handle: ?*ZyntraContext,
    region: ct.ZyntraRect,
    out_stats: ?*ct.ZyntraRenderStats,
) callconv(.c) ct.ZyntraResult {
    const h = checkFb(fb_handle) catch return .invalid_argument;
    const ch = checkHandle(ctx_handle) catch return .invalid_argument;
    const fb = toFb(h);
    const ctx = toCtx(ch);
    const stats = software_mod.renderRegion(fb, ctx.drawCommands(), ctx.viewport, toRect(region)) catch |err| return mapRenderErr(err);
    if (out_stats) |s| s.* = stats;
    return .ok;
}

// ---------------------------------------------------------------------------
// Métricas estendidas (M153)
// ---------------------------------------------------------------------------

/// Métricas estendidas do frame (M153): contadores por tipo de
/// comando, bytes de texto, glifos e crescimentos de buffer.
pub export fn zyntra_context_frame_metrics(
    handle: ?*ZyntraContext,
    out_metrics: ?*ct.ZyntraFrameMetrics,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_metrics orelse return .invalid_argument;
    const m = toCtx(h).frameMetrics();
    out.* = .{
        .commands_total = m.commands_total,
        .commands_visible = m.commands_visible,
        .commands_culled = m.commands_culled,
        .rects = m.rects,
        .texts = m.texts,
        .text_bytes = m.text_bytes,
        .images = m.images,
        .image_regions = m.image_regions,
        .glyph_runs = m.glyph_runs,
        .glyphs_total = m.glyphs_total,
        .dirty_rects = m.dirty_rects,
        .buffer_growths = m.buffer_growths,
    };
    return .ok;
}

/// Rasteriza o frame atual e devolve as métricas do rasterizador
/// (M153): contadores por caminho (rápido/genérico) e pixels escritos.
pub export fn zyntra_framebuffer_render_metrics(
    fb_handle: ?*ZyntraFramebuffer,
    ctx_handle: ?*ZyntraContext,
    out_stats: ?*ct.ZyntraRenderStats,
    out_metrics: ?*ct.ZyntraRasterMetrics,
) callconv(.c) ct.ZyntraResult {
    const h = checkFb(fb_handle) catch return .invalid_argument;
    const ch = checkHandle(ctx_handle) catch return .invalid_argument;
    const fb = toFb(h);
    const ctx = toCtx(ch);
    const stats = software_mod.render(fb, ctx.drawCommands(), ctx.viewport) catch |err| return mapRenderErr(err);
    if (out_stats) |s| s.* = stats;
    if (out_metrics) |m| m.* = .{
        .rect_fast_path = fb.metrics.rect_fast_path,
        .rect_generic_path = fb.metrics.rect_generic_path,
        .blit_fast_path = fb.metrics.blit_fast_path,
        .blit_generic_path = fb.metrics.blit_generic_path,
        .commands_drawn = fb.metrics.commands_drawn,
        .pixels_written = fb.metrics.pixels_written,
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Viewport 3D (M146): rasterizador em software + cena de cubos
// ---------------------------------------------------------------------------

/// Viewport 3D opaco: renderiza a cena num framebuffer interno (o app
/// apresenta os pixels com `zyntra_draw_image`). O handle é destruído
/// com `zyntra_vp3d_destroy`.
pub const ZyntraViewport3D = opaque {};

const Vp3DObject = struct {
    id: u32 = 0,
    center: vp3d_math.Vec3 = .{},
    size: f32 = 1,
    color: types_mod.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

const Vp3DState = struct {
    gpa: std.mem.Allocator,
    fb: software_mod.SoftwareFramebuffer,
    raster: vp3d_raster.Rasterizer,
    cam: vp3d_camera.Camera = .{},
    objects: std.ArrayList(Vp3DObject) = .empty,
    width: u32 = 0,
    height: u32 = 0,

    fn deinit(self: *Vp3DState) void {
        self.objects.deinit(self.gpa);
        self.raster.deinit();
        self.fb.deinit(self.gpa);
    }

    fn aspect(self: *const Vp3DState) f32 {
        if (self.width == 0 or self.height == 0) return 1;
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }

    /// (re)aponta o rasterizador para o framebuffer interno.
    fn bindTarget(self: *Vp3DState) void {
        self.raster.setTarget(.{
            .pixels = self.fb.pixels,
            .width = self.fb.w,
            .height = self.fb.h,
            .stride = self.fb.w * 4,
        }) catch {};
    }
};

fn toVp3D(h: *ZyntraViewport3D) *Vp3DState {
    return @ptrCast(@alignCast(h));
}

/// Cria um viewport 3D (`width`×`height` em pixels).
pub export fn zyntra_vp3d_create(
    width: u32,
    height: u32,
    out: ?*?*ZyntraViewport3D,
) callconv(.c) ct.ZyntraResult {
    const o = out orelse return .invalid_argument;
    if (width == 0 or height == 0) return .invalid_argument;
    const gpa = std.heap.page_allocator;
    const state = gpa.create(Vp3DState) catch return .out_of_memory;
    errdefer gpa.destroy(state);
    state.* = undefined;
    state.gpa = gpa;
    state.width = width;
    state.height = height;
    state.cam = .{}; // câmera padrão (o app ajusta com zyntra_vp3d_camera)
    state.objects = .empty;
    state.fb = software_mod.SoftwareFramebuffer.init(gpa, width, height) catch return .out_of_memory;
    errdefer state.fb.deinit(gpa);
    state.raster = vp3d_raster.Rasterizer.init(gpa, width, height) catch return .out_of_memory;
    errdefer state.raster.deinit();
    state.bindTarget();
    o.* = @ptrCast(state);
    return .ok;
}

/// Destrói o viewport 3D (libera o framebuffer e a cena).
pub export fn zyntra_vp3d_destroy(vp: ?*ZyntraViewport3D) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    const gpa = std.heap.page_allocator;
    const state = toVp3D(h);
    state.deinit();
    gpa.destroy(state);
    return .ok;
}

/// Redimensiona o viewport (o framebuffer é recriado).
pub export fn zyntra_vp3d_resize(
    vp: ?*ZyntraViewport3D,
    width: u32,
    height: u32,
) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    if (width == 0 or height == 0) return .invalid_argument;
    const state = toVp3D(h);
    state.fb.deinit(state.gpa);
    state.fb = software_mod.SoftwareFramebuffer.init(state.gpa, width, height) catch return .out_of_memory;
    state.raster.deinit();
    state.raster = vp3d_raster.Rasterizer.init(state.gpa, width, height) catch return .out_of_memory;
    state.bindTarget();
    state.width = width;
    state.height = height;
    return .ok;
}

/// Define a câmera (distância, órbita em Y e X, alvo).
pub export fn zyntra_vp3d_camera(
    vp: ?*ZyntraViewport3D,
    distance: f32,
    yaw: f32,
    pitch: f32,
    target_x: f32,
    target_y: f32,
    target_z: f32,
) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    const state = toVp3D(h);
    if (!std.math.isFinite(distance) or !std.math.isFinite(yaw) or !std.math.isFinite(pitch) or
        !std.math.isFinite(target_x) or !std.math.isFinite(target_y) or !std.math.isFinite(target_z))
    {
        return .invalid_argument;
    }
    if (distance <= 0) return .invalid_argument;
    state.cam.distance = distance;
    state.cam.yaw = yaw;
    state.cam.pitch = pitch;
    state.cam.target = .{ .x = target_x, .y = target_y, .z = target_z };
    if (!state.cam.isValid()) return .invalid_argument;
    return .ok;
}

/// Orbita a câmera (delta em radianos).
pub export fn zyntra_vp3d_orbit(
    vp: ?*ZyntraViewport3D,
    d_yaw: f32,
    d_pitch: f32,
) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    toVp3D(h).cam.orbit(d_yaw, d_pitch);
    return .ok;
}

/// Aproxima/afasta a câmera (`delta > 0` afasta).
pub export fn zyntra_vp3d_zoom(
    vp: ?*ZyntraViewport3D,
    delta: f32,
) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    toVp3D(h).cam.zoom(delta);
    return .ok;
}

/// Adiciona um objeto (um cubo) à cena.
pub export fn zyntra_vp3d_add_object(
    vp: ?*ZyntraViewport3D,
    id: u32,
    x: f32,
    y: f32,
    z: f32,
    size: f32,
    r: u8,
    g: u8,
    b: u8,
) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    const state = toVp3D(h);
    if (!std.math.isFinite(x) or !std.math.isFinite(y) or !std.math.isFinite(z) or
        !std.math.isFinite(size) or size <= 0)
    {
        return .invalid_argument;
    }
    state.objects.append(state.gpa, .{
        .id = id,
        .center = .{ .x = x, .y = y, .z = z },
        .size = size,
        .color = .{ .r = r, .g = g, .b = b, .a = 255 },
    }) catch return .out_of_memory;
    return .ok;
}

/// Limpa a cena.
pub export fn zyntra_vp3d_clear_objects(vp: ?*ZyntraViewport3D) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    toVp3D(h).objects.clearRetainingCapacity();
    return .ok;
}

/// Renderiza a cena no framebuffer interno (grade + eixos + objetos).
pub export fn zyntra_vp3d_render(vp: ?*ZyntraViewport3D) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    const state = toVp3D(h);
    const aspect = state.aspect();
    state.raster.clear(.{ .r = 12, .g = 14, .b = 20, .a = 255 });
    vp3d_grid.drawGrid(&state.raster, state.cam, aspect, .{ .spacing = 1.0, .extent = 6 });
    vp3d_grid.drawAxes(&state.raster, state.cam, aspect, .{ .length = 1.5 });
    for (state.objects.items) |obj| {
        var cube = vp3d_mesh.CubeMesh.init(obj.size);
        state.raster.drawMesh(
            cube.mesh(),
            vp3d_math.Mat4.translation(obj.center),
            state.cam,
            aspect,
            .{ .color = obj.color, .backface_culling = true },
        );
    }
    return .ok;
}

/// Pica o objeto sob a posição de tela (em pixels do viewport).
/// `out_id` recebe 0 quando não há objeto.
pub export fn zyntra_vp3d_pick(
    vp: ?*ZyntraViewport3D,
    screen_x: f32,
    screen_y: f32,
    out_id: ?*u32,
) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    const out = out_id orelse return .invalid_argument;
    const state = toVp3D(h);
    if (!std.math.isFinite(screen_x) or !std.math.isFinite(screen_y)) return .invalid_argument;
    out.* = 0;
    const mvp = state.cam.viewProjection(state.aspect()) orelse return .ok;
    const ray = vp3d_pick.screenRay(mvp, screen_x, screen_y, state.width, state.height) orelse return .ok;
    var best: ?vp3d_pick.Hit = null;
    for (state.objects.items) |obj| {
        var cube = vp3d_mesh.CubeMesh.init(obj.size);
        const hit = vp3d_pick.pickMesh(
            ray,
            cube.mesh(),
            vp3d_math.Mat4.translation(obj.center),
            obj.id,
            true,
        ) orelse continue;
        if (best) |b| {
            if (hit.distance >= b.distance) continue;
        }
        best = hit;
    }
    if (best) |b| out.* = b.id;
    return .ok;
}

/// Os pixels do viewport (RGBA8, emprestados): o app apresenta com
/// `zyntra_draw_image`.
pub export fn zyntra_vp3d_pixels(
    vp: ?*ZyntraViewport3D,
    out_pixels: ?*[*]const u8,
    out_width: ?*u32,
    out_height: ?*u32,
    out_stride: ?*u32,
) callconv(.c) ct.ZyntraResult {
    const h = vp orelse return .invalid_argument;
    const p = out_pixels orelse return .invalid_argument;
    const w = out_width orelse return .invalid_argument;
    const hh = out_height orelse return .invalid_argument;
    const st = out_stride orelse return .invalid_argument;
    const state = toVp3D(h);
    p.* = @as([*]const u8, @ptrCast(state.fb.pixels.ptr));
    w.* = state.fb.w;
    hh.* = state.fb.h;
    st.* = state.fb.w * 4;
    return .ok;
}

/// Calcula o rect de destino e a região de origem de uma imagem nos
/// modos de ajuste: 0 = stretch, 1 = contain, 2 = cover, 3 = none.
pub export fn zyntra_image_fit_rect(
    bounds: ct.ZyntraRect,
    img_w: u32,
    img_h: u32,
    mode: i32,
    out_dest: ?*ct.ZyntraRect,
    out_src_x: ?*u32,
    out_src_y: ?*u32,
    out_src_w: ?*u32,
    out_src_h: ?*u32,
) callconv(.c) ct.ZyntraResult {
    const dest = out_dest orelse return .invalid_argument;
    const sx = out_src_x orelse return .invalid_argument;
    const sy = out_src_y orelse return .invalid_argument;
    const sw = out_src_w orelse return .invalid_argument;
    const sh = out_src_h orelse return .invalid_argument;
    if (img_w == 0 or img_h == 0) return .invalid_argument;
    const fit: image_widget_mod.Fit = switch (mode) {
        0 => .stretch,
        1 => .contain,
        2 => .cover,
        3 => .none,
        else => return .invalid_argument,
    };
    const place = image_widget_mod.fitRectSize(toRect(bounds), img_w, img_h, fit);
    dest.* = fromRect(place.dest);
    sx.* = place.src.x;
    sy.* = place.src.y;
    sw.* = place.src.w;
    sh.* = place.src.h;
    return .ok;
}

// ---------------------------------------------------------------------------
// Caminhos vetoriais (M161)
// ---------------------------------------------------------------------------

/// Preenche ou traça um caminho vetorial.
///
/// `points` são os pontos (em pixels lógicos) e `contours` dizem quais
/// faixas formam cada contorno (aberto ou fechado). `thickness` 0 =
/// preenchimento, > 0 = traço com essa espessura. `rule` 0 = nonzero,
/// 1 = evenodd; `join` 0 = miter, 1 = round, 2 = bevel; `cap` 0 = butt,
/// 1 = round, 2 = square.
///
/// Os pontos são COPIADOS pelo comando (o app pode liberar o buffer
/// depois da chamada).
pub export fn zyntra_draw_path(
    handle: ?*ZyntraContext,
    points: ?[*]const ct.ZyntraVec2,
    point_count: u32,
    contours: ?[*]const ct.ZyntraPathContour,
    contour_count: u32,
    color: ct.ZyntraColor,
    thickness: f32,
    rule: i32,
    join: i32,
    cap: i32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    if (point_count == 0) return .invalid_argument;
    const pts_ptr = points orelse return .invalid_argument;
    const fill_rule = switch (rule) {
        0 => path_mod.FillRule.nonzero,
        1 => path_mod.FillRule.evenodd,
        else => return .invalid_argument,
    };
    const stroke_join = switch (join) {
        0 => path_mod.StrokeJoin.miter,
        1 => path_mod.StrokeJoin.round,
        2 => path_mod.StrokeJoin.bevel,
        else => return .invalid_argument,
    };
    const stroke_cap = switch (cap) {
        0 => path_mod.StrokeCap.butt,
        1 => path_mod.StrokeCap.round,
        2 => path_mod.StrokeCap.square,
        else => return .invalid_argument,
    };
    if (!std.math.isFinite(thickness) or thickness < 0) return .invalid_argument;

    // Converte para a geometria interna (cópia temporária).
    const gpa = std.heap.page_allocator;
    const pts = gpa.alloc(types_mod.Vec2, point_count) catch return .out_of_memory;
    defer gpa.free(pts);
    for (pts, 0..) |*p, i| {
        const src = pts_ptr[i];
        if (!std.math.isFinite(src.x) or !std.math.isFinite(src.y)) return .invalid_argument;
        p.* = .{ .x = src.x, .y = src.y };
    }
    var ranges: []path_mod.ContourRange = &.{};
    defer if (ranges.len != 0) gpa.free(ranges);
    if (contour_count > 0) {
        const cont_ptr = contours orelse return .invalid_argument;
        ranges = gpa.alloc(path_mod.ContourRange, contour_count) catch return .out_of_memory;
        for (ranges, 0..) |*r, i| {
            const src = cont_ptr[i];
            if (src.len < 2) return .invalid_argument;
            if (src.start + src.len > point_count) return .invalid_argument;
            r.* = .{
                .start = src.start,
                .len = src.len,
                .closed = src.closed != 0,
            };
        }
    }
    const flat = path_mod.Flat{ .points = pts, .contours = ranges };
    return pushDraw(ctx.draw.path(
        ctx.allocator,
        flat,
        toColor(color),
        thickness,
        fill_rule,
        stroke_join,
        stroke_cap,
    ));
}

/// Path SVG analisado e achatado (buffers próprios).
const SvgPath = struct {
    segments: []path_mod.Segment = &.{},
    points: []types_mod.Vec2 = &.{},
    contours: []path_mod.ContourRange = &.{},
    flat: path_mod.Flat = .{},

    fn deinit(self: *SvgPath, gpa: std.mem.Allocator) void {
        if (self.segments.len != 0) gpa.free(self.segments);
        if (self.points.len != 0) gpa.free(self.points);
        if (self.contours.len != 0) gpa.free(self.contours);
        self.* = .{};
    }
};

/// Analisa e achata um path SVG (aloca os buffers; o chamador libera
/// com `SvgPath.deinit`). Devolve null se o path é inválido.
fn loadSvg(gpa: std.mem.Allocator, text: []const u8) ?SvgPath {
    var out = SvgPath{};
    // Segmentos: uma estimativa generosa (2 por caractere).
    const seg_cap = @max(16, text.len * 2);
    out.segments = gpa.alloc(path_mod.Segment, seg_cap) catch return null;
    const builder = svg_mod.parsePath(text, out.segments) catch {
        out.deinit(gpa);
        return null;
    };
    // Achatamento: os buffers crescem até caber.
    var point_cap: usize = 64;
    var range_cap: usize = 16;
    out.points = gpa.alloc(types_mod.Vec2, point_cap) catch {
        out.deinit(gpa);
        return null;
    };
    out.contours = gpa.alloc(path_mod.ContourRange, range_cap) catch {
        out.deinit(gpa);
        return null;
    };
    while (true) {
        const res = path_mod.flatten(builder.segments(), 0.25, out.points, out.contours);
        if (res) |ok| {
            out.flat = ok;
            break;
        } else |err| switch (err) {
            error.InvalidArgument => {
                out.deinit(gpa);
                return null;
            },
            error.NoSpaceLeft => {
                if (point_cap > 1 << 20 or range_cap > 1 << 16) {
                    out.deinit(gpa);
                    return null;
                }
                point_cap *= 2;
                range_cap *= 2;
                const new_points = gpa.alloc(types_mod.Vec2, point_cap) catch {
                    out.deinit(gpa);
                    return null;
                };
                gpa.free(out.points);
                out.points = new_points;
                const new_contours = gpa.alloc(path_mod.ContourRange, range_cap) catch {
                    out.deinit(gpa);
                    return null;
                };
                gpa.free(out.contours);
                out.contours = new_contours;
            },
        }
    }
    return out;
}

/// Desenha um path SVG ("M 0 0 L 10 10 Z"): a string é analisada,
/// achatada e desenhada (mesmos parâmetros de `zyntra_draw_path`).
/// A string é lida durante a chamada (o app pode liberá-la depois).
pub export fn zyntra_draw_svg_path(
    handle: ?*ZyntraContext,
    svg: ?[*]const u8,
    svg_len: u32,
    color: ct.ZyntraColor,
    thickness: f32,
    rule: i32,
    join: i32,
    cap: i32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    const text_ptr = svg orelse return .invalid_argument;
    if (svg_len == 0) return .invalid_argument;
    if (!std.math.isFinite(thickness) or thickness < 0) return .invalid_argument;
    const fill_rule = switch (rule) {
        0 => path_mod.FillRule.nonzero,
        1 => path_mod.FillRule.evenodd,
        else => return .invalid_argument,
    };
    const stroke_join = switch (join) {
        0 => path_mod.StrokeJoin.miter,
        1 => path_mod.StrokeJoin.round,
        2 => path_mod.StrokeJoin.bevel,
        else => return .invalid_argument,
    };
    const stroke_cap = switch (cap) {
        0 => path_mod.StrokeCap.butt,
        1 => path_mod.StrokeCap.round,
        2 => path_mod.StrokeCap.square,
        else => return .invalid_argument,
    };
    const text = text_ptr[0..svg_len];
    const gpa = std.heap.page_allocator;
    var svg_path = loadSvg(gpa, text) orelse return .invalid_argument;
    defer svg_path.deinit(gpa);
    return pushDraw(ctx.draw.path(
        ctx.allocator,
        svg_path.flat,
        toColor(color),
        thickness,
        fill_rule,
        stroke_join,
        stroke_cap,
    ));
}

/// Desenha um path SVG TRANSFORMADO (escala uniforme `factor` +
/// deslocamento (`dx`, `dy`)) — é o que permite encaixar um ícone no
/// rect (veja `zyntra_svg_path_bounds`).
pub export fn zyntra_draw_svg_path_transformed(
    handle: ?*ZyntraContext,
    svg: ?[*]const u8,
    svg_len: u32,
    color: ct.ZyntraColor,
    thickness: f32,
    rule: i32,
    join: i32,
    cap: i32,
    factor: f32,
    dx: f32,
    dy: f32,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    const text_ptr = svg orelse return .invalid_argument;
    if (svg_len == 0) return .invalid_argument;
    if (!std.math.isFinite(thickness) or thickness < 0) return .invalid_argument;
    if (!std.math.isFinite(factor) or factor <= 0) return .invalid_argument;
    if (!std.math.isFinite(dx) or !std.math.isFinite(dy)) return .invalid_argument;
    const fill_rule = switch (rule) {
        0 => path_mod.FillRule.nonzero,
        1 => path_mod.FillRule.evenodd,
        else => return .invalid_argument,
    };
    const stroke_join = switch (join) {
        0 => path_mod.StrokeJoin.miter,
        1 => path_mod.StrokeJoin.round,
        2 => path_mod.StrokeJoin.bevel,
        else => return .invalid_argument,
    };
    const stroke_cap = switch (cap) {
        0 => path_mod.StrokeCap.butt,
        1 => path_mod.StrokeCap.round,
        2 => path_mod.StrokeCap.square,
        else => return .invalid_argument,
    };
    const gpa = std.heap.page_allocator;
    var svg_path = loadSvg(gpa, text_ptr[0..svg_len]) orelse return .invalid_argument;
    defer svg_path.deinit(gpa);
    return pushDraw(ctx.draw.pathTransformed(
        ctx.allocator,
        svg_path.flat,
        toColor(color),
        thickness,
        fill_rule,
        stroke_join,
        stroke_cap,
        factor,
        dx,
        dy,
    ));
}

/// A caixa (bbox) do path SVG — o app usa para encaixar o ícone no
/// rect (mesma conta do modo `contain`).
pub export fn zyntra_svg_path_bounds(
    svg: ?[*]const u8,
    svg_len: u32,
    out_x: ?*f32,
    out_y: ?*f32,
    out_w: ?*f32,
    out_h: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const text_ptr = svg orelse return .invalid_argument;
    if (svg_len == 0) return .invalid_argument;
    const x = out_x orelse return .invalid_argument;
    const y = out_y orelse return .invalid_argument;
    const w = out_w orelse return .invalid_argument;
    const h = out_h orelse return .invalid_argument;
    const gpa = std.heap.page_allocator;
    var svg_path = loadSvg(gpa, text_ptr[0..svg_len]) orelse return .invalid_argument;
    defer svg_path.deinit(gpa);
    const b = svg_path.flat.bounds();
    x.* = b.x;
    y.* = b.y;
    w.* = b.w;
    h.* = b.h;
    return .ok;
}

// Widgets: primeira superfície C (M107)
// ---------------------------------------------------------------------------

/// Deriva um id estável do hash FNV-1a 64 da string (`utf8_len == 0` ou
/// ponteiro NULL ⇒ id nulo, que os widgets rejeitam com
/// `ZYNTRA_INVALID_ARGUMENT`).
pub export fn zyntra_id_from_string(utf8: ?[*]const u8, utf8_len: usize) callconv(.c) ct.ZyntraId {
    if (utf8_len == 0 or utf8 == null) return 0;
    return id_mod.Id.fromString(utf8.?[0..utf8_len]).value();
}

/// Deriva um id filho do pai (itens de lista/tabela/árvore, subwidgets).
/// Pai nulo ⇒ nulo (não inventa um id a partir do nada); os widgets
/// rejeitam o `0` com `ZYNTRA_INVALID_ARGUMENT`.
pub export fn zyntra_id_child(parent: ct.ZyntraId, index: u32) callconv(.c) ct.ZyntraId {
    if (parent == 0) return 0;
    return id_mod.Id.fromU64(parent).child(index).value();
}

fn themeOf(kind: i32) ?style_mod.Theme {
    const k = std.enums.fromInt(ct.ZyntraThemeKind, kind) orelse return null;
    return switch (k) {
        .dark => style_mod.Theme.darkDefault(),
        .light => style_mod.Theme.lightDefault(),
    };
}

fn toOrientation(v: i32) ?separator_mod.SeparatorOrientation {
    const o = std.enums.fromInt(ct.ZyntraOrientation, v) orelse return null;
    return switch (o) {
        .horizontal => .horizontal,
        .vertical => .vertical,
    };
}

/// Mapeia os error sets dos widgets (o C não vê error unions;
/// `invalid_state` cobre o resto).
fn mapWidgetErr(err: anyerror) ct.ZyntraResult {
    return switch (err) {
        error.InvalidUtf8 => .invalid_text,
        error.InvalidMetrics => .invalid_argument,
        else => mapRenderErr(err),
    };
}

/// Cores base do tema embutido (`kind`: `ZYNTRA_THEME_DARK`/`ZYNTRA_THEME_LIGHT`).
pub export fn zyntra_theme_colors(
    kind: i32,
    out_colors: ?*ct.ZyntraThemeColors,
) callconv(.c) ct.ZyntraResult {
    const out = out_colors orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = .{
        .bg = fromColor(t.bg),
        .surface = fromColor(t.surface),
        .text = fromColor(t.text),
        .accent = fromColor(t.accent),
        .border = fromColor(t.border),
    };
    return .ok;
}

/// Estilo de botão do tema embutido (mutável pelo chamador antes do uso).
pub export fn zyntra_style_button(kind: i32, out_style: ?*ct.ZyntraButtonStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.buttonStyle();
    return .ok;
}

pub export fn zyntra_style_checkbox(kind: i32, out_style: ?*ct.ZyntraCheckboxStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.checkboxStyle();
    return .ok;
}

pub export fn zyntra_style_switch(kind: i32, out_style: ?*ct.ZyntraSwitchStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.switchStyle();
    return .ok;
}

pub export fn zyntra_style_slider(kind: i32, out_style: ?*ct.ZyntraSliderStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.sliderStyle();
    return .ok;
}

pub export fn zyntra_style_progress(kind: i32, out_style: ?*ct.ZyntraProgressStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.progressStyle();
    return .ok;
}

pub export fn zyntra_style_separator(kind: i32, out_style: ?*ct.ZyntraSeparatorStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.separatorStyle();
    return .ok;
}

/// Rótulo de texto (`utf8` é emprestado só na chamada — a `DrawList` copia).
/// `out_result` é opcional (métricas + `truncated`).
pub export fn zyntra_widget_label(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    color: ct.ZyntraColor,
    size: f32,
    utf8: ?[*]const u8,
    utf8_len: usize,
    debug_draw: bool,
    out_result: ?*ct.ZyntraLabelResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const bytes: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const res = label_mod.label(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        bytes,
        toColor(color),
        metrics_mod.FontMetrics.withSize(size),
        debug_draw,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .metrics = res.metrics, .truncated = res.truncated };
    return .ok;
}

/// Botão (a caixa; o rótulo é um `zyntra_widget_label` por cima, como na
/// API Zig). `out_result` é opcional (`hovered`/`pressed`/`clicked`).
pub export fn zyntra_widget_button(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    style: ?*const ct.ZyntraButtonStyle,
    out_result: ?*ct.ZyntraButtonResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const res = button_mod.button(toCtx(h), id_mod.Id.fromU64(id), toRect(bounds), st.*) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .hovered = res.hovered, .pressed = res.pressed, .clicked = res.clicked };
    return .ok;
}

/// Caixa de seleção: `checked` é do chamador (lida e alternada pelo widget).
pub export fn zyntra_widget_checkbox(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    checked: ?*bool,
    style: ?*const ct.ZyntraCheckboxStyle,
    out_result: ?*ct.ZyntraCheckboxResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const chk = checked orelse return .invalid_argument;
    const res = checkbox_mod.checkbox(toCtx(h), id_mod.Id.fromU64(id), toRect(bounds), chk, st.*) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .hovered = res.hovered, .toggled = res.toggled, .checked = res.checked };
    return .ok;
}

/// Interruptor liga/desliga (mesmo modelo de estado do `checkbox`).
pub export fn zyntra_widget_switch(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    checked: ?*bool,
    style: ?*const ct.ZyntraSwitchStyle,
    out_result: ?*ct.ZyntraSwitchResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const chk = checked orelse return .invalid_argument;
    const res = switch_mod.beginSwitch(toCtx(h), id_mod.Id.fromU64(id), toRect(bounds), chk, st.*) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .hovered = res.hovered,
        .toggled = res.toggled,
        .checked = res.checked,
        .focused = res.focused,
    };
    return .ok;
}

/// Controle deslizante: `value` é do chamador (lido, preso a `[min, max]` e
/// alterado pelo arraste/teclado).
pub export fn zyntra_widget_slider(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    value: ?*f32,
    min: f32,
    max: f32,
    style: ?*const ct.ZyntraSliderStyle,
    out_result: ?*ct.ZyntraSliderResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const v = value orelse return .invalid_argument;
    const res = slider_mod.slider(toCtx(h), id_mod.Id.fromU64(id), toRect(bounds), v, min, max, st.*) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .value = res.value,
        .changed = res.changed,
        .hovered = res.hovered,
        .dragging = res.dragging,
    };
    return .ok;
}

/// Barra de progresso (sem id, sem interação: só desenha `frac` em [0, 1]).
pub export fn zyntra_widget_progress(
    handle: ?*ZyntraContext,
    bounds: ct.ZyntraRect,
    frac: f32,
    style: ?*const ct.ZyntraProgressStyle,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    progress_mod.progress(toCtx(h), toRect(bounds), frac, st.*) catch |err| return mapWidgetErr(err);
    return .ok;
}

/// Separador (sem id): linha centralizada em `bounds`, horizontal ou
/// vertical conforme `orientation`.
pub export fn zyntra_widget_separator(
    handle: ?*ZyntraContext,
    bounds: ct.ZyntraRect,
    orientation: i32,
    style: ?*const ct.ZyntraSeparatorStyle,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const o = toOrientation(orientation) orelse return .invalid_argument;
    separator_mod.separator(toCtx(h), toRect(bounds), o, st.*) catch |err| return mapWidgetErr(err);
    return .ok;
}

// ---------------------------------------------------------------------------
// Widgets com listas de strings e painel (M108)
// ---------------------------------------------------------------------------

/// Tamanho de fonte dos widgets que não recebem `size` do chamador (o mesmo
/// da API Zig: abas e itens de lista usam `withSize(10)`).
const widget_font_size: f32 = 10;

/// Fatia de texto emprestada -> `[]const u8` (`len == 0` aceita `ptr` nulo).
/// `null` = ponteiro nulo com `len > 0` (`invalid_argument`).
fn strOf(s: ct.ZyntraStr) ?[]const u8 {
    if (s.len == 0) return &.{};
    const p = s.ptr orelse return null;
    return p[0..s.len];
}

/// Buffer de `T` apoiado em scratch da pilha do chamador: usa o scratch
/// quando cabe (caminho comum, sem alocação) e o alocador do contexto caso
/// contrário, liberando no `deinit`.
fn Buf(comptime T: type) type {
    return struct {
        slice: []T = &.{},
        owned: ?[]T = null,
        allocator: std.mem.Allocator = undefined,

        fn init(allocator: std.mem.Allocator, count: usize, scratch: []T) error{OutOfMemory}!@This() {
            if (count <= scratch.len) return .{ .slice = scratch[0..count] };
            const buf = try allocator.alloc(T, count);
            return .{ .slice = buf, .owned = buf, .allocator = allocator };
        }

        fn deinit(self: @This()) void {
            if (self.owned) |buf| self.allocator.free(buf);
        }
    };
}

/// Lista de `ZyntraStr` convertida para as fatias Zig que os widgets esperam.
const StrList = struct {
    items: []const []const u8 = &.{},
    buf: Buf([]const u8) = .{},

    fn deinit(self: StrList) void {
        self.buf.deinit();
    }
};

fn strListOf(
    allocator: std.mem.Allocator,
    src: ?[*]const ct.ZyntraStr,
    count: usize,
    scratch: [][]const u8,
) error{ InvalidArgument, OutOfMemory }!StrList {
    if (count == 0) return .{};
    const in = src orelse return error.InvalidArgument;
    var buf = try Buf([]const u8).init(allocator, count, scratch);
    errdefer buf.deinit();
    for (buf.slice, 0..) |*slot, i| {
        slot.* = strOf(in[i]) orelse return error.InvalidArgument;
    }
    return .{ .items = buf.slice, .buf = buf };
}

/// Itens de menu convertidos para os `MenuItem` da API Zig.
const MenuList = struct {
    items: []const menu_mod.MenuItem = &.{},
    buf: Buf(menu_mod.MenuItem) = .{},

    fn deinit(self: MenuList) void {
        self.buf.deinit();
    }
};

fn menuListOf(
    allocator: std.mem.Allocator,
    src: ?[*]const ct.ZyntraMenuItem,
    count: usize,
    scratch: []menu_mod.MenuItem,
) error{ InvalidArgument, OutOfMemory }!MenuList {
    if (count == 0) return .{};
    const in = src orelse return error.InvalidArgument;
    var buf = try Buf(menu_mod.MenuItem).init(allocator, count, scratch);
    errdefer buf.deinit();
    for (buf.slice, 0..) |*slot, i| {
        const it = in[i];
        slot.* = .{
            .label = strOf(it.label) orelse return error.InvalidArgument,
            .shortcut = if (it.shortcut.len == 0) null else (strOf(it.shortcut) orelse return error.InvalidArgument),
            .enabled = it.enabled,
            .separator = it.separator,
            .checked = if (it.has_checked) it.checked else null,
        };
    }
    return .{ .items = buf.slice, .buf = buf };
}

/// Colunas, linhas e células da tabela convertidas para os tipos da API Zig.
const TableArgs = struct {
    columns: []const table_mod.TableColumn = &.{},
    rows: []const table_mod.TableRow = &.{},
    buf_columns: Buf(table_mod.TableColumn) = .{},
    buf_rows: Buf(table_mod.TableRow) = .{},
    buf_cells: Buf([]const u8) = .{},

    fn deinit(self: TableArgs) void {
        self.buf_columns.deinit();
        self.buf_rows.deinit();
        self.buf_cells.deinit();
    }
};

fn tableArgsOf(
    allocator: std.mem.Allocator,
    columns: ?[*]const ct.ZyntraTableColumn,
    columns_len: usize,
    rows: ?[*]const ct.ZyntraTableRow,
    rows_len: usize,
    scratch_columns: []table_mod.TableColumn,
    scratch_rows: []table_mod.TableRow,
    scratch_cells: [][]const u8,
) error{ InvalidArgument, OutOfMemory }!TableArgs {
    if (columns_len == 0) return error.InvalidArgument;
    const in_columns = columns orelse return error.InvalidArgument;
    const in_rows: ?[*]const ct.ZyntraTableRow = if (rows_len == 0) null else (rows orelse return error.InvalidArgument);
    var total_cells: usize = 0;
    if (in_rows) |rs| {
        for (rs[0..rows_len]) |r| {
            total_cells = std.math.add(usize, total_cells, r.cells_len) catch return error.InvalidArgument;
        }
    }

    var columns_buf = try Buf(table_mod.TableColumn).init(allocator, columns_len, scratch_columns);
    errdefer columns_buf.deinit();
    var rows_buf = try Buf(table_mod.TableRow).init(allocator, rows_len, scratch_rows);
    errdefer rows_buf.deinit();
    var cells_buf = try Buf([]const u8).init(allocator, total_cells, scratch_cells);
    errdefer cells_buf.deinit();

    for (columns_buf.slice, 0..) |*slot, i| {
        const c = in_columns[i];
        slot.* = .{ .title = strOf(c.title) orelse return error.InvalidArgument, .width = c.width };
    }
    var at: usize = 0;
    if (in_rows) |rs| {
        for (rows_buf.slice, 0..) |*slot, i| {
            const r = rs[i];
            const cells = cells_buf.slice[at .. at + r.cells_len];
            at += r.cells_len;
            if (r.cells_len > 0) {
                const in_cells = r.cells orelse return error.InvalidArgument;
                for (cells, 0..) |*cslot, j| {
                    cslot.* = strOf(in_cells[j]) orelse return error.InvalidArgument;
                }
            }
            slot.* = .{ .cells = cells };
        }
    }
    return .{
        .columns = columns_buf.slice,
        .rows = rows_buf.slice,
        .buf_columns = columns_buf,
        .buf_rows = rows_buf,
        .buf_cells = cells_buf,
    };
}

/// Limites defensivos da árvore convertida: cortam recursão infinita
/// (ciclos vindos da fronteira C) e profundidade absurda.
const tree_max_nodes: usize = 1 << 16;
const tree_max_depth: usize = 128;

/// Conta os nós da subárvore de `in` (recursivo, com limites).
fn treeCount(in: [*]ct.ZyntraTreeItem, count: usize, depth: usize, total: *usize) error{InvalidArgument}!void {
    if (depth > tree_max_depth) return error.InvalidArgument;
    total.* = std.math.add(usize, total.*, count) catch return error.InvalidArgument;
    if (total.* > tree_max_nodes) return error.InvalidArgument;
    for (in[0..count]) |node| {
        if (node.children_len > 0) {
            const kids = node.children orelse return error.InvalidArgument;
            try treeCount(kids, node.children_len, depth + 1, total);
        }
    }
}

/// Preenche `nodes` (árvore Zig) e `owners` (nós da árvore C, na mesma
/// ordem): os filhos diretos de cada grupo ficam contíguos e as subárvores
/// deles em seguida.
fn treeFill(
    nodes: []tree_mod.TreeItem,
    owners: []*ct.ZyntraTreeItem,
    in: [*]ct.ZyntraTreeItem,
    count: usize,
    at: *usize,
) error{InvalidArgument}!void {
    const base = at.*;
    at.* = base + count;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const node = &in[i];
        const children = nodes[at.* .. at.* + node.children_len];
        if (node.children_len > 0) {
            const kids = node.children orelse return error.InvalidArgument;
            try treeFill(nodes, owners, kids, node.children_len, at);
        }
        owners[base + i] = node;
        nodes[base + i] = .{
            .label = strOf(node.label) orelse return error.InvalidArgument,
            .children = children,
            .expanded = node.expanded,
        };
    }
}

/// Árvore convertida para os `TreeItem` da API Zig, com o mapa de nós
/// originais para devolver `expanded` (única mutação do widget).
const TreeArgs = struct {
    items: []tree_mod.TreeItem = &.{},
    owners: []*ct.ZyntraTreeItem = &.{},
    buf_nodes: Buf(tree_mod.TreeItem) = .{},
    buf_owners: Buf(*ct.ZyntraTreeItem) = .{},

    fn deinit(self: TreeArgs) void {
        self.buf_nodes.deinit();
        self.buf_owners.deinit();
    }

    /// Escreve de volta na árvore do chamador o estado de expansão.
    fn writeBack(self: TreeArgs) void {
        for (self.owners, self.items) |owner, node| owner.expanded = node.expanded;
    }
};

fn treeArgsOf(
    allocator: std.mem.Allocator,
    items: ?[*]ct.ZyntraTreeItem,
    items_len: usize,
    scratch_nodes: []tree_mod.TreeItem,
    scratch_owners: []*ct.ZyntraTreeItem,
) error{ InvalidArgument, OutOfMemory }!TreeArgs {
    if (items_len == 0) return error.InvalidArgument;
    const in = items orelse return error.InvalidArgument;
    var total: usize = 0;
    try treeCount(in, items_len, 0, &total);
    var nodes_buf = try Buf(tree_mod.TreeItem).init(allocator, total, scratch_nodes);
    errdefer nodes_buf.deinit();
    var owners_buf = try Buf(*ct.ZyntraTreeItem).init(allocator, total, scratch_owners);
    errdefer owners_buf.deinit();
    var at: usize = 0;
    try treeFill(nodes_buf.slice, owners_buf.slice, in, items_len, &at);
    return .{
        .items = nodes_buf.slice,
        .owners = owners_buf.slice,
        .buf_nodes = nodes_buf,
        .buf_owners = owners_buf,
    };
}

/// Buffer de bytes pertencente ao chamador: `len == 0` aceita `ptr == NULL`
/// (campo sem capacidade, só leitura do vazio) e devolve uma fatia vazia.
fn byteBufOf(ptr: ?[*]u8, len: usize) error{InvalidArgument}![]u8 {
    var vazio: [0]u8 = .{};
    if (len == 0) return vazio[0..];
    const p = ptr orelse return error.InvalidArgument;
    return p[0..len];
}

/// Índice opcional da API Zig -> `i64` do C (`-1` = nenhum).
fn fromIndex(idx: ?usize) i64 {
    if (idx) |i| return @intCast(i);
    return -1;
}

/// Estilo de radio do tema embutido.
pub export fn zyntra_style_radio(kind: i32, out_style: ?*ct.ZyntraRadioStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.radioStyle();
    return .ok;
}

/// Estilo de barra de abas do tema embutido.
pub export fn zyntra_style_tab_bar(kind: i32, out_style: ?*ct.ZyntraTabBarStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.tabBarStyle();
    return .ok;
}

/// Estilo de lista do tema embutido.
pub export fn zyntra_style_list_view(kind: i32, out_style: ?*ct.ZyntraListViewStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.listViewStyle();
    return .ok;
}

/// Estilo de painel do tema embutido.
pub export fn zyntra_style_panel(kind: i32, out_style: ?*ct.ZyntraPanelStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.panelStyle();
    return .ok;
}

/// Estilo de menu do tema embutido.
pub export fn zyntra_style_menu(kind: i32, out_style: ?*ct.ZyntraMenuStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.menuStyle();
    return .ok;
}

/// Estilo de tabela do tema embutido.
pub export fn zyntra_style_table(kind: i32, out_style: ?*ct.ZyntraTableStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.tableStyle();
    return .ok;
}

/// Estilo de árvore do tema embutido.
pub export fn zyntra_style_tree_view(kind: i32, out_style: ?*ct.ZyntraTreeViewStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.treeViewStyle();
    return .ok;
}

/// Estilo de campo/área de texto do tema embutido.
pub export fn zyntra_style_text_input(kind: i32, out_style: ?*ct.ZyntraTextInputStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.textInputStyle();
    return .ok;
}

/// Grupo de opções exclusivas: `options` é uma lista de `ZyntraStr`
/// (emprestada só na chamada) e `selected` pertence ao chamador (o widget lê
/// e altera no clique/setas). `size` é a fonte do rótulo.
pub export fn zyntra_widget_radio(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    options: ?[*]const ct.ZyntraStr,
    options_len: usize,
    selected: ?*usize,
    size: f32,
    style: ?*const ct.ZyntraRadioStyle,
    out_result: ?*ct.ZyntraRadioResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const sel = selected orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const ctx = toCtx(h);
    var scratch: [64][]const u8 = undefined;
    const list = strListOf(ctx.allocator, options, options_len, &scratch) catch |err| return mapWidgetErr(err);
    defer list.deinit();
    const res = radio_mod.radio(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        list.items,
        sel,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .changed = res.changed, .hovered = res.hovered, .focused = res.focused };
    return .ok;
}

/// Barra de abas: `tabs` é a lista de rótulos (lista de `ZyntraStr`) e
/// `active` pertence ao chamador (o widget lê e altera no clique/setas).
pub export fn zyntra_widget_tab_bar(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    tabs: ?[*]const ct.ZyntraStr,
    tabs_len: usize,
    active: ?*usize,
    style: ?*const ct.ZyntraTabBarStyle,
    out_result: ?*ct.ZyntraTabBarResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const act = active orelse return .invalid_argument;
    const ctx = toCtx(h);
    var scratch: [64][]const u8 = undefined;
    const list = strListOf(ctx.allocator, tabs, tabs_len, &scratch) catch |err| return mapWidgetErr(err);
    defer list.deinit();
    const res = tab_bar_mod.beginTabBar(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        list.items,
        act,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .changed = res.changed,
        .focused = res.focused,
        .hovered_index = fromIndex(res.hovered_index),
        .active = res.active,
    };
    return .ok;
}

/// Lista de itens: `items` é a lista de rótulos (lista de `ZyntraStr`);
/// `selected` e `scroll_offset` pertencem ao chamador (o widget lê e altera
/// no clique, roda e teclado).
pub export fn zyntra_widget_list_view(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    items: ?[*]const ct.ZyntraStr,
    items_len: usize,
    selected: ?*usize,
    scroll_offset: ?*f32,
    style: ?*const ct.ZyntraListViewStyle,
    out_result: ?*ct.ZyntraListViewResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const sel = selected orelse return .invalid_argument;
    const scroll = scroll_offset orelse return .invalid_argument;
    const ctx = toCtx(h);
    var scratch: [64][]const u8 = undefined;
    const list = strListOf(ctx.allocator, items, items_len, &scratch) catch |err| return mapWidgetErr(err);
    defer list.deinit();
    const res = list_view_mod.beginListView(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        list.items,
        sel,
        scroll,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .selected = res.selected,
        .changed = res.changed,
        .hovered_index = fromIndex(res.hovered_index),
        .scroll_offset = res.scroll_offset,
    };
    return .ok;
}

/// Painel com cabeçalho: `collapsed` pertence ao chamador (o widget alterna
/// no chevron/tecla). `options.title` é emprestado só na chamada; `size` é a
/// fonte do título.
pub export fn zyntra_widget_panel(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    collapsed: ?*bool,
    options: ct.ZyntraPanelOptions,
    size: f32,
    style: ?*const ct.ZyntraPanelStyle,
    out_result: ?*ct.ZyntraPanelResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const coll = collapsed orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const title = strOf(options.title) orelse return .invalid_argument;
    const res = panel_mod.panel(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        coll,
        .{ .title = title, .collapsible = options.collapsible, .closable = options.closable },
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .content = .{ .x = res.content.x, .y = res.content.y, .w = res.content.w, .h = res.content.h },
        .collapsed = res.collapsed,
        .toggled = res.toggled,
        .close_requested = res.close_requested,
        .hovered = res.hovered,
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Widgets com estruturas planas: menu e tabela (M109)
// ---------------------------------------------------------------------------

/// Menu suspenso: `items` é o vetor de itens (rótulos/atalhos emprestados só
/// na chamada) e `active` pertence ao chamador (hover, teclado e escolha).
pub export fn zyntra_widget_menu(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    items: ?[*]const ct.ZyntraMenuItem,
    items_len: usize,
    active: ?*usize,
    size: f32,
    style: ?*const ct.ZyntraMenuStyle,
    out_result: ?*ct.ZyntraMenuResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const act = active orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const ctx = toCtx(h);
    var scratch: [64]menu_mod.MenuItem = undefined;
    const list = menuListOf(ctx.allocator, items, items_len, &scratch) catch |err| return mapWidgetErr(err);
    defer list.deinit();
    const res = menu_mod.menu(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        list.items,
        act,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .chosen = fromIndex(res.chosen),
        .hovered_index = fromIndex(res.hovered_index),
        .dismissed = res.dismissed,
        .hovered = res.hovered,
        .focus_parent = res.focus_parent,
    };
    return .ok;
}

/// Tabela: `columns` é o vetor de colunas (título + largura) e `rows` o vetor
/// de linhas, cada uma com seu vetor de células (`ZyntraStr`); `selected` e
/// `scroll_offset` pertencem ao chamador (clique, roda e teclado).
pub export fn zyntra_widget_table(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    columns: ?[*]const ct.ZyntraTableColumn,
    columns_len: usize,
    rows: ?[*]const ct.ZyntraTableRow,
    rows_len: usize,
    selected: ?*usize,
    scroll_offset: ?*f32,
    style: ?*const ct.ZyntraTableStyle,
    out_result: ?*ct.ZyntraTableResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const sel = selected orelse return .invalid_argument;
    const scroll = scroll_offset orelse return .invalid_argument;
    const ctx = toCtx(h);
    var col_scratch: [16]table_mod.TableColumn = undefined;
    var row_scratch: [64]table_mod.TableRow = undefined;
    var cell_scratch: [256][]const u8 = undefined;
    const args = tableArgsOf(
        ctx.allocator,
        columns,
        columns_len,
        rows,
        rows_len,
        &col_scratch,
        &row_scratch,
        &cell_scratch,
    ) catch |err| return mapWidgetErr(err);
    defer args.deinit();
    const res = table_mod.beginTable(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        args.columns,
        args.rows,
        sel,
        scroll,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .selected = res.selected,
        .hovered_index = fromIndex(res.hovered_index),
        .scroll_offset = res.scroll_offset,
        .changed = res.changed,
    };
    return .ok;
}

/// Árvore: `items` é a árvore **do chamador** (rótulos emprestados só na
/// chamada; `expanded` volta atualizado na própria árvore) e `selected`/
/// `scroll_offset` pertencem ao chamador (clique, roda e teclado).
pub export fn zyntra_widget_tree_view(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    items: ?[*]ct.ZyntraTreeItem,
    items_len: usize,
    selected: ?*usize,
    scroll_offset: ?*f32,
    style: ?*const ct.ZyntraTreeViewStyle,
    out_result: ?*ct.ZyntraTreeViewResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const sel = selected orelse return .invalid_argument;
    const scroll = scroll_offset orelse return .invalid_argument;
    const ctx = toCtx(h);
    var node_scratch: [64]tree_mod.TreeItem = undefined;
    var owner_scratch: [64]*ct.ZyntraTreeItem = undefined;
    const args = treeArgsOf(ctx.allocator, items, items_len, &node_scratch, &owner_scratch) catch |err| return mapWidgetErr(err);
    defer args.deinit();
    // O widget commita as expansões pendentes mesmo em caminhos de erro, logo
    // o estado devolvido à árvore C é escrito antes de mapear o resultado.
    const outcome = tree_mod.beginTreeView(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        args.items,
        sel,
        scroll,
        st.*,
    );
    args.writeBack();
    const res = outcome catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .selected = res.selected,
        .hovered_index = fromIndex(res.hovered_index),
        .scroll_offset = res.scroll_offset,
        .changed = res.changed,
        .toggled_index = fromIndex(res.toggled_index),
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Campos de texto: text_input (simples e com seleção) e textarea (M112)
// ---------------------------------------------------------------------------

/// Campo de texto de linha única: `buffer` (capacidade `buffer_len`) é do
/// chamador junto de `len`/`cursor` (bytes UTF-8 em fronteira de codepoint);
/// `size` é a fonte usada na medição e no desenho.
pub export fn zyntra_widget_text_input(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    buffer: ?[*]u8,
    buffer_len: usize,
    len: ?*usize,
    cursor: ?*usize,
    size: f32,
    style: ?*const ct.ZyntraTextInputStyle,
    out_result: ?*ct.ZyntraTextInputResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const n = len orelse return .invalid_argument;
    const cur = cursor orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const buf = byteBufOf(buffer, buffer_len) catch return .invalid_argument;
    const res = text_input_mod.textInput(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        buf,
        n,
        cur,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .focused = res.focused,
        .changed = res.changed,
        .submitted = res.submitted,
        .overflowed = res.overflowed,
        .selected = res.selected,
        .undone = res.undone,
        .redone = res.redone,
        .len = res.len,
    };
    return .ok;
}

/// Campo de texto com seleção: `anchor` (offset de byte) e `cursor` marcam a
/// faixa `[min,max)`; ambos pertencem ao chamador e persistem entre frames.
/// Converte a composição C para o modelo Zig (emprestado).
fn toImeComp(c: ct.ZyntraImeComposition) ?ime_mod.Composition {
    const p = c.buf orelse return null;
    if (c.cap == 0) return null;
    if (c.len > c.cap or c.cursor > c.len) return null;
    return .{
        .buf = p[0..c.cap],
        .len = c.len,
        .cursor = c.cursor,
        .active = c.active,
        .committed = c.committed,
    };
}

/// Devolve o estado da composição para o chamador C.
fn fromImeComp(dst: *ct.ZyntraImeComposition, src: ime_mod.Composition) void {
    dst.len = src.len;
    dst.cursor = src.cursor;
    dst.active = src.active;
    dst.committed = src.committed;
}

/// Substitui o pré-edit da composição (`cursor` em bytes, ajustado para
/// uma fronteira de codepoint). Texto emprestado só durante a chamada.
pub export fn zyntra_ime_update(
    comp: ?*ct.ZyntraImeComposition,
    utf8: ?[*]const u8,
    utf8_len: usize,
    cursor: usize,
) callconv(.c) ct.ZyntraResult {
    const c = comp orelse return .invalid_argument;
    var zig = toImeComp(c.*) orelse return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const text: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    zig.update(text, cursor) catch |err| return switch (err) {
        error.InvalidUtf8 => .invalid_text,
        error.BufferTooSmall => .invalid_argument,
        error.OutOfSpace => .out_of_memory,
        error.InvalidState => .invalid_argument,
    };
    fromImeComp(c, zig);
    return .ok;
}

/// Confirma o pré-edit: o texto fica pendente para o widget aplicar.
pub export fn zyntra_ime_commit(comp: ?*ct.ZyntraImeComposition) callconv(.c) ct.ZyntraResult {
    const c = comp orelse return .invalid_argument;
    var zig = toImeComp(c.*) orelse return .invalid_argument;
    zig.commit();
    fromImeComp(c, zig);
    return .ok;
}

/// Cancela a composição (descarta o pré-edit).
pub export fn zyntra_ime_cancel(comp: ?*ct.ZyntraImeComposition) callconv(.c) ct.ZyntraResult {
    const c = comp orelse return .invalid_argument;
    var zig = toImeComp(c.*) orelse return .invalid_argument;
    zig.cancel();
    fromImeComp(c, zig);
    return .ok;
}

/// Campo de texto com composição de IME: aplica o texto confirmado no
/// buffer (substituindo a seleção) e desenha o pré-edit na posição do
/// caret.
pub export fn zyntra_widget_text_input_ime(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    buffer: ?[*]u8,
    buffer_len: usize,
    len: ?*usize,
    cursor: ?*usize,
    anchor: ?*usize,
    comp: ?*ct.ZyntraImeComposition,
    size: f32,
    style: ?*const ct.ZyntraTextInputStyle,
    out_result: ?*ct.ZyntraTextInputResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const n = len orelse return .invalid_argument;
    const cur = cursor orelse return .invalid_argument;
    const anc = anchor orelse return .invalid_argument;
    const c = comp orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const buf = byteBufOf(buffer, buffer_len) catch return .invalid_argument;
    var zig_comp = toImeComp(c.*) orelse return .invalid_argument;
    const res = text_input_mod.textInputIme(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        buf,
        n,
        cur,
        anc,
        &zig_comp,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    fromImeComp(c, zig_comp);
    if (out_result) |o| o.* = .{
        .focused = res.focused,
        .changed = res.changed,
        .submitted = res.submitted,
        .overflowed = res.overflowed,
        .selected = res.selected,
        .undone = res.undone,
        .redone = res.redone,
        .len = res.len,
    };
    return .ok;
}

pub export fn zyntra_widget_text_input_selected(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    buffer: ?[*]u8,
    buffer_len: usize,
    len: ?*usize,
    cursor: ?*usize,
    anchor: ?*usize,
    size: f32,
    style: ?*const ct.ZyntraTextInputStyle,
    out_result: ?*ct.ZyntraTextInputResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const n = len orelse return .invalid_argument;
    const cur = cursor orelse return .invalid_argument;
    const anc = anchor orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const buf = byteBufOf(buffer, buffer_len) catch return .invalid_argument;
    const res = text_input_mod.textInputSelected(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        buf,
        n,
        cur,
        anc,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .focused = res.focused,
        .changed = res.changed,
        .submitted = res.submitted,
        .overflowed = res.overflowed,
        .selected = res.selected,
        .undone = res.undone,
        .redone = res.redone,
        .len = res.len,
    };
    return .ok;
}

/// Área de texto multilinha: além de `buffer`/`len`/`cursor`/`anchor`,
/// `scroll_y` (px) pertence ao chamador e é ajustado pelo widget.
/// Área de texto com composição de IME: aplica o texto confirmado no
/// buffer (substituindo a seleção) e desenha o pré-edit na posição do
/// caret.
pub export fn zyntra_widget_text_area_ime(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    buffer: ?[*]u8,
    buffer_len: usize,
    len: ?*usize,
    cursor: ?*usize,
    anchor: ?*usize,
    scroll_y: ?*f32,
    comp: ?*ct.ZyntraImeComposition,
    size: f32,
    style: ?*const ct.ZyntraTextInputStyle,
    out_result: ?*ct.ZyntraTextAreaResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const n = len orelse return .invalid_argument;
    const cur = cursor orelse return .invalid_argument;
    const anc = anchor orelse return .invalid_argument;
    const scroll = scroll_y orelse return .invalid_argument;
    const c = comp orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const buf = byteBufOf(buffer, buffer_len) catch return .invalid_argument;
    var zig_comp = toImeComp(c.*) orelse return .invalid_argument;
    const res = textarea_mod.textAreaIme(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        buf,
        n,
        cur,
        anc,
        scroll,
        &zig_comp,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    fromImeComp(c, zig_comp);
    if (out_result) |o| o.* = .{
        .focused = res.focused,
        .changed = res.changed,
        .overflowed = res.overflowed,
        .selected = res.selected,
        .undone = res.undone,
        .redone = res.redone,
        .len = res.len,
    };
    return .ok;
}

/// Campo de texto com fonte real (atlas de glifos): caret, seleção e
/// clique seguem os AVANÇOS REAIS dos glifos.
pub export fn zyntra_widget_text_input_atlas(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    buffer: ?[*]u8,
    buffer_len: usize,
    len: ?*usize,
    cursor: ?*usize,
    anchor: ?*usize,
    atlas: ?*ZyntraFontAtlas,
    style: ?*const ct.ZyntraTextInputStyle,
    out_result: ?*ct.ZyntraTextInputResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const n = len orelse return .invalid_argument;
    const cur = cursor orelse return .invalid_argument;
    const anc = anchor orelse return .invalid_argument;
    const a = atlas orelse return .invalid_argument;
    const buf = byteBufOf(buffer, buffer_len) catch return .invalid_argument;
    const state = toFontAtlas(a);
    state.refresh();
    const res = text_input_mod.textInputAtlas(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        buf,
        n,
        cur,
        anc,
        &state.view,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .focused = res.focused,
        .changed = res.changed,
        .submitted = res.submitted,
        .overflowed = res.overflowed,
        .selected = res.selected,
        .undone = res.undone,
        .redone = res.redone,
        .len = res.len,
    };
    return .ok;
}

/// Bloco de texto multilinha (parágrafo) com as métricas de fallback:
/// quebra pela largura do rect e alinha cada linha
/// (`ZYNTRA_TEXT_ALIGN_START/CENTER/END`).
pub export fn zyntra_widget_text_block(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    utf8: ?[*]const u8,
    utf8_len: usize,
    color: ct.ZyntraColor,
    size: f32,
    alignment: i32,
    out_result: ?*ct.ZyntraTextBlockResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (utf8_len > 0 and utf8 == null) return .invalid_argument;
    const al: text_block_mod.Align = switch (alignment) {
        0 => .start,
        1 => .center,
        2 => .end,
        else => return .invalid_argument,
    };
    const bytes: []const u8 = if (utf8_len == 0) &.{} else utf8.?[0..utf8_len];
    const res = text_block_mod.textBlock(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        bytes,
        toColor(color),
        metrics_mod.FontMetrics.withSize(size),
        .{ .alignment = al },
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .lines = @intCast(res.lines), .truncated = res.truncated };
    return .ok;
}

/// Área de texto com fonte real (atlas de glifos): o caret, a seleção,
/// o clique e a rolagem usam os AVANÇOS REAIS dos glifos. Sem quebra
/// suave (as linhas visuais são as linhas lógicas).
pub export fn zyntra_widget_text_area_atlas(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    buffer: ?[*]u8,
    buffer_len: usize,
    len: ?*usize,
    cursor: ?*usize,
    anchor: ?*usize,
    scroll_y: ?*f32,
    atlas: ?*ZyntraFontAtlas,
    style: ?*const ct.ZyntraTextInputStyle,
    out_result: ?*ct.ZyntraTextAreaResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const n = len orelse return .invalid_argument;
    const cur = cursor orelse return .invalid_argument;
    const anc = anchor orelse return .invalid_argument;
    const scroll = scroll_y orelse return .invalid_argument;
    const a = atlas orelse return .invalid_argument;
    const buf = byteBufOf(buffer, buffer_len) catch return .invalid_argument;
    const state = toFontAtlas(a);
    state.refresh();
    const res = textarea_mod.textAreaAtlas(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        buf,
        n,
        cur,
        anc,
        scroll,
        &state.view,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .focused = res.focused,
        .changed = res.changed,
        .overflowed = res.overflowed,
        .selected = res.selected,
        .undone = res.undone,
        .redone = res.redone,
        .len = res.len,
    };
    return .ok;
}

pub export fn zyntra_widget_text_area(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    buffer: ?[*]u8,
    buffer_len: usize,
    len: ?*usize,
    cursor: ?*usize,
    anchor: ?*usize,
    scroll_y: ?*f32,
    size: f32,
    style: ?*const ct.ZyntraTextInputStyle,
    out_result: ?*ct.ZyntraTextAreaResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const n = len orelse return .invalid_argument;
    const cur = cursor orelse return .invalid_argument;
    const anc = anchor orelse return .invalid_argument;
    const scroll = scroll_y orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const buf = byteBufOf(buffer, buffer_len) catch return .invalid_argument;
    const res = textarea_mod.textArea(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        buf,
        n,
        cur,
        anc,
        scroll,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .focused = res.focused,
        .changed = res.changed,
        .overflowed = res.overflowed,
        .selected = res.selected,
        .undone = res.undone,
        .redone = res.redone,
        .len = res.len,
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Widgets de composição/exibição: combo, splitter, spinner, groupbox e
// tooltip (M115)
// ---------------------------------------------------------------------------

/// Orientação do splitter (`ZYNTRA_HORIZONTAL` = divisória horizontal, pos = y;
/// `ZYNTRA_VERTICAL` = divisória vertical, pos = x).
fn toSplitterOrientation(v: i32) ?splitter_mod.SplitterOrientation {
    const o = std.enums.fromInt(ct.ZyntraOrientation, v) orelse return null;
    return switch (o) {
        .horizontal => .horizontal,
        .vertical => .vertical,
    };
}

/// Estilo de splitter do tema embutido.
pub export fn zyntra_style_splitter(kind: i32, out_style: ?*ct.ZyntraSplitterStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.splitterStyle();
    return .ok;
}

/// Estilo de spinner do tema embutido.
pub export fn zyntra_style_spinner(kind: i32, out_style: ?*ct.ZyntraSpinnerStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.spinnerStyle();
    return .ok;
}

/// Estilo de groupbox do tema embutido.
pub export fn zyntra_style_group_box(kind: i32, out_style: ?*ct.ZyntraGroupBoxStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.groupBoxStyle();
    return .ok;
}

/// Estilo de tooltip do tema embutido.
pub export fn zyntra_style_tooltip(kind: i32, out_style: ?*ct.ZyntraTooltipStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.tooltipStyle();
    return .ok;
}

/// Combo dropdown: reusa `ButtonStyle`/`MenuStyle` (como na API Zig).
/// `options` é a lista de rótulos (vetor de `ZyntraStr`, emprestado só na
/// chamada; 1..256), `selected` e `open` pertencem ao chamador (o widget lê e
/// altera). `size` é a fonte do rótulo e dos itens.
pub export fn zyntra_widget_combo(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    options: ?[*]const ct.ZyntraStr,
    options_len: usize,
    selected: ?*usize,
    open: ?*bool,
    size: f32,
    button_style: ?*const ct.ZyntraButtonStyle,
    menu_style: ?*const ct.ZyntraMenuStyle,
    out_result: ?*ct.ZyntraComboResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const bst = button_style orelse return .invalid_argument;
    const mst = menu_style orelse return .invalid_argument;
    const sel = selected orelse return .invalid_argument;
    const op = open orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (options_len == 0 or options_len > 256) return .invalid_argument;
    const ctx = toCtx(h);
    var scratch: [64][]const u8 = undefined;
    const list = strListOf(ctx.allocator, options, options_len, &scratch) catch |err| return mapWidgetErr(err);
    defer list.deinit();
    const res = combo_mod.combo(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        list.items,
        sel,
        op,
        metrics_mod.FontMetrics.withSize(size),
        bst.*,
        mst.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .changed = res.changed, .open = res.open };
    return .ok;
}

/// Splitter arrastável: `pos` pertence ao chamador (lido, clampado e alterado
/// pelo arraste/teclado). `out_result` é opcional.
pub export fn zyntra_widget_splitter(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    orientation: i32,
    pos: ?*f32,
    style: ?*const ct.ZyntraSplitterStyle,
    out_result: ?*ct.ZyntraSplitterResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const p = pos orelse return .invalid_argument;
    const o = toSplitterOrientation(orientation) orelse return .invalid_argument;
    const res = splitter_mod.beginSplitter(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        o,
        p,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |out| out.* = .{
        .pos = res.pos,
        .changed = res.changed,
        .hovered = res.hovered,
        .dragging = res.dragging,
    };
    return .ok;
}

/// Spinner indeterminado (display puro, sem id): `t` é o tempo decorrido em
/// segundos (fornecido pelo chamador); o quadro é função pura de `t`.
pub export fn zyntra_widget_spinner(
    handle: ?*ZyntraContext,
    center: ct.ZyntraVec2,
    t: f32,
    style: ?*const ct.ZyntraSpinnerStyle,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    spinner_mod.spinner(toCtx(h), toVec2(center), t, st.*) catch |err| return mapWidgetErr(err);
    return .ok;
}

/// Groupbox com título: desenha o chrome e devolve em `out_content` (opcional)
/// a área útil para o chamador posicionar os filhos. `title` é emprestado só
/// na chamada; `size` é a fonte do título.
pub export fn zyntra_widget_group_box(
    handle: ?*ZyntraContext,
    bounds: ct.ZyntraRect,
    title: ?[*]const u8,
    title_len: usize,
    size: f32,
    style: ?*const ct.ZyntraGroupBoxStyle,
    out_content: ?*ct.ZyntraRect,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (title_len > 0 and title == null) return .invalid_argument;
    const bytes: []const u8 = if (title_len == 0) &.{} else title.?[0..title_len];
    const content = groupbox_mod.groupBox(
        toCtx(h),
        toRect(bounds),
        bytes,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_content) |o| o.* = fromRect(content);
    return .ok;
}

/// Tooltip por hover: conta frames consecutivos com o mouse em `anchor` e,
/// ao atingir `delay_frames`, desenha caixa + texto perto do cursor. `state`
/// pertence ao chamador (um por tooltip). `text` é emprestado só na chamada.
pub export fn zyntra_widget_tooltip(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    anchor: ct.ZyntraRect,
    text: ?[*]const u8,
    text_len: usize,
    size: f32,
    style: ?*const ct.ZyntraTooltipStyle,
    delay_frames: u32,
    state: ?*ct.ZyntraTooltipState,
    out_result: ?*ct.ZyntraTooltipResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const s = state orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (text_len > 0 and text == null) return .invalid_argument;
    const bytes: []const u8 = if (text_len == 0) &.{} else text.?[0..text_len];
    var local = tooltip_mod.TooltipState{ .hover_frames = s.hover_frames };
    const res = tooltip_mod.tooltip(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(anchor),
        bytes,
        metrics_mod.FontMetrics.withSize(size),
        st.*,
        delay_frames,
        &local,
    ) catch |err| return mapWidgetErr(err);
    s.hover_frames = local.hover_frames;
    if (out_result) |o| o.* = .{ .visible = res.visible, .hovered = res.hovered };
    return .ok;
}

// ---------------------------------------------------------------------------
// Contêineres begin/end: scroll, popup e modal (M116)
// ---------------------------------------------------------------------------

/// Estilo de container rolável do tema embutido.
pub export fn zyntra_style_scroll(kind: i32, out_style: ?*ct.ZyntraScrollStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.scrollStyle();
    return .ok;
}

/// Estilo de popup do tema embutido.
pub export fn zyntra_style_popup(kind: i32, out_style: ?*ct.ZyntraPopupStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.popupStyle();
    return .ok;
}

/// Estilo de modal do tema embutido.
pub export fn zyntra_style_modal(kind: i32, out_style: ?*ct.ZyntraModalStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.modalStyle();
    return .ok;
}

/// Posiciona um popup de `size` junto a `anchor`, dentro de `viewport`.
/// Puro (não exige handle/frame): abre abaixo e vira para cima se faltar
/// espaço; não-finitos saturam para a origem do viewport.
pub export fn zyntra_popup_place(
    anchor: ct.ZyntraRect,
    size: ct.ZyntraSize,
    viewport: ct.ZyntraRect,
    out_rect: ?*ct.ZyntraRect,
) callconv(.c) ct.ZyntraResult {
    const out = out_rect orelse return .invalid_argument;
    const r = popup_mod.popupPlace(
        toRect(anchor),
        .{ .w = size.w, .h = size.h },
        toRect(viewport),
    );
    out.* = fromRect(r);
    return .ok;
}

/// Abre o container rolável: aplica roda/teclado/arrasto em `scroll_y`
/// (do chamador), emite `clip(bounds)` e devolve em `out_result` a área
/// `content` onde os filhos devem ser posicionados. SEMPRE parear com
/// `zyntra_widget_scroll_end`, mesmo sem filhos.
pub export fn zyntra_widget_scroll_begin(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    scroll_y: ?*f32,
    content_h: f32,
    speed: f32,
    style: ?*const ct.ZyntraScrollStyle,
    out_result: ?*ct.ZyntraScrollResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const sy = scroll_y orelse return .invalid_argument;
    const res = scroll_mod.beginScroll(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        sy,
        content_h,
        speed,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .content = fromRect(res.content),
        .offset = res.offset,
        .max_offset = res.max_offset,
        .hovered = res.hovered,
        .scrolled = res.scrolled,
        .dragging = res.dragging,
    };
    return .ok;
}

/// Fecha o container rolável: limpa o clip e desenha a scrollbar (só com
/// overflow). `bounds`, `scroll_y`, `content_h` e `style` devem ser os
/// mesmos do `zyntra_widget_scroll_begin` correspondente.
pub export fn zyntra_widget_scroll_end(
    handle: ?*ZyntraContext,
    bounds: ct.ZyntraRect,
    scroll_y: f32,
    content_h: f32,
    style: ?*const ct.ZyntraScrollStyle,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const b = toRect(bounds);
    if (!std.math.isFinite(b.x) or !std.math.isFinite(b.y) or
        !std.math.isFinite(b.w) or !std.math.isFinite(b.h) or b.w <= 0 or b.h <= 0)
    {
        return .invalid_argument;
    }
    if (!std.math.isFinite(scroll_y) or scroll_y < 0) return .invalid_argument;
    if (!std.math.isFinite(content_h) or content_h < 0) return .invalid_argument;
    if (!st.isValid()) return .invalid_argument;
    scroll_mod.endScroll(toCtx(h), b, scroll_y, content_h, st.*) catch |err| return mapWidgetErr(err);
    return .ok;
}

/// Abre o popup: desenha o painel, emite `clip(bounds)` e sinaliza em
/// `out_result` hover e dispensa (press fora ou Escape). SEMPRE parear com
/// `zyntra_widget_popup_end`; o chamador decide abrir/fechar.
pub export fn zyntra_widget_popup_begin(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    style: ?*const ct.ZyntraPopupStyle,
    out_result: ?*ct.ZyntraPopupResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const res = popup_mod.beginPopup(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .dismissed = res.dismissed, .hovered = res.hovered };
    return .ok;
}

/// Fecha o popup: limpa o clip do `zyntra_widget_popup_begin` correspondente.
pub export fn zyntra_widget_popup_end(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    popup_mod.endPopup(toCtx(h)) catch |err| return mapWidgetErr(err);
    return .ok;
}

/// Abre o modal básico: escurece o viewport, desenha o painel, emite
/// `clip(bounds)` e sinaliza dispensa (press fora ou Escape). SEMPRE parear
/// com `zyntra_widget_modal_end`.
pub export fn zyntra_widget_modal_begin(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    style: ?*const ct.ZyntraModalStyle,
    out_result: ?*ct.ZyntraModalResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const res = modal_mod.beginModal(
        toCtx(h),
        id_mod.Id.fromU64(id),
        toRect(bounds),
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .dismissed = res.dismissed, .hovered = res.hovered, .dragging = res.dragging };
    return .ok;
}

/// Abre o modal arrastável com título: press na faixa de título captura e
/// `bounds`/`drag` (do chamador) persistem entre frames. `title` é emprestado
/// só na chamada; `size` é a fonte do título. SEMPRE parear com
/// `zyntra_widget_modal_end`.
pub export fn zyntra_widget_modal_titled(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ?*ct.ZyntraRect,
    title: ?[*]const u8,
    title_len: usize,
    size: f32,
    title_h: f32,
    drag: ?*ct.ZyntraModalDragState,
    style: ?*const ct.ZyntraModalStyle,
    out_result: ?*ct.ZyntraModalResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const bp = bounds orelse return .invalid_argument;
    const dp = drag orelse return .invalid_argument;
    const st = style orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (!std.math.isFinite(title_h) or title_h <= 0) return .invalid_argument;
    if (title_len > 0 and title == null) return .invalid_argument;
    const bytes: []const u8 = if (title_len == 0) &.{} else title.?[0..title_len];
    var b = toRect(bp.*);
    defer bp.* = fromRect(b);
    var d = modal_mod.ModalDragState{ .dx = dp.dx, .dy = dp.dy };
    defer {
        dp.dx = d.dx;
        dp.dy = d.dy;
    }
    const res = modal_mod.beginModalTitled(
        toCtx(h),
        id_mod.Id.fromU64(id),
        &b,
        bytes,
        metrics_mod.FontMetrics.withSize(size),
        title_h,
        &d,
        st.*,
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{ .dismissed = res.dismissed, .hovered = res.hovered, .dragging = res.dragging };
    return .ok;
}

/// Fecha o modal: limpa o clip do `zyntra_widget_modal_begin`/`_titled`
/// correspondente.
pub export fn zyntra_widget_modal_end(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    modal_mod.endModal(toCtx(h)) catch |err| return mapWidgetErr(err);
    return .ok;
}

// ---------------------------------------------------------------------------
// Arrastar-e-soltar e fantasma do arraste: DnD + drag ghost (M117)
// ---------------------------------------------------------------------------

/// Estilo de drag ghost do tema embutido.
pub export fn zyntra_style_drag_ghost(kind: i32, out_style: ?*ct.ZyntraDragGhostStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.dragGhostStyle();
    return .ok;
}

/// Inicia um arraste a partir de `source` (a origem deve já deter a captura
/// de press). `kind` (não vazio) é o contrato entre origem e alvo; `label`
/// (opcional) é o rótulo do fantasma; ambos são EMPRESTADOS e devem
/// continuar válidos até o solto/cancelamento. `data` é opaco (a lib nunca
/// dereferencia; pode ser nulo).
pub export fn zyntra_dnd_begin(
    handle: ?*ZyntraContext,
    source: ct.ZyntraId,
    kind: ?[*]const u8,
    kind_len: usize,
    data: ?*const anyopaque,
    label: ?[*]const u8,
    label_len: usize,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    if (source == 0 or kind_len == 0 or kind == null) return .invalid_argument;
    if (label_len > 0 and label == null) return .invalid_argument;
    const k: []const u8 = kind.?[0..kind_len];
    const l: []const u8 = if (label_len == 0) &.{} else label.?[0..label_len];
    dnd_mod.begin(toCtx(h), id_mod.Id.fromU64(source), .{
        .kind = k,
        .data = data,
        .label = l,
    }) catch |err| return mapWidgetErr(err);
    return .ok;
}

/// Cancela o arraste ativo (sem alvo). Sem arraste, não tem efeito; o
/// último solto/cancelamento permanece até o próximo `begin_frame`.
pub export fn zyntra_dnd_cancel(handle: ?*ZyntraContext) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    dnd_mod.cancel(toCtx(h));
    return .ok;
}

/// `true` se há arraste ativo.
pub export fn zyntra_dnd_is_dragging(handle: ?*ZyntraContext, out_dragging: ?*bool) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_dragging orelse return .invalid_argument;
    out.* = dnd_mod.isDragging(toCtx(h));
    return .ok;
}

/// Registra `id` como alvo candidato neste frame e devolve o verdicto.
/// Chamar todo frame, mesmo sem arraste (para receber `.dropped`).
pub export fn zyntra_dnd_accept(
    handle: ?*ZyntraContext,
    target: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    out_accept: ?*ct.ZyntraDndAccept,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_accept orelse return .invalid_argument;
    const res = dnd_mod.accept(toCtx(h), id_mod.Id.fromU64(target), toRect(bounds));
    out.* = switch (res) {
        .none => .none,
        .hover => .hover,
        .dropped => .dropped,
    };
    return .ok;
}

/// Solto resolvido neste frame. Sem solto, devolve `present == false` e
/// zera os demais campos. `kind`/`label` apontam para a memória emprestada
/// no `zyntra_dnd_begin` correspondente.
pub export fn zyntra_dnd_last_drop(handle: ?*ZyntraContext, out_drop: ?*ct.ZyntraDndDrop) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_drop orelse return .invalid_argument;
    const drop = dnd_mod.lastDrop(toCtx(h)) orelse {
        out.* = .{};
        return .ok;
    };
    out.* = .{
        .present = true,
        .cancelled = drop.cancelled,
        .target = if (drop.target) |t| t.value() else 0,
        .source = if (drop.source) |s| s.value() else 0,
        .kind = cStr(drop.payload.kind),
        .label = cStr(drop.payload.label),
        .data = drop.payload.data,
    };
    return .ok;
}

/// Id da origem do arraste ativo (`0` sem arraste).
pub export fn zyntra_dnd_drag_source(handle: ?*ZyntraContext, out_source: ?*ct.ZyntraId) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_source orelse return .invalid_argument;
    out.* = if (dnd_mod.dragSource(toCtx(h))) |s| s.value() else 0;
    return .ok;
}

/// Alvo sob o cursor registrado neste frame (`0` = nenhum).
pub export fn zyntra_dnd_hover_target(handle: ?*ZyntraContext, out_target: ?*ct.ZyntraId) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_target orelse return .invalid_argument;
    out.* = if (dnd_mod.hoverTarget(toCtx(h))) |t| t.value() else 0;
    return .ok;
}

/// Posição atual do arraste (cursor conhecido; senão a última).
pub export fn zyntra_dnd_drag_position(handle: ?*ZyntraContext, out_pos: ?*ct.ZyntraVec2) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_pos orelse return .invalid_argument;
    const p = dnd_mod.dragPosition(toCtx(h));
    out.* = .{ .x = p.x, .y = p.y };
    return .ok;
}

/// Posição onde o arraste começou.
pub export fn zyntra_dnd_drag_origin(handle: ?*ZyntraContext, out_pos: ?*ct.ZyntraVec2) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_pos orelse return .invalid_argument;
    const p = dnd_mod.dragOrigin(toCtx(h));
    out.* = .{ .x = p.x, .y = p.y };
    return .ok;
}

/// Distância percorrida desde o início do arraste (`0` sem arraste).
pub export fn zyntra_dnd_drag_distance(handle: ?*ZyntraContext, out_distance: ?*f32) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_distance orelse return .invalid_argument;
    out.* = dnd_mod.dragDistance(toCtx(h));
    return .ok;
}

/// `true` quando a distância percorrida excede `px`; `px` não-finito ou
/// negativo devolve `false` (mesma regra da API Zig).
pub export fn zyntra_dnd_drag_exceeds(
    handle: ?*ZyntraContext,
    px: f32,
    out_exceeds: ?*bool,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_exceeds orelse return .invalid_argument;
    out.* = dnd_mod.dragExceeds(toCtx(h), px);
    return .ok;
}

/// Desenha o fantasma do arraste ativo sob o cursor (chamar por último,
/// para ficar por cima). Sem arraste, nenhum comando é emitido e
/// `out_result.drawn` é falso. `size` é a fonte do rótulo.
pub export fn zyntra_widget_drag_ghost(
    handle: ?*ZyntraContext,
    style: ?*const ct.ZyntraDragGhostStyle,
    size: f32,
    out_result: ?*ct.ZyntraDragGhostResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    const res = drag_ghost_mod.dragGhost(
        toCtx(h),
        st.*,
        metrics_mod.FontMetrics.withSize(size),
    ) catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .drawn = res.drawn,
        .rect = fromRect(res.rect),
        .metrics = res.metrics,
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Barras de composição: toolbar e statusbar (M118)
// ---------------------------------------------------------------------------

/// Reconstrói o posicionador da toolbar a partir do estado C (o `area` é
/// derivado de `content`/`item_h`, como no widget Zig). Estado corrompido
/// (não-finito/negativo) ⇒ `null`.
fn toolbarFromC(s: *const ct.ZyntraToolbar) ?toolbar_mod.Toolbar {
    const content = toRect(s.content);
    if (!std.math.isFinite(content.x) or !std.math.isFinite(content.y) or
        !std.math.isFinite(content.w) or !std.math.isFinite(content.h) or
        content.w < 0 or content.h < 0)
    {
        return null;
    }
    if (!std.math.isFinite(s.item_h) or s.item_h < 0) return null;
    if (!std.math.isFinite(s.spacing) or s.spacing < 0) return null;
    if (!std.math.isFinite(s.cursor)) return null;
    const strip = types_mod.Rect{
        .x = content.x,
        .y = content.y + @max(0, (content.h - s.item_h) * 0.5),
        .w = content.w,
        .h = s.item_h,
    };
    var placer = layout_mod.StackPlacer.init(strip, .horizontal, s.spacing);
    placer.cursor = s.cursor;
    return .{
        .content = content,
        .item_h = s.item_h,
        .placer = placer,
        .overflowed = s.overflowed,
    };
}

fn toolbarToC(tb: *const toolbar_mod.Toolbar) ct.ZyntraToolbar {
    return .{
        .content = fromRect(tb.content),
        .item_h = tb.item_h,
        .spacing = tb.placer.spacing,
        .cursor = tb.placer.cursor,
        .overflowed = tb.overflowed,
    };
}

/// Reconstrói o posicionador da statusbar a partir do estado C. Estado
/// corrompido (não-finito/negativo) ⇒ `null`.
fn statusBarFromC(s: *const ct.ZyntraStatusBar) ?statusbar_mod.StatusBar {
    const content = toRect(s.content);
    if (!std.math.isFinite(content.x) or !std.math.isFinite(content.y) or
        !std.math.isFinite(content.w) or !std.math.isFinite(content.h) or
        content.w < 0 or content.h < 0)
    {
        return null;
    }
    if (!std.math.isFinite(s.item_h) or s.item_h < 0) return null;
    if (!std.math.isFinite(s.spacing) or s.spacing < 0) return null;
    if (!std.math.isFinite(s.left_cursor) or !std.math.isFinite(s.right_x)) return null;
    const strip = types_mod.Rect{
        .x = content.x,
        .y = content.y + @max(0, (content.h - s.item_h) * 0.5),
        .w = content.w,
        .h = s.item_h,
    };
    var left = layout_mod.StackPlacer.init(strip, .horizontal, s.spacing);
    left.cursor = s.left_cursor;
    return .{
        .content = content,
        .item_h = s.item_h,
        .spacing = s.spacing,
        .left = left,
        .right_x = s.right_x,
        .overflowed = s.overflowed,
    };
}

fn statusBarToC(sb: *const statusbar_mod.StatusBar) ct.ZyntraStatusBar {
    return .{
        .content = fromRect(sb.content),
        .item_h = sb.item_h,
        .spacing = sb.spacing,
        .left_cursor = sb.left.cursor,
        .right_x = sb.right_x,
        .overflowed = sb.overflowed,
    };
}

/// Estilo de toolbar do tema embutido.
pub export fn zyntra_style_toolbar(kind: i32, out_style: ?*ct.ZyntraToolbarStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.toolbarStyle();
    return .ok;
}

/// Estilo de statusbar do tema embutido.
pub export fn zyntra_style_status_bar(kind: i32, out_style: ?*ct.ZyntraStatusBarStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.statusBarStyle();
    return .ok;
}

/// Desenha o chrome da toolbar e devolve em `out_bar` o estado de
/// posicionamento (do chamador) para os `zyntra_toolbar_*`.
pub export fn zyntra_widget_toolbar(
    handle: ?*ZyntraContext,
    bounds: ct.ZyntraRect,
    style: ?*const ct.ZyntraToolbarStyle,
    out_bar: ?*ct.ZyntraToolbar,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const out = out_bar orelse return .invalid_argument;
    const res = toolbar_mod.toolbar(toCtx(h), toRect(bounds), st.*) catch |err| return mapWidgetErr(err);
    out.* = toolbarToC(&res);
    return .ok;
}

/// Próximo item da toolbar com `width` pedida (clampada ao restante; largura
/// inválida/maior marca `overflowed`). `out_rect` é obrigatório.
pub export fn zyntra_toolbar_next_item(
    bar: ?*ct.ZyntraToolbar,
    width: f32,
    out_rect: ?*ct.ZyntraRect,
) callconv(.c) ct.ZyntraResult {
    const b = bar orelse return .invalid_argument;
    const out = out_rect orelse return .invalid_argument;
    var tb = toolbarFromC(b) orelse return .invalid_argument;
    const r = tb.nextItem(width);
    b.* = toolbarToC(&tb);
    out.* = fromRect(r);
    return .ok;
}

/// Espaço horizontal restante na faixa de itens.
pub export fn zyntra_toolbar_remaining(
    bar: ?*const ct.ZyntraToolbar,
    out_remaining: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const b = bar orelse return .invalid_argument;
    const out = out_remaining orelse return .invalid_argument;
    const tb = toolbarFromC(b) orelse return .invalid_argument;
    out.* = tb.remaining();
    return .ok;
}

/// Posiciona e desenha um divisor vertical entre grupos (reusa o separador),
/// avançando o estado da toolbar.
pub export fn zyntra_toolbar_separator(
    handle: ?*ZyntraContext,
    bar: ?*ct.ZyntraToolbar,
    style: ?*const ct.ZyntraSeparatorStyle,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const b = bar orelse return .invalid_argument;
    const st = style orelse return .invalid_argument;
    var tb = toolbarFromC(b) orelse return .invalid_argument;
    toolbar_mod.toolbarSeparator(toCtx(h), &tb, st.*) catch |err| return mapWidgetErr(err);
    b.* = toolbarToC(&tb);
    return .ok;
}

/// Desenha o chrome da statusbar e devolve em `out_bar` o estado de
/// posicionamento (do chamador) para os `zyntra_status_bar_*`.
pub export fn zyntra_widget_status_bar(
    handle: ?*ZyntraContext,
    bounds: ct.ZyntraRect,
    style: ?*const ct.ZyntraStatusBarStyle,
    out_bar: ?*ct.ZyntraStatusBar,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st = style orelse return .invalid_argument;
    const out = out_bar orelse return .invalid_argument;
    const res = statusbar_mod.statusBar(toCtx(h), toRect(bounds), st.*) catch |err| return mapWidgetErr(err);
    out.* = statusBarToC(&res);
    return .ok;
}

/// Próximo segmento à esquerda; clampa ao espaço livre (inclui a reserva do
/// lado direito) e marca `overflowed` quando não couber.
pub export fn zyntra_status_bar_next_item(
    bar: ?*ct.ZyntraStatusBar,
    width: f32,
    out_rect: ?*ct.ZyntraRect,
) callconv(.c) ct.ZyntraResult {
    const b = bar orelse return .invalid_argument;
    const out = out_rect orelse return .invalid_argument;
    var sb = statusBarFromC(b) orelse return .invalid_argument;
    const r = sb.nextItem(width);
    b.* = statusBarToC(&sb);
    out.* = fromRect(r);
    return .ok;
}

/// Próximo segmento ancorado à direita (nunca invade o lado esquerdo).
pub export fn zyntra_status_bar_next_right(
    bar: ?*ct.ZyntraStatusBar,
    width: f32,
    out_rect: ?*ct.ZyntraRect,
) callconv(.c) ct.ZyntraResult {
    const b = bar orelse return .invalid_argument;
    const out = out_rect orelse return .invalid_argument;
    var sb = statusBarFromC(b) orelse return .invalid_argument;
    const r = sb.nextRight(width);
    b.* = statusBarToC(&sb);
    out.* = fromRect(r);
    return .ok;
}

/// Espaço horizontal livre entre os dois lados.
pub export fn zyntra_status_bar_remaining(
    bar: ?*const ct.ZyntraStatusBar,
    out_remaining: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const b = bar orelse return .invalid_argument;
    const out = out_remaining orelse return .invalid_argument;
    const sb = statusBarFromC(b) orelse return .invalid_argument;
    out.* = sb.remaining();
    return .ok;
}

/// Segmento de texto (1 linha) à esquerda: mede, posiciona e emite o texto.
/// `text` é emprestado só na chamada; `out_rect` é opcional.
pub export fn zyntra_status_bar_text(
    handle: ?*ZyntraContext,
    bar: ?*ct.ZyntraStatusBar,
    text: ?[*]const u8,
    text_len: usize,
    size: f32,
    color: ct.ZyntraColor,
    out_rect: ?*ct.ZyntraRect,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const b = bar orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;
    if (text_len > 0 and text == null) return .invalid_argument;
    const bytes: []const u8 = if (text_len == 0) &.{} else text.?[0..text_len];
    var sb = statusBarFromC(b) orelse return .invalid_argument;
    const r = statusbar_mod.statusBarText(
        toCtx(h),
        &sb,
        bytes,
        metrics_mod.FontMetrics.withSize(size),
        toColor(color),
    ) catch |err| return mapWidgetErr(err);
    b.* = statusBarToC(&sb);
    if (out_rect) |o| o.* = fromRect(r);
    return .ok;
}

/// Posiciona e desenha um divisor vertical entre segmentos (lado esquerdo),
/// avançando o estado da statusbar.
pub export fn zyntra_status_bar_separator(
    handle: ?*ZyntraContext,
    bar: ?*ct.ZyntraStatusBar,
    style: ?*const ct.ZyntraSeparatorStyle,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const b = bar orelse return .invalid_argument;
    const st = style orelse return .invalid_argument;
    var sb = statusBarFromC(b) orelse return .invalid_argument;
    statusbar_mod.statusBarSeparator(toCtx(h), &sb, st.*) catch |err| return mapWidgetErr(err);
    b.* = statusBarToC(&sb);
    return .ok;
}

// ---------------------------------------------------------------------------
// Grafo de nós: graph view (M119)
// ---------------------------------------------------------------------------

/// Buffers temporários da chamada: nós/arestas convertidos e as posições
/// C para escrever de volta após um arraste.
const GraphArgs = struct {
    nodes: []graph_mod.GraphNode,
    edges: []graph_mod.GraphEdge,
    c_nodes: ?[*]ct.ZyntraGraphNode,
    node_count: usize,
    allocator: std.mem.Allocator,

    fn deinit(self: *GraphArgs) void {
        self.allocator.free(self.nodes);
        self.allocator.free(self.edges);
    }

    fn writeBack(self: *const GraphArgs) void {
        if (self.node_count == 0) return;
        const owners = self.c_nodes.?[0..self.node_count];
        for (self.nodes, owners) |n, *owner| {
            owner.pos = .{ .x = n.pos.x, .y = n.pos.y };
        }
    }
};

/// Converte os nós/arestas C para as fatias do modelo Zig. Os títulos são
/// emprestados só durante a chamada; `pos` é copiado de volta no fim.
fn graphArgsOf(
    allocator: std.mem.Allocator,
    c_nodes: ?[*]ct.ZyntraGraphNode,
    nodes_len: usize,
    c_edges: ?[*]const ct.ZyntraGraphEdge,
    edges_len: usize,
) !GraphArgs {
    if (nodes_len > 0 and c_nodes == null) return error.InvalidArgument;
    if (edges_len > 0 and c_edges == null) return error.InvalidArgument;

    const nodes = try allocator.alloc(graph_mod.GraphNode, nodes_len);
    errdefer allocator.free(nodes);
    if (nodes_len > 0) {
        for (c_nodes.?[0..nodes_len], 0..) |n, i| {
            const title: []const u8 = if (n.title.len == 0) &.{} else blk: {
                const p = n.title.ptr orelse return error.InvalidArgument;
                break :blk p[0..n.title.len];
            };
            nodes[i] = .{
                .pos = .{ .x = n.pos.x, .y = n.pos.y },
                .size = .{ .x = n.size.x, .y = n.size.y },
                .title = title,
                .inputs = n.inputs,
                .outputs = n.outputs,
            };
        }
    }

    const edges = try allocator.alloc(graph_mod.GraphEdge, edges_len);
    errdefer allocator.free(edges);
    if (edges_len > 0) {
        for (c_edges.?[0..edges_len], 0..) |e, i| {
            edges[i] = .{
                .from = e.from,
                .to = e.to,
                .from_port = e.from_port,
                .to_port = e.to_port,
            };
        }
    }

    return .{
        .nodes = nodes,
        .edges = edges,
        .c_nodes = c_nodes,
        .node_count = nodes_len,
        .allocator = allocator,
    };
}

/// Índice C (-1 = nenhum) → índice Zig.
fn graphIndex(value: i64) ?usize {
    if (value < 0) return null;
    return std.math.cast(usize, value);
}

fn graphViewStateFromC(s: ct.ZyntraGraphViewState) graph_view_mod.GraphViewState {
    return .{
        .transform = .{
            .pan = .{ .x = s.transform.pan.x, .y = s.transform.pan.y },
            .zoom = s.transform.zoom,
        },
        .selected = graphIndex(s.selected),
        .drag_node = graphIndex(s.drag_node),
        .drag_grab = .{ .x = s.drag_grab.x, .y = s.drag_grab.y },
        .pan_anchor = .{ .x = s.pan_anchor.x, .y = s.pan_anchor.y },
        .panning = s.panning,
    };
}

fn graphViewStateToC(s: *const graph_view_mod.GraphViewState) ct.ZyntraGraphViewState {
    return .{
        .transform = .{
            .pan = .{ .x = s.transform.pan.x, .y = s.transform.pan.y },
            .zoom = s.transform.zoom,
        },
        .selected = fromIndex(s.selected),
        .drag_node = fromIndex(s.drag_node),
        .drag_grab = .{ .x = s.drag_grab.x, .y = s.drag_grab.y },
        .pan_anchor = .{ .x = s.pan_anchor.x, .y = s.pan_anchor.y },
        .panning = s.panning,
    };
}

/// Estilo de grafo do tema embutido.
pub export fn zyntra_style_graph(kind: i32, out_style: ?*ct.ZyntraGraphStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.graphStyle();
    return .ok;
}

/// Inicializa o estado do grafo com os padrões da API Zig (zoom 1, nenhum
/// nó selecionado/arrastado). Chame antes do primeiro frame.
pub export fn zyntra_graph_view_state_init(out_state: ?*ct.ZyntraGraphViewState) callconv(.c) ct.ZyntraResult {
    const out = out_state orelse return .invalid_argument;
    out.* = .{};
    return .ok;
}

/// Preenche as opções de interação com os padrões da API Zig.
pub export fn zyntra_graph_view_options_default(out_options: ?*ct.ZyntraGraphViewOptions) callconv(.c) ct.ZyntraResult {
    const out = out_options orelse return .invalid_argument;
    out.* = .{};
    return .ok;
}

/// Desenha e interage com um grafo de nós. `nodes` é mutável: o arraste
/// atualiza `pos` na memória do chamador. `title` é emprestado só na
/// chamada. `state` é retido entre frames; índices -1 = nenhum.
pub export fn zyntra_widget_graph_view(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    nodes: ?[*]ct.ZyntraGraphNode,
    nodes_len: usize,
    edges: ?[*]const ct.ZyntraGraphEdge,
    edges_len: usize,
    state: ?*ct.ZyntraGraphViewState,
    options: ?*const ct.ZyntraGraphViewOptions,
    style: ?*const ct.ZyntraGraphStyle,
    size: f32,
    out_result: ?*ct.ZyntraGraphViewResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st_c = state orelse return .invalid_argument;
    const opts_c = options orelse return .invalid_argument;
    const sty = style orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;

    const ctx = toCtx(h);
    var args = graphArgsOf(ctx.allocator, nodes, nodes_len, edges, edges_len) catch |err| return mapWidgetErr(err);
    defer args.deinit();

    const opts = graph_view_mod.GraphViewOptions{
        .min_zoom = opts_c.min_zoom,
        .max_zoom = opts_c.max_zoom,
        .zoom_step = opts_c.zoom_step,
        .pan_step = opts_c.pan_step,
        .edge_segments = opts_c.edge_segments,
    };
    var st = graphViewStateFromC(st_c.*);
    const outcome = graph_view_mod.graphView(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        args.nodes,
        args.edges,
        &st,
        opts,
        sty.*,
        metrics_mod.FontMetrics.withSize(size),
    );
    args.writeBack();
    st_c.* = graphViewStateToC(&st);
    const res = outcome catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .hovered = fromIndex(res.hovered),
        .selected = fromIndex(res.selected),
        .dragging = fromIndex(res.dragging),
        .drag_delta = .{ .x = res.drag_delta.x, .y = res.drag_delta.y },
        .pan_delta = .{ .x = res.pan_delta.x, .y = res.pan_delta.y },
        .zoom_changed = res.zoom_changed,
        .panning = res.panning,
        .changed = res.changed,
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Timeline: trilhas, chaves, scrub/pan/zoom (M120)
// ---------------------------------------------------------------------------

/// Buffers temporários da timeline: trilhas convertidas, chaves achatadas e
/// as trilhas C para escrever de volta os tempos arrastados.
const TimelineArgs = struct {
    tracks: []timeline_mod.Track,
    keys: []timeline_mod.Keyframe,
    c_tracks: ?[*]ct.ZyntraTimelineTrack,
    track_count: usize,
    allocator: std.mem.Allocator,

    fn deinit(self: *TimelineArgs) void {
        self.allocator.free(self.tracks);
        self.allocator.free(self.keys);
    }

    fn writeBack(self: *const TimelineArgs) void {
        if (self.track_count == 0) return;
        const owners = self.c_tracks.?[0..self.track_count];
        for (self.tracks, owners) |track, *owner| {
            if (track.keys.len == 0) continue;
            const dest = owner.keys.?[0..track.keys.len];
            for (track.keys, dest) |k, *ck| ck.t = k.t;
        }
    }
};

/// Converte trilhas C em trilhas Zig; as chaves são achatadas num buffer
/// único e os nomes ficam emprestados só durante a chamada.
fn timelineArgsOf(
    allocator: std.mem.Allocator,
    c_tracks: ?[*]ct.ZyntraTimelineTrack,
    tracks_len: usize,
) !TimelineArgs {
    if (tracks_len > 0 and c_tracks == null) return error.InvalidArgument;

    var total_keys: usize = 0;
    if (tracks_len > 0) {
        for (c_tracks.?[0..tracks_len]) |t| {
            if (t.keys_len > 0 and t.keys == null) return error.InvalidArgument;
            total_keys = std.math.add(usize, total_keys, t.keys_len) catch return error.InvalidArgument;
        }
    }

    const tracks = try allocator.alloc(timeline_mod.Track, tracks_len);
    errdefer allocator.free(tracks);
    const keys = try allocator.alloc(timeline_mod.Keyframe, total_keys);
    errdefer allocator.free(keys);

    var offset: usize = 0;
    if (tracks_len > 0) {
        for (c_tracks.?[0..tracks_len], 0..) |t, i| {
            const name: []const u8 = if (t.name.len == 0) &.{} else blk: {
                const p = t.name.ptr orelse return error.InvalidArgument;
                break :blk p[0..t.name.len];
            };
            const slice = keys[offset .. offset + t.keys_len];
            if (t.keys_len > 0) {
                for (t.keys.?[0..t.keys_len], 0..) |k, ki| {
                    slice[ki] = .{ .t = k.t, .tag = k.tag };
                }
            }
            offset += t.keys_len;
            tracks[i] = .{ .name = name, .keys = slice };
        }
    }

    return .{
        .tracks = tracks,
        .keys = keys,
        .c_tracks = c_tracks,
        .track_count = tracks_len,
        .allocator = allocator,
    };
}

/// (`track`, `key`) C (-1 = nenhum) → referência Zig.
fn timelineRef(track: i64, key: i64) ?timeline_mod.KeyRef {
    if (track < 0 or key < 0) return null;
    const t = std.math.cast(u32, track) orelse return null;
    const k = std.math.cast(u32, key) orelse return null;
    return .{ .track = t, .key = k };
}

fn timelineRefTrack(r: ?timeline_mod.KeyRef) i64 {
    return if (r) |v| @intCast(v.track) else -1;
}

fn timelineRefKey(r: ?timeline_mod.KeyRef) i64 {
    return if (r) |v| @intCast(v.key) else -1;
}

fn timelineDragFromC(mode: i32) ?timeline_view_mod.TimelineDragMode {
    return switch (mode) {
        0 => .none,
        1 => .scrub,
        2 => .pan,
        3 => .key,
        else => null,
    };
}

fn timelineViewStateFromC(s: ct.ZyntraTimelineViewState) !timeline_view_mod.TimelineViewState {
    const drag = timelineDragFromC(s.drag) orelse return error.InvalidArgument;
    return .{
        .transform = .{ .start = s.transform.start, .pps = s.transform.pps },
        .duration = s.duration,
        .playhead = s.playhead,
        .selected = timelineRef(s.selected_track, s.selected_key),
        .drag = drag,
        .drag_key = timelineRef(s.drag_track, s.drag_key),
        .drag_grab = s.drag_grab,
        .pan_time = s.pan_time,
    };
}

fn timelineViewStateToC(s: *const timeline_view_mod.TimelineViewState) ct.ZyntraTimelineViewState {
    return .{
        .transform = .{ .start = s.transform.start, .pps = s.transform.pps },
        .duration = s.duration,
        .playhead = s.playhead,
        .selected_track = timelineRefTrack(s.selected),
        .selected_key = timelineRefKey(s.selected),
        .drag = @backingInt(s.drag),
        .drag_track = timelineRefTrack(s.drag_key),
        .drag_key = timelineRefKey(s.drag_key),
        .drag_grab = s.drag_grab,
        .pan_time = s.pan_time,
    };
}

/// Estilo de timeline do tema embutido.
pub export fn zyntra_style_timeline(kind: i32, out_style: ?*ct.ZyntraTimelineStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.timelineStyle();
    return .ok;
}

/// Inicializa o estado da timeline (duração 10 s, playhead 0, pps 80,
/// nenhuma seleção/arraste). Chame antes do primeiro frame.
pub export fn zyntra_timeline_view_state_init(out_state: ?*ct.ZyntraTimelineViewState) callconv(.c) ct.ZyntraResult {
    const out = out_state orelse return .invalid_argument;
    out.* = .{};
    return .ok;
}

/// Preenche as opções de interação com os padrões da API Zig.
pub export fn zyntra_timeline_view_options_default(out_options: ?*ct.ZyntraTimelineViewOptions) callconv(.c) ct.ZyntraResult {
    const out = out_options orelse return .invalid_argument;
    out.* = .{};
    return .ok;
}

/// Desenha e interage com uma timeline. `tracks` é mutável: o arraste de uma
/// chave atualiza `keys[i].t` na memória do chamador. Nomes são emprestados
/// só na chamada. `state` é retido entre frames; índices -1 = nenhum.
pub export fn zyntra_widget_timeline_view(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    tracks: ?[*]ct.ZyntraTimelineTrack,
    tracks_len: usize,
    state: ?*ct.ZyntraTimelineViewState,
    options: ?*const ct.ZyntraTimelineViewOptions,
    style: ?*const ct.ZyntraTimelineStyle,
    size: f32,
    out_result: ?*ct.ZyntraTimelineViewResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st_c = state orelse return .invalid_argument;
    const opts_c = options orelse return .invalid_argument;
    const sty = style orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;

    const ctx = toCtx(h);
    var args = timelineArgsOf(ctx.allocator, tracks, tracks_len) catch |err| return mapWidgetErr(err);
    defer args.deinit();

    const opts = timeline_view_mod.TimelineViewOptions{
        .min_pps = opts_c.min_pps,
        .max_pps = opts_c.max_pps,
        .zoom_step = opts_c.zoom_step,
        .snap_keys = opts_c.snap_keys,
        .key_hit_px = opts_c.key_hit_px,
    };
    var st = timelineViewStateFromC(st_c.*) catch return .invalid_argument;
    const outcome = timeline_view_mod.timelineView(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        args.tracks,
        &st,
        opts,
        sty.*,
        metrics_mod.FontMetrics.withSize(size),
    );
    args.writeBack();
    st_c.* = timelineViewStateToC(&st);
    const res = outcome catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .hovered_track = fromIndex(res.hovered_track),
        .hovered_key = timelineRefKey(res.hovered_key),
        .selected_track = timelineRefTrack(res.selected),
        .selected_key = timelineRefKey(res.selected),
        .dragging_track = timelineRefTrack(res.dragging_key),
        .dragging_key = timelineRefKey(res.dragging_key),
        .key_delta = res.key_delta,
        .playhead = res.playhead,
        .scrubbing = res.scrubbing,
        .panning = res.panning,
        .zoom_changed = res.zoom_changed,
        .changed = res.changed,
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Inspector: propriedades tipadas, edição e rolagem (M121)
// ---------------------------------------------------------------------------

/// Buffers temporários do inspector: propriedades convertidas e rótulos de
/// escolha achatados. Os valores ficam na memória do chamador (ponteiros).
const InspectorArgs = struct {
    properties: []inspector_mod.Property,
    choice_options: [][]const u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *InspectorArgs) void {
        self.allocator.free(self.properties);
        self.allocator.free(self.choice_options);
    }
};

fn inspectorKindFromC(kind: i32) ?inspector_mod.Kind {
    return switch (kind) {
        0 => .boolean,
        1 => .integer,
        2 => .real,
        3 => .text,
        4 => .choice,
        else => null,
    };
}

/// Fatia UTF-8 emprestada; `len == 0` aceita ponteiro nulo.
fn inspectorStr(s: ct.ZyntraStr) ?[]const u8 {
    if (s.len == 0) return &.{};
    const p = s.ptr orelse return null;
    return p[0..s.len];
}

fn inspectorValuePtr(comptime T: type, p: ?*anyopaque) !*T {
    const q = p orelse return error.InvalidArgument;
    if (@intFromPtr(q) % @alignOf(T) != 0) return error.InvalidArgument;
    return @ptrCast(@alignCast(q));
}

/// Converte props C em props Zig; nomes/textos/rótulos ficam emprestados só
/// durante a chamada e os valores continuam apontando para a memória C.
fn inspectorArgsOf(
    allocator: std.mem.Allocator,
    c_props: ?[*]ct.ZyntraInspectorProperty,
    props_len: usize,
) !InspectorArgs {
    if (props_len > 0 and c_props == null) return error.InvalidArgument;

    var total_options: usize = 0;
    if (props_len > 0) {
        for (c_props.?[0..props_len]) |cp| {
            _ = inspectorKindFromC(cp.kind) orelse return error.InvalidArgument;
            if (cp.kind == @backingInt(ct.ZyntraInspectorKind.choice)) {
                if (cp.choice.options == null or cp.choice.options_len == 0 or cp.choice.index == null) {
                    return error.InvalidArgument;
                }
                total_options = std.math.add(usize, total_options, cp.choice.options_len) catch
                    return error.InvalidArgument;
            }
        }
    }

    const properties = try allocator.alloc(inspector_mod.Property, props_len);
    errdefer allocator.free(properties);
    const choice_options = try allocator.alloc([]const u8, total_options);
    errdefer allocator.free(choice_options);

    var offset: usize = 0;
    if (props_len > 0) {
        for (c_props.?[0..props_len], 0..) |cp, i| {
            const kind = inspectorKindFromC(cp.kind) orelse return error.InvalidArgument;
            const name = inspectorStr(cp.name) orelse return error.InvalidArgument;
            const value: inspector_mod.Value = switch (kind) {
                .boolean => .{ .boolean = try inspectorValuePtr(bool, cp.value) },
                .integer => .{ .integer = try inspectorValuePtr(i64, cp.value) },
                .real => .{ .real = try inspectorValuePtr(f32, cp.value) },
                .text => .{ .text = inspectorStr(cp.text) orelse return error.InvalidArgument },
                .choice => blk: {
                    const idxp = cp.choice.index.?;
                    if (@intFromPtr(idxp) % @alignOf(u32) != 0) return error.InvalidArgument;
                    const idx: *u32 = @ptrCast(@alignCast(idxp));
                    const opt_count = cp.choice.options_len;
                    const opts_ptr = cp.choice.options.?;
                    if (@intFromPtr(opts_ptr) % @alignOf(ct.ZyntraStr) != 0) {
                        return error.InvalidArgument;
                    }
                    const slice = choice_options[offset .. offset + opt_count];
                    for (opts_ptr[0..opt_count], 0..) |s, k| {
                        slice[k] = inspectorStr(s) orelse return error.InvalidArgument;
                    }
                    offset += opt_count;
                    break :blk .{ .choice = .{ .index = idx, .options = slice } };
                },
            };
            properties[i] = .{
                .name = name,
                .value = value,
                .readonly = cp.readonly,
                .step = if (cp.has_step) cp.step else null,
                .decimals = if (cp.has_decimals) cp.decimals else null,
                .range = if (cp.has_range) .{ .min = cp.range.min, .max = cp.range.max } else null,
            };
        }
    }

    return .{
        .properties = properties,
        .choice_options = choice_options,
        .allocator = allocator,
    };
}

/// Índice C (-1 = nenhum) → `?usize`.
fn inspectorIndex(v: i64) ?usize {
    if (v < 0) return null;
    return std.math.cast(usize, v) orelse null;
}

fn inspectorIndexOut(v: ?usize) i64 {
    return if (v) |x| @intCast(x) else -1;
}

fn inspectorViewStateFromC(s: ct.ZyntraInspectorViewState) inspector_view_mod.InspectorViewState {
    return .{
        .active = inspectorIndex(s.active),
        .scroll = s.scroll,
        .dragging = inspectorIndex(s.dragging),
        .drag_anchor = s.drag_anchor,
        .drag_x = s.drag_x,
    };
}

fn inspectorViewStateToC(s: *const inspector_view_mod.InspectorViewState) ct.ZyntraInspectorViewState {
    return .{
        .active = inspectorIndexOut(s.active),
        .scroll = s.scroll,
        .dragging = inspectorIndexOut(s.dragging),
        .drag_anchor = s.drag_anchor,
        .drag_x = s.drag_x,
    };
}

/// Estilo de inspector do tema embutido.
pub export fn zyntra_style_inspector(kind: i32, out_style: ?*ct.ZyntraInspectorStyle) callconv(.c) ct.ZyntraResult {
    const out = out_style orelse return .invalid_argument;
    const t = themeOf(kind) orelse return .invalid_argument;
    out.* = t.inspectorStyle();
    return .ok;
}

/// Inicializa o estado do inspector (nenhuma linha ativa/arraste, rolagem 0).
pub export fn zyntra_inspector_view_state_init(out_state: ?*ct.ZyntraInspectorViewState) callconv(.c) ct.ZyntraResult {
    const out = out_state orelse return .invalid_argument;
    out.* = .{};
    return .ok;
}

/// Preenche as opções de edição com os padrões da API Zig.
pub export fn zyntra_inspector_view_options_default(out_options: ?*ct.ZyntraInspectorViewOptions) callconv(.c) ct.ZyntraResult {
    const out = out_options orelse return .invalid_argument;
    out.* = .{};
    return .ok;
}

/// Desenha e edita propriedades. Os valores são ponteiros para a memória do
/// chamador (o widget lê/escreve por ali); nomes, textos e rótulos de escolha
/// são emprestados só na chamada. `state` é retido entre frames.
pub export fn zyntra_widget_inspector_view(
    handle: ?*ZyntraContext,
    id: ct.ZyntraId,
    bounds: ct.ZyntraRect,
    properties: ?[*]ct.ZyntraInspectorProperty,
    properties_len: usize,
    state: ?*ct.ZyntraInspectorViewState,
    options: ?*const ct.ZyntraInspectorViewOptions,
    style: ?*const ct.ZyntraInspectorStyle,
    size: f32,
    out_result: ?*ct.ZyntraInspectorViewResult,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const st_c = state orelse return .invalid_argument;
    const opts_c = options orelse return .invalid_argument;
    const sty = style orelse return .invalid_argument;
    if (!std.math.isFinite(size) or size <= 0) return .invalid_argument;

    const ctx = toCtx(h);
    var args = inspectorArgsOf(ctx.allocator, properties, properties_len) catch |err| return mapWidgetErr(err);
    defer args.deinit();

    const opts = inspector_view_mod.InspectorViewOptions{
        .step = opts_c.step,
        .decimals = opts_c.decimals,
        .scroll_step = opts_c.scroll_step,
        .coarse_factor = opts_c.coarse_factor,
        .fine_factor = opts_c.fine_factor,
    };
    var st = inspectorViewStateFromC(st_c.*);
    const outcome = inspector_view_mod.inspectorView(
        ctx,
        id_mod.Id.fromU64(id),
        toRect(bounds),
        args.properties,
        &st,
        opts,
        sty.*,
        metrics_mod.FontMetrics.withSize(size),
    );
    st_c.* = inspectorViewStateToC(&st);
    const res = outcome catch |err| return mapWidgetErr(err);
    if (out_result) |o| o.* = .{
        .hovered = inspectorIndexOut(res.hovered),
        .active = inspectorIndexOut(res.active),
        .active_changed = res.active_changed,
        .changed = inspectorIndexOut(res.changed),
        .dragging = inspectorIndexOut(res.dragging),
        .scroll_delta = res.scroll_delta,
        .scrolled = res.scrolled,
    };
    return .ok;
}

// ---------------------------------------------------------------------------
// Animação: easing, tween, timer e cor (M122)
// ---------------------------------------------------------------------------

fn easeFromC(ease: i32) ?anim_mod.Ease {
    return switch (ease) {
        0 => .linear,
        1 => .quad_in,
        2 => .quad_out,
        3 => .quad_in_out,
        4 => .cubic_in,
        5 => .cubic_out,
        6 => .cubic_in_out,
        else => null,
    };
}

fn tweenFromC(t: ct.ZyntraTween) ?anim_mod.Tween {
    const ease = easeFromC(t.ease) orelse return null;
    const tw = anim_mod.Tween.init(t.from, t.to, t.duration, ease) catch return null;
    return tw;
}

fn animTimerValid(t: ct.ZyntraAnimTimer) bool {
    return std.math.isFinite(t.duration) and t.duration > 0 and
        std.math.isFinite(t.elapsed);
}

/// Aplica uma curva de easing (0..1; entradas saturadas).
pub export fn zyntra_ease_apply(
    ease: i32,
    t: f32,
    out_value: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const out = out_value orelse return .invalid_argument;
    const e = easeFromC(ease) orelse return .invalid_argument;
    out.* = e.apply(t);
    return .ok;
}

/// Inicializa um tween (`duration` > 0 e finita; `ease` conhecido).
pub export fn zyntra_tween_init(
    out_tween: ?*ct.ZyntraTween,
    from: f32,
    to: f32,
    duration: f32,
    ease: i32,
) callconv(.c) ct.ZyntraResult {
    const out = out_tween orelse return .invalid_argument;
    const e = easeFromC(ease) orelse return .invalid_argument;
    const tw = anim_mod.Tween.init(from, to, duration, e) catch return .invalid_argument;
    out.* = .{ .from = tw.from, .to = tw.to, .duration = tw.duration, .ease = ease };
    return .ok;
}

/// Valor do tween em `elapsed` segundos (tempo saturado).
pub export fn zyntra_tween_value_at(
    tween: ?*const ct.ZyntraTween,
    elapsed: f32,
    out_value: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const tw_c = tween orelse return .invalid_argument;
    const out = out_value orelse return .invalid_argument;
    const tw = tweenFromC(tw_c.*) orelse return .invalid_argument;
    out.* = tw.valueAt(elapsed);
    return .ok;
}

/// Indica se o tween terminou em `elapsed` segundos.
pub export fn zyntra_tween_done_at(
    tween: ?*const ct.ZyntraTween,
    elapsed: f32,
    out_done: ?*bool,
) callconv(.c) ct.ZyntraResult {
    const tw_c = tween orelse return .invalid_argument;
    const out = out_done orelse return .invalid_argument;
    const tw = tweenFromC(tw_c.*) orelse return .invalid_argument;
    out.* = tw.doneAt(elapsed);
    return .ok;
}

/// Inicializa um cronômetro (`duration` > 0 e finita).
pub export fn zyntra_anim_timer_init(
    out_timer: ?*ct.ZyntraAnimTimer,
    duration: f32,
    looping: bool,
) callconv(.c) ct.ZyntraResult {
    const out = out_timer orelse return .invalid_argument;
    const tm = anim_mod.AnimTimer.init(duration, looping) catch return .invalid_argument;
    out.* = .{ .duration = tm.duration, .elapsed = tm.elapsed, .looping = tm.looping };
    return .ok;
}

/// Zera o tempo decorrido do cronômetro.
pub export fn zyntra_anim_timer_reset(timer: ?*ct.ZyntraAnimTimer) callconv(.c) ct.ZyntraResult {
    const t = timer orelse return .invalid_argument;
    if (!animTimerValid(t.*)) return .invalid_argument;
    t.elapsed = 0;
    return .ok;
}

/// Avança o cronômetro; `dt` negativo/não-finito é ignorado (como na API Zig).
pub export fn zyntra_anim_timer_tick(
    timer: ?*ct.ZyntraAnimTimer,
    dt: f32,
) callconv(.c) ct.ZyntraResult {
    const t = timer orelse return .invalid_argument;
    if (!animTimerValid(t.*)) return .invalid_argument;
    var tm = anim_mod.AnimTimer{ .duration = t.duration, .elapsed = t.elapsed, .looping = t.looping };
    tm.tick(dt);
    t.elapsed = tm.elapsed;
    return .ok;
}

/// Progresso 0..1 (saturado quando não-looping).
pub export fn zyntra_anim_timer_progress(
    timer: ?*const ct.ZyntraAnimTimer,
    out_progress: ?*f32,
) callconv(.c) ct.ZyntraResult {
    const t = timer orelse return .invalid_argument;
    const out = out_progress orelse return .invalid_argument;
    if (!animTimerValid(t.*)) return .invalid_argument;
    const tm = anim_mod.AnimTimer{ .duration = t.duration, .elapsed = t.elapsed, .looping = t.looping };
    out.* = tm.progress();
    return .ok;
}

/// Indica se o cronômetro (não-looping) terminou.
pub export fn zyntra_anim_timer_done(
    timer: ?*const ct.ZyntraAnimTimer,
    out_done: ?*bool,
) callconv(.c) ct.ZyntraResult {
    const t = timer orelse return .invalid_argument;
    const out = out_done orelse return .invalid_argument;
    if (!animTimerValid(t.*)) return .invalid_argument;
    const tm = anim_mod.AnimTimer{ .duration = t.duration, .elapsed = t.elapsed, .looping = t.looping };
    out.* = tm.done();
    return .ok;
}

/// Interpola duas cores por canal (`t` saturado, alfa incluído).
pub export fn zyntra_anim_lerp_color(
    a: ct.ZyntraColor,
    b: ct.ZyntraColor,
    t: f32,
    out_color: ?*ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const out = out_color orelse return .invalid_argument;
    out.* = fromColor(anim_mod.lerpColor(toColor(a), toColor(b), t));
    return .ok;
}

test "C-ABI ciclo completo via símbolos exportados" {
    const stdt = @import("std");
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_context_create(.{ .x = 0, .y = 0, .w = 800, .h = 600 }, &handle),
    );
    defer zyntra_context_destroy(handle);
    try stdt.testing.expect(handle != null);

    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_begin_frame(handle));
    // begin duplo é erro de estado, sem crash:
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_state, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_push_mouse_move(handle, .{ .x = 5, .y = 6 }));
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 5, .y = 6 }),
    );
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_argument, zyntra_context_push_mouse_button(handle, 9, true, .{ .x = 0, .y = 0 }));
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_rect_filled(handle, .{ .x = 0, .y = 0, .w = 10, .h = 10 }, .{ .r = 255 }),
    );
    // rect negativo é comando inválido, contagem preservada:
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_rect_filled(handle, .{ .x = 0, .y = 0, .w = -1, .h = 5 }, .{}),
    );
    var n_events: usize = 99;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_pending_events(handle, &n_events));
    try stdt.testing.expectEqual(@as(usize, 2), n_events);
    var n_draw: usize = 99;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 1), n_draw);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_end_frame(handle));
    // end sem begin é erro de estado:
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_state, zyntra_context_end_frame(handle));
    var idx: u64 = 99;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_frame_index(handle, &idx));
    try stdt.testing.expectEqual(@as(u64, 1), idx);

    // Nulos nunca crasham:
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_argument, zyntra_context_begin_frame(null));
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_argument, zyntra_context_create(.{}, null));
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_argument, zyntra_context_frame_index(handle, null));
    zyntra_context_destroy(null); // null-safe
}

test "C-ABI draw_text copia, valida e conta" {
    const stdt = @import("std");
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_context_create(.{ .x = 0, .y = 0, .w = 800, .h = 600 }, &handle),
    );
    defer zyntra_context_destroy(handle);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_begin_frame(handle));

    const hello = "Hi";
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_text(handle, .{ .x = 1, .y = 2 }, .{ .r = 255 }, 16, hello.ptr, hello.len),
    );
    // Run vazio com NULL é válido:
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_text(handle, .{ .x = 0, .y = 0 }, .{}, 16, null, 0),
    );
    // UTF-8 malformado, size inválido e ptr nulo com len:
    const bad = "\xff";
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_text,
        zyntra_draw_text(handle, .{ .x = 0, .y = 0 }, .{}, 16, bad.ptr, bad.len),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_draw_text(handle, .{ .x = 0, .y = 0 }, .{}, 0, hello.ptr, hello.len),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_draw_text(handle, .{ .x = 0, .y = 0 }, .{}, 16, null, 3),
    );
    var n_draw: usize = 99;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 2), n_draw);
    // Bytes copiados: sobrevivem ao buffer original.
    const cmds = toCtx(handle.?).drawCommands();
    try stdt.testing.expectEqualStrings("Hi", toCtx(handle.?).draw.textOf(cmds[0]));
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_end_frame(handle));
}

test "C-ABI desenho moderno + clip + métricas de texto" {
    const stdt = @import("std");
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_context_create(.{ .x = 0, .y = 0, .w = 200, .h = 100 }, &handle),
    );
    defer zyntra_context_destroy(handle);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_begin_frame(handle));

    const white: ct.ZyntraColor = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const dark: ct.ZyntraColor = .{ .r = 10, .g = 10, .b = 20, .a = 255 };
    const rect: ct.ZyntraRect = .{ .x = 10, .y = 10, .w = 40, .h = 30 };

    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_clear(handle, dark));
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_clip(handle, rect));
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_rect_shadow(handle, rect, 6, .{ .x = 0, .y = 2 }, 4, dark),
    );
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_rect_rounded(handle, rect, 6, white));
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_rect_gradient(handle, rect, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 30 }, white, dark),
    );
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_rect_outline(handle, rect, white, 1.5));
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_line(handle, .{ .x = 0, .y = 0 }, .{ .x = 40, .y = 30 }, white, 2),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_circle_filled(handle, .{ .x = 30, .y = 20 }, 8, white),
    );
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_blur(handle, rect, 3));
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_clip_reset(handle));

    // Inválidos são rejeitados sem enfileirar:
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_rect_rounded(handle, rect, -1, white),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_line(handle, .{ .x = std.math.nan(f32), .y = 0 }, .{}, white, 1),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_rect_outline(handle, rect, white, 0),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_draw_blur(null, rect, 3),
    );

    var n: usize = 0;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_count(handle, &n));
    try stdt.testing.expectEqual(@as(usize, 10), n);

    // Métricas de texto espelham a API Zig (avanço fixo por glifo).
    const font = metrics_mod.FontMetrics.withSize(10);
    const zig = try metrics_mod.measure("abc", font);
    var w: f32 = 0;
    var h: f32 = 0;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_text_measure("abc", 3, 10, &w, &h));
    try stdt.testing.expectEqual(zig.width, w);
    try stdt.testing.expectEqual(zig.height, h);

    var kept: usize = 99;
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_text_truncate("abcdef", 6, 10, font.advance * 3.5, &kept),
    );
    try stdt.testing.expectEqual(@as(usize, 3), kept);

    // Rejeições de texto/argumentos:
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_text,
        zyntra_text_measure("\xff", 1, 10, &w, &h),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_text_measure("a", 1, 0, &w, &h),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_text_measure("a", 1, 10, null, &h),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_text_truncate("a", 1, 10, -1, &kept),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_text_truncate("a", 1, 10, 5, null),
    );
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_end_frame(handle));
}

test "C-ABI versão espelha constantes Zig" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(types_mod.version_major, zyntra_version_major());
    try stdt.testing.expectEqual(types_mod.version_minor, zyntra_version_minor());
    try stdt.testing.expectEqual(types_mod.version_patch, zyntra_version_patch());
    const pre = std.mem.span(zyntra_version_prerelease());
    try stdt.testing.expectEqualStrings(types_mod.version_prerelease, pre);
}

test "C-ABI pixels: framebuffer, render integral/parcial e dirty rect" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;

    // Dimensões inválidas são rejeitadas sem alocar.
    var bad: ?*ZyntraFramebuffer = null;
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_create(0, 32, &bad));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_create(32, 9000, &bad));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_create(32, 32, null));

    var fb_handle: ?*ZyntraFramebuffer = null;
    try eq(ok, zyntra_framebuffer_create(64, 32, &fb_handle));
    defer zyntra_framebuffer_destroy(fb_handle);
    var ctx_handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 64, .h = 32 }, &ctx_handle));
    defer zyntra_context_destroy(ctx_handle);

    var fw: u32 = 0;
    var fh: u32 = 0;
    try eq(ok, zyntra_framebuffer_size(fb_handle, &fw, &fh));
    try eq(@as(u32, 64), fw);
    try eq(@as(u32, 32), fh);
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_size(fb_handle, &fw, null));

    const bg: ct.ZyntraColor = .{ .r = 10, .g = 20, .b = 30, .a = 255 };
    const red: ct.ZyntraColor = .{ .r = 200, .g = 40, .b = 40, .a = 255 };
    const white: ct.ZyntraColor = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const black: ct.ZyntraColor = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const green: ct.ZyntraColor = .{ .r = 0, .g = 200, .b = 60, .a = 255 };
    const blue: ct.ZyntraColor = .{ .r = 40, .g = 80, .b = 220, .a = 255 };

    // `fill` cobre o framebuffer inteiro antes de qualquer frame.
    try eq(ok, zyntra_framebuffer_fill(fb_handle, bg));
    var px: ct.ZyntraColor = .{};
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 63, 31, &px));
    try eq(bg.r, px.r);

    // Frame 1: clear + retângulo + gradiente + cantos arredondados.
    const box: ct.ZyntraRect = .{ .x = 4, .y = 4, .w = 16, .h = 16 };
    const grad_box: ct.ZyntraRect = .{ .x = 32, .y = 4, .w = 24, .h = 16 };
    const round_box: ct.ZyntraRect = .{ .x = 4, .y = 20, .w = 20, .h = 10 };
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, bg));
    try eq(ok, zyntra_draw_rect_filled(ctx_handle, box, red));
    try eq(ok, zyntra_draw_rect_gradient(ctx_handle, grad_box, .{ .x = 32, .y = 4 }, .{ .x = 56, .y = 4 }, white, black));
    try eq(ok, zyntra_draw_rect_rounded(ctx_handle, round_box, 5, green));

    // Dirty rect: união dos dois primeiros rects; limpar zera.
    try eq(ok, zyntra_context_mark_dirty(ctx_handle, box));
    try eq(ok, zyntra_context_mark_dirty(ctx_handle, grad_box));
    var dirty: ct.ZyntraRect = .{};
    try eq(ok, zyntra_context_dirty_rect(ctx_handle, &dirty));
    try eq(@as(f32, 4), dirty.x);
    try eq(@as(f32, 52), dirty.w);
    try eq(ok, zyntra_context_clear_dirty(ctx_handle));
    try eq(ok, zyntra_context_dirty_rect(ctx_handle, &dirty));
    try stdt.testing.expect(dirty.w == 0 and dirty.h == 0);

    var stats: ct.ZyntraRenderStats = .{};
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, &stats));
    try eq(@as(u32, 4), stats.submitted);
    try eq(@as(u32, 4), stats.drawn);
    try eq(@as(u32, 0), stats.culled);

    // Pixels: retângulo, fundo, gradiente nos dois extremos, canto
    // arredondado dentro/fora.
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 12, 12, &px));
    try eq(red.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 2, 2, &px));
    try eq(bg.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 33, 10, &px));
    try stdt.testing.expect(px.r > 200);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 55, 10, &px));
    try stdt.testing.expect(px.r < 60);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 14, 25, &px));
    try eq(green.g, px.g);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 4, 20, &px));
    try eq(bg.r, px.r);
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_pixel(fb_handle, 64, 0, &px));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_pixel(fb_handle, 0, 32, &px));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_pixel(fb_handle, 0, 0, null));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_pixel(null, 0, 0, &px));
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Frame 2 (parcial): só a região marcada é repintada; o resto do
    // framebuffer mantém o frame anterior.
    const patch: ct.ZyntraRect = .{ .x = 40, .y = 20, .w = 14, .h = 10 };
    const patch_box: ct.ZyntraRect = .{ .x = 40, .y = 20, .w = 12, .h = 8 };
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, bg));
    try eq(ok, zyntra_draw_rect_filled(ctx_handle, patch_box, blue));
    try eq(ok, zyntra_context_mark_dirty(ctx_handle, patch));
    var part: ct.ZyntraRenderStats = .{};
    try eq(ok, zyntra_framebuffer_render_region(fb_handle, ctx_handle, patch, &part));
    try eq(@as(u32, 2), part.submitted);
    try eq(@as(u32, 2), part.drawn);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 45, 24, &px));
    try eq(blue.b, px.b);
    // Dentro da região, fora do rect: o clear parcial pintou o fundo.
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 53, 29, &px));
    try eq(bg.r, px.r);
    // Fora da região: retângulo e gradiente do frame anterior intactos.
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 12, 12, &px));
    try eq(red.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 55, 10, &px));
    try stdt.testing.expect(px.r < 60);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Nulos nunca crasham.
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_render(null, ctx_handle, null));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_render(fb_handle, null, null));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_render_region(fb_handle, null, patch, null));
    try eq(ok, zyntra_framebuffer_render_region(fb_handle, ctx_handle, patch, null));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_framebuffer_fill(null, bg));
    try eq(ct.ZyntraResult.invalid_argument, zyntra_context_mark_dirty(null, box));
    zyntra_framebuffer_destroy(null);
}

test "C-ABI widgets: ids, estilos do tema e primeiro lote desenhado" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;

    // Ids: string vazia/NULL é nulo; o mesmo texto dá o mesmo id.
    try eq(@as(ct.ZyntraId, 0), zyntra_id_from_string("", 0));
    try eq(@as(ct.ZyntraId, 0), zyntra_id_from_string(null, 3));
    const id = zyntra_id_from_string("c:btn", 5);
    try stdt.testing.expect(id != 0);
    try eq(id, zyntra_id_from_string("c:btn", 5));
    try stdt.testing.expect(zyntra_id_child(id, 0) != zyntra_id_child(id, 1));
    try eq(@as(ct.ZyntraId, 0), zyntra_id_child(0, 1));

    // Tema: cores base (escuro mais escuro que claro) e estilos.
    var dark: ct.ZyntraThemeColors = .{};
    var light: ct.ZyntraThemeColors = .{};
    try eq(ok, zyntra_theme_colors(0, &dark));
    try eq(ok, zyntra_theme_colors(1, &light));
    try stdt.testing.expect(dark.bg.r < light.bg.r);
    try eq(bad, zyntra_theme_colors(2, &dark));
    try eq(bad, zyntra_theme_colors(0, null));

    var bs: ct.ZyntraButtonStyle = undefined;
    var bsl: ct.ZyntraButtonStyle = undefined;
    var cs: ct.ZyntraCheckboxStyle = undefined;
    var ss: ct.ZyntraSwitchStyle = undefined;
    var sls: ct.ZyntraSliderStyle = undefined;
    var ps: ct.ZyntraProgressStyle = undefined;
    var ses: ct.ZyntraSeparatorStyle = undefined;
    try eq(ok, zyntra_style_button(0, &bs));
    try eq(ok, zyntra_style_button(1, &bsl));
    try eq(ok, zyntra_style_checkbox(0, &cs));
    try eq(ok, zyntra_style_switch(0, &ss));
    try eq(ok, zyntra_style_slider(0, &sls));
    try eq(ok, zyntra_style_progress(0, &ps));
    try eq(ok, zyntra_style_separator(0, &ses));
    try stdt.testing.expect(bs.bg.r != bsl.bg.r);
    try eq(bad, zyntra_style_button(3, &bs));
    try eq(bad, zyntra_style_button(0, null));

    var ctx_handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 96, .h = 64 }, &ctx_handle));
    defer zyntra_context_destroy(ctx_handle);
    var fb_handle: ?*ZyntraFramebuffer = null;
    try eq(ok, zyntra_framebuffer_create(96, 64, &fb_handle));
    defer zyntra_framebuffer_destroy(fb_handle);

    // Frame frio: um de cada widget do lote.
    const bounds: ct.ZyntraRect = .{ .x = 4, .y = 4, .w = 40, .h = 16 };
    var label_res: ct.ZyntraLabelResult = .{};
    var btn_res: ct.ZyntraButtonResult = .{};
    var chk_res: ct.ZyntraCheckboxResult = .{};
    var sw_res: ct.ZyntraSwitchResult = .{};
    var sl_res: ct.ZyntraSliderResult = .{};
    var checked = false;
    var switched = true;
    var value: f32 = 30;
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, dark.bg));
    try eq(ok, zyntra_widget_label(ctx_handle, id, .{ .x = 6, .y = 6, .w = 36, .h = 12 }, dark.text, 10, "Ok", 2, false, &label_res));
    try stdt.testing.expect(label_res.metrics.width > 0 and !label_res.truncated);
    try eq(ok, zyntra_widget_button(ctx_handle, id, bounds, &bs, &btn_res));
    try stdt.testing.expect(!btn_res.clicked and !btn_res.hovered);
    try eq(ok, zyntra_widget_checkbox(ctx_handle, zyntra_id_child(id, 1), .{ .x = 4, .y = 26, .w = 18, .h = 18 }, &checked, &cs, &chk_res));
    try eq(false, chk_res.checked);
    try eq(ok, zyntra_widget_switch(ctx_handle, zyntra_id_child(id, 2), .{ .x = 28, .y = 26, .w = 36, .h = 18 }, &switched, &ss, &sw_res));
    try eq(true, sw_res.checked);
    try eq(ok, zyntra_widget_slider(ctx_handle, zyntra_id_child(id, 3), .{ .x = 4, .y = 48, .w = 88, .h = 12 }, &value, 0, 100, &sls, &sl_res));
    try eq(@as(f32, 30), sl_res.value);
    try eq(ok, zyntra_widget_progress(ctx_handle, .{ .x = 4, .y = 60, .w = 88, .h = 4 }, 0.5, &ps));
    try eq(ok, zyntra_widget_separator(ctx_handle, .{ .x = 4, .y = 30, .w = 88, .h = 2 }, 0, &ses));

    // Estilos inválidos e argumentos nulos são rejeitados sem crash.
    var bad_bs = bs;
    bad_bs.radius = -1;
    try eq(bad, zyntra_widget_button(ctx_handle, id, bounds, &bad_bs, null));
    try eq(bad, zyntra_widget_button(ctx_handle, 0, bounds, &bs, null));
    try eq(bad, zyntra_widget_button(ctx_handle, id, bounds, null, null));
    try eq(bad, zyntra_widget_label(ctx_handle, id, bounds, dark.text, 0, "x", 1, false, null));
    try eq(bad, zyntra_widget_label(ctx_handle, id, bounds, dark.text, 10, null, 3, false, null));
    try eq(ct.ZyntraResult.invalid_text, zyntra_widget_label(ctx_handle, id, bounds, dark.text, 10, "\xff", 1, false, null));
    try eq(ok, zyntra_widget_label(ctx_handle, id, bounds, dark.text, 10, null, 0, false, null));
    try eq(bad, zyntra_widget_checkbox(ctx_handle, id, bounds, null, &cs, null));
    try eq(bad, zyntra_widget_switch(ctx_handle, id, bounds, null, &ss, null));
    try eq(bad, zyntra_widget_slider(ctx_handle, id, bounds, null, 0, 1, &sls, null));
    try eq(bad, zyntra_widget_progress(ctx_handle, bounds, 0.5, null));
    try eq(bad, zyntra_widget_separator(ctx_handle, bounds, 9, &ses));
    try eq(bad, zyntra_widget_separator(null, bounds, 0, &ses));

    // Rasteriza: botão no centro, fundo fora dele.
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, null));
    var px: ct.ZyntraColor = .{};
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 24, 12, &px));
    try eq(bs.bg.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 90, 2, &px));
    try eq(dark.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Press sobre o botão: press_owner + `pressed` (sem clique ainda).
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 24, .y = 12 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 24, .y = 12 }));
    try eq(ok, zyntra_widget_button(ctx_handle, id, bounds, &bs, &btn_res));
    try stdt.testing.expect(btn_res.hovered and btn_res.pressed and !btn_res.clicked);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Release sobre o botão: clique.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 24, .y = 12 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, false, .{ .x = 24, .y = 12 }));
    try eq(ok, zyntra_widget_button(ctx_handle, id, bounds, &bs, &btn_res));
    try stdt.testing.expect(btn_res.clicked);
    try eq(ok, zyntra_context_end_frame(ctx_handle));
}

test "C-ABI listas: abas, lista, radio e painel" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;

    // Estilos do tema (tamanhos travados em types.zig).
    var rs: ct.ZyntraRadioStyle = undefined;
    var tbs: ct.ZyntraTabBarStyle = undefined;
    var lvs: ct.ZyntraListViewStyle = undefined;
    var pans: ct.ZyntraPanelStyle = undefined;
    try eq(ok, zyntra_style_radio(0, &rs));
    try eq(ok, zyntra_style_tab_bar(0, &tbs));
    try eq(ok, zyntra_style_list_view(0, &lvs));
    try eq(ok, zyntra_style_panel(0, &pans));
    try eq(bad, zyntra_style_radio(5, &rs));
    try eq(bad, zyntra_style_panel(0, null));
    lvs.item_height = 20; // linhas previsíveis para os pixels abaixo

    var ctx_handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 160, .h = 160 }, &ctx_handle));
    defer zyntra_context_destroy(ctx_handle);
    var fb_handle: ?*ZyntraFramebuffer = null;
    try eq(ok, zyntra_framebuffer_create(160, 160, &fb_handle));
    defer zyntra_framebuffer_destroy(fb_handle);

    const id = zyntra_id_from_string("c:lists", 7);
    const tabs = [_]ct.ZyntraStr{ .{ .ptr = "A", .len = 1 }, .{ .ptr = "BB", .len = 2 } };
    const items = [_]ct.ZyntraStr{
        .{ .ptr = "a", .len = 1 },
        .{ .ptr = "b", .len = 1 },
        .{ .ptr = "c", .len = 1 },
    };
    const opts = [_]ct.ZyntraStr{
        .{ .ptr = "x", .len = 1 },
        .{ .ptr = "y", .len = 1 },
        .{ .ptr = "z", .len = 1 },
    };
    const panel_title: ct.ZyntraPanelOptions = .{ .title = .{ .ptr = "P", .len = 1 } };
    const tab_bounds: ct.ZyntraRect = .{ .x = 0, .y = 0, .w = 160, .h = 24 };
    const list_bounds: ct.ZyntraRect = .{ .x = 0, .y = 28, .w = 80, .h = 60 };
    const radio_bounds: ct.ZyntraRect = .{ .x = 84, .y = 28, .w = 76, .h = 60 };
    const panel_bounds: ct.ZyntraRect = .{ .x = 0, .y = 92, .w = 160, .h = 60 };
    var tbres: ct.ZyntraTabBarResult = .{};
    var lvres: ct.ZyntraListViewResult = .{};
    var rares: ct.ZyntraRadioResult = .{};
    var panres: ct.ZyntraPanelResult = .{};
    var active: usize = 0;
    var selected: usize = 0;
    var radio_sel: usize = 0;
    var scroll: f32 = 0;
    var collapsed = false;
    var px: ct.ZyntraColor = .{};

    // Frame frio: um de cada, rasterizado (sem mouse sobre nenhum).
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 0, .y = 159 }));
    try eq(ok, zyntra_draw_clear(ctx_handle, .{ .r = 24, .g = 24, .b = 28, .a = 255 }));
    try eq(ok, zyntra_widget_tab_bar(ctx_handle, id, tab_bounds, &tabs, tabs.len, &active, &tbs, &tbres));
    try stdt.testing.expect(!tbres.changed and tbres.active == 0 and tbres.hovered_index == -1);
    try eq(ok, zyntra_widget_list_view(ctx_handle, id, list_bounds, &items, items.len, &selected, &scroll, &lvs, &lvres));
    try stdt.testing.expect(lvres.selected == 0 and lvres.hovered_index == -1 and lvres.scroll_offset == 0);
    try eq(ok, zyntra_widget_radio(ctx_handle, id, radio_bounds, &opts, opts.len, &radio_sel, 10, &rs, &rares));
    try stdt.testing.expect(!rares.changed and radio_sel == 0);
    try eq(ok, zyntra_widget_panel(ctx_handle, id, panel_bounds, &collapsed, panel_title, 10, &pans, &panres));
    try stdt.testing.expect(!panres.collapsed and !panres.toggled and panres.content.w > 0);

    // Inválidos: listas nulas, ptr nulo com len > 0, estados nulos, size.
    try eq(bad, zyntra_widget_tab_bar(ctx_handle, id, tab_bounds, null, 2, &active, &tbs, null));
    try eq(bad, zyntra_widget_list_view(ctx_handle, id, list_bounds, null, 1, &selected, &scroll, &lvs, null));
    const broken = [_]ct.ZyntraStr{.{ .ptr = null, .len = 3 }};
    try eq(bad, zyntra_widget_radio(ctx_handle, id, radio_bounds, &broken, 1, &radio_sel, 10, &rs, null));
    try eq(bad, zyntra_widget_radio(ctx_handle, id, radio_bounds, &opts, opts.len, null, 10, &rs, null));
    try eq(bad, zyntra_widget_radio(ctx_handle, id, radio_bounds, &opts, opts.len, &radio_sel, 0, &rs, null));
    try eq(bad, zyntra_widget_list_view(ctx_handle, id, list_bounds, &items, items.len, &selected, null, &lvs, null));
    try eq(bad, zyntra_widget_tab_bar(ctx_handle, id, tab_bounds, &tabs, tabs.len, &active, null, null));
    try eq(bad, zyntra_widget_panel(ctx_handle, id, panel_bounds, null, panel_title, 10, &pans, null));
    try eq(bad, zyntra_widget_panel(ctx_handle, id, panel_bounds, &collapsed, .{}, 0, &pans, null));
    try eq(bad, zyntra_widget_panel(null, id, panel_bounds, &collapsed, panel_title, 10, &pans, null));

    // Pixels: aba ativa/inativa, linha selecionada/normal, ponto do radio e
    // cabeçalho/corpo do painel.
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 15, 12, &px));
    try eq(tbs.bg_active.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 48, 12, &px));
    try eq(tbs.bg.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 38, &px));
    try eq(lvs.bg_selected.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 58, &px));
    try eq(lvs.bg.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 95, 37, &px));
    try eq(rs.dot.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 95, 56, &px));
    try eq(rs.box.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 96, &px));
    try eq(pans.header_bg.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 130, &px));
    try eq(pans.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Clique na aba 1 (x = 30..66 com advance 6 e padding_x 12).
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 48, .y = 12 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 48, .y = 12 }));
    try eq(ok, zyntra_widget_tab_bar(ctx_handle, id, tab_bounds, &tabs, tabs.len, &active, &tbs, &tbres));
    try stdt.testing.expect(tbres.changed and tbres.active == 1 and active == 1);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Clique na linha 2 da lista.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 20, .y = 78 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 20, .y = 78 }));
    try eq(ok, zyntra_widget_list_view(ctx_handle, id, list_bounds, &items, items.len, &selected, &scroll, &lvs, &lvres));
    try stdt.testing.expect(lvres.changed and lvres.selected == 2 and selected == 2);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Press na opção 1 do radio (seleção é one-shot no press).
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 95, .y = 56 }));
    try eq(ok, zyntra_widget_radio(ctx_handle, id, radio_bounds, &opts, opts.len, &radio_sel, 10, &rs, &rares));
    try stdt.testing.expect(rares.changed and radio_sel == 1);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Painel: press + release no chevron (canto superior direito) colapsa.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 143, .y = 103 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 143, .y = 103 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, false, .{ .x = 143, .y = 103 }));
    try eq(ok, zyntra_widget_panel(ctx_handle, id, panel_bounds, &collapsed, panel_title, 10, &pans, &panres));
    try stdt.testing.expect(collapsed and panres.toggled and panres.content.w == 0);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Lista maior que o scratch da pilha: caminho com alocação do contexto.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    var big: [70]ct.ZyntraStr = undefined;
    for (&big) |*s| s.* = .{ .ptr = "op", .len = 2 };
    var big_sel: usize = 69;
    var big_res: ct.ZyntraRadioResult = .{};
    try eq(ok, zyntra_widget_radio(ctx_handle, id, radio_bounds, &big, big.len, &big_sel, 10, &rs, &big_res));
    try stdt.testing.expect(big_sel == 69 and !big_res.changed);
    try eq(ok, zyntra_context_end_frame(ctx_handle));
}

test "C-ABI estruturas: menu e tabela" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;

    var ms: ct.ZyntraMenuStyle = undefined;
    var ts: ct.ZyntraTableStyle = undefined;
    try eq(ok, zyntra_style_menu(0, &ms));
    try eq(ok, zyntra_style_table(0, &ts));
    try eq(bad, zyntra_style_menu(2, &ms));
    try eq(bad, zyntra_style_table(1, null));

    var ctx_handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 240, .h = 200 }, &ctx_handle));
    defer zyntra_context_destroy(ctx_handle);
    var fb_handle: ?*ZyntraFramebuffer = null;
    try eq(ok, zyntra_framebuffer_create(240, 200, &fb_handle));
    defer zyntra_framebuffer_destroy(fb_handle);

    const id = zyntra_id_from_string("c:rich", 6);
    const menu_bounds: ct.ZyntraRect = .{ .x = 8, .y = 8, .w = 160, .h = 104 };
    const table_bounds: ct.ZyntraRect = .{ .x = 8, .y = 120, .w = 220, .h = 72 };
    // size 16 ⇒ altura de item do menu = 17 + 8 = 25 px (linhas previsíveis).
    const menu_items = [_]ct.ZyntraMenuItem{
        .{ .label = .{ .ptr = "Abrir", .len = 5 } },
        .{ .label = .{ .ptr = "", .len = 0 }, .separator = true },
        .{ .label = .{ .ptr = "Salvar", .len = 6 }, .shortcut = .{ .ptr = "Ctrl+S", .len = 6 }, .has_checked = true, .checked = true },
        .{ .label = .{ .ptr = "Sair", .len = 4 }, .enabled = false },
    };
    const columns = [_]ct.ZyntraTableColumn{
        .{ .title = .{ .ptr = "Nome", .len = 4 }, .width = 120 },
        .{ .title = .{ .ptr = "Tipo", .len = 4 }, .width = 100 },
    };
    const row_cells = [_][2]ct.ZyntraStr{
        .{ .{ .ptr = "um", .len = 2 }, .{ .ptr = "tipo1", .len = 5 } },
        .{ .{ .ptr = "dois", .len = 4 }, .{ .ptr = "tipo2", .len = 5 } },
        .{ .{ .ptr = "tres", .len = 4 }, .{ .ptr = "tipo3", .len = 5 } },
    };
    const rows = [_]ct.ZyntraTableRow{
        .{ .cells = &row_cells[0], .cells_len = 2 },
        .{ .cells = &row_cells[1], .cells_len = 2 },
        .{ .cells = &row_cells[2], .cells_len = 2 },
    };
    var mres: ct.ZyntraMenuResult = .{};
    var tres: ct.ZyntraTableResult = .{};
    var active: usize = 0;
    var selected: usize = 0;
    var scroll: f32 = 0;
    var px: ct.ZyntraColor = .{};

    // Frame frio: menu sem hover e tabela com linha 0 selecionada.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 236, .y = 196 }));
    try eq(ok, zyntra_draw_clear(ctx_handle, .{ .r = 24, .g = 24, .b = 28, .a = 255 }));
    try eq(ok, zyntra_widget_menu(ctx_handle, id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(mres.chosen == -1 and mres.hovered_index == -1 and !mres.hovered and !mres.dismissed);
    try eq(ok, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, columns.len, &rows, rows.len, &selected, &scroll, &ts, &tres));
    try stdt.testing.expect(tres.selected == 0 and tres.hovered_index == -1 and !tres.changed);
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 50, 20, &px));
    try eq(ms.bg.r, px.r); // linha 0 sem hover
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 130, &px));
    try eq(ts.bg.r, px.r); // cabeçalho
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 158, &px));
    try eq(ts.bg_selected.r, px.r); // linha 0 selecionada
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 182, &px));
    try eq(ts.bg_alt.r, px.r); // linha 1 alternada
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Hover na linha 2 do menu (y 58..83): realce + índice no resultado.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, .{ .r = 24, .g = 24, .b = 28, .a = 255 }));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 50, .y = 70 }));
    try eq(ok, zyntra_widget_menu(ctx_handle, id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(mres.hovered and mres.hovered_index == 2 and active == 2);
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 50, 70, &px));
    try eq(ms.item_hover.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 50, 20, &px));
    try eq(ms.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Press na linha 2 escolhe (one-shot); press fora dispensa.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 50, .y = 70 }));
    try eq(ok, zyntra_widget_menu(ctx_handle, id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(mres.chosen == 2 and !mres.dismissed);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 236, .y = 196 }));
    try eq(ok, zyntra_widget_menu(ctx_handle, id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(mres.chosen == -1 and mres.dismissed);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Tabela: clique na linha 1 (y 170..194) muda a seleção.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, .{ .r = 24, .g = 24, .b = 28, .a = 255 }));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 20, .y = 182 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 20, .y = 182 }));
    try eq(ok, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, columns.len, &rows, rows.len, &selected, &scroll, &ts, &tres));
    try stdt.testing.expect(tres.changed and tres.selected == 1 and selected == 1);
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 182, &px));
    try eq(ts.bg_selected.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 158, &px));
    try eq(ts.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Inválidos: vetores nulos, célula sem ponteiro, estados nulos, size,
    // colunas vazias e bounds sem corpo.
    try eq(bad, zyntra_widget_menu(ctx_handle, id, menu_bounds, null, 3, &active, 16, &ms, null));
    try eq(bad, zyntra_widget_menu(ctx_handle, id, menu_bounds, &menu_items, menu_items.len, &active, 0, &ms, null));
    try eq(bad, zyntra_widget_menu(ctx_handle, id, menu_bounds, &menu_items, menu_items.len, null, 16, &ms, null));
    const broken_items = [_]ct.ZyntraMenuItem{.{ .label = .{ .ptr = null, .len = 3 } }};
    try eq(bad, zyntra_widget_menu(ctx_handle, id, menu_bounds, &broken_items, 1, &active, 16, &ms, null));
    try eq(bad, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, 0, &rows, rows.len, &selected, &scroll, &ts, null));
    try eq(bad, zyntra_widget_table(ctx_handle, id, table_bounds, null, 2, &rows, rows.len, &selected, &scroll, &ts, null));
    try eq(bad, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, columns.len, null, 1, &selected, &scroll, &ts, null));
    try eq(bad, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, columns.len, &rows, rows.len, null, &scroll, &ts, null));
    try eq(bad, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, columns.len, &rows, rows.len, &selected, null, &ts, null));
    const broken_rows = [_]ct.ZyntraTableRow{.{ .cells = null, .cells_len = 2 }};
    try eq(bad, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, columns.len, &broken_rows, 1, &selected, &scroll, &ts, null));
    const short_bounds: ct.ZyntraRect = .{ .x = 8, .y = 120, .w = 220, .h = 20 };
    try eq(bad, zyntra_widget_table(ctx_handle, id, short_bounds, &columns, columns.len, &rows, rows.len, &selected, &scroll, &ts, null));

    // Tabela maior que o scratch da pilha (65 linhas): caminho com alocação.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    var many_cells: [65][1]ct.ZyntraStr = undefined;
    var many_rows: [65]ct.ZyntraTableRow = undefined;
    for (&many_cells, 0..) |*cells, i| {
        cells[0] = .{ .ptr = "linha", .len = 5 };
        many_rows[i] = .{ .cells = cells, .cells_len = 1 };
    }
    var many_sel: usize = 64;
    var many_scroll: f32 = 0;
    try eq(ok, zyntra_widget_table(ctx_handle, id, table_bounds, &columns, columns.len, &many_rows, many_rows.len, &many_sel, &many_scroll, &ts, &tres));
    try stdt.testing.expect(many_sel == 64 and tres.selected == 64 and !tres.changed);
    try eq(ok, zyntra_context_end_frame(ctx_handle));
}

test "C-ABI árvore: tree_view com estado devolvido" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;

    var tvs: ct.ZyntraTreeViewStyle = undefined;
    try eq(ok, zyntra_style_tree_view(0, &tvs));
    try eq(bad, zyntra_style_tree_view(9, &tvs));
    try eq(bad, zyntra_style_tree_view(0, null));

    var ctx_handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 240, .h = 200 }, &ctx_handle));
    defer zyntra_context_destroy(ctx_handle);
    var fb_handle: ?*ZyntraFramebuffer = null;
    try eq(ok, zyntra_framebuffer_create(240, 200, &fb_handle));
    defer zyntra_framebuffer_destroy(fb_handle);

    const id = zyntra_id_from_string("c:tree", 6);
    const bounds: ct.ZyntraRect = .{ .x = 8, .y = 8, .w = 200, .h = 128 };
    // src > (ui > widget.zig, app.zig), build.zig
    var neto = [_]ct.ZyntraTreeItem{.{ .label = .{ .ptr = "widget.zig", .len = 10 } }};
    var filhos = [_]ct.ZyntraTreeItem{
        .{ .label = .{ .ptr = "ui", .len = 2 }, .children = &neto, .children_len = 1 },
        .{ .label = .{ .ptr = "app.zig", .len = 7 } },
    };
    var raizes = [_]ct.ZyntraTreeItem{
        .{ .label = .{ .ptr = "src", .len = 3 }, .children = &filhos, .children_len = 2 },
        .{ .label = .{ .ptr = "build.zig", .len = 9 } },
    };
    var res: ct.ZyntraTreeViewResult = .{};
    var selected: usize = 0;
    var scroll: f32 = 0;
    var px: ct.ZyntraColor = .{};

    // Frame frio: só as duas raízes visíveis (hash de opções).
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, .{ .r = 24, .g = 24, .b = 28, .a = 255 }));
    try eq(ok, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, raizes.len, &selected, &scroll, &tvs, &res));
    try stdt.testing.expect(res.selected == 0 and res.toggled_index == -1 and !res.changed);
    try stdt.testing.expect(!raizes[0].expanded and !filhos[0].expanded);
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 100, 20, &px));
    try eq(tvs.bg_selected.r, px.r); // nó 0 selecionado
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 12, 12, &px));
    try eq(tvs.text_selected.r, px.r); // expansor do nó 0 (selecionado)
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 100, 44, &px));
    try eq(tvs.bg.r, px.r); // nó 1 (sem expansor, não selecionado)
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 28, 32, &px));
    try eq(tvs.bg.r, px.r); // ainda não há nó em profundidade 1
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Clique no expansor do nó 0: alterna e devolve `expanded` na árvore.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, .{ .r = 24, .g = 24, .b = 28, .a = 255 }));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 12, .y = 12 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 12, .y = 12 }));
    try eq(ok, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, raizes.len, &selected, &scroll, &tvs, &res));
    try stdt.testing.expect(res.toggled_index == 0 and raizes[0].expanded and res.selected == 0);
    try eq(ok, zyntra_framebuffer_render(fb_handle, ctx_handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 28, 32, &px));
    try eq(tvs.text.r, px.r); // expansor do nó "ui" (profundidade 1)
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 100, 44, &px));
    try eq(tvs.bg.r, px.r); // linha 1 = "ui", sem seleção
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Clique no expansor do nó "ui": alterna o filho (estado aninhado).
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 28, .y = 32 }));
    try eq(ok, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, raizes.len, &selected, &scroll, &tvs, &res));
    try stdt.testing.expect(res.toggled_index == 1 and filhos[0].expanded and raizes[0].expanded);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Clique no nó 4 ("build.zig", sem expansor) seleciona.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 100, .y = 116 }));
    try eq(ok, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, raizes.len, &selected, &scroll, &tvs, &res));
    try stdt.testing.expect(res.changed and res.selected == 4 and selected == 4 and res.toggled_index == -1);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Inválidos: vetores nulos, rótulo/filhos sem ponteiro, estados nulos e
    // ciclo na árvore (corta pela profundidade máxima).
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, 0, &selected, &scroll, &tvs, null));
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, null, 1, &selected, &scroll, &tvs, null));
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, raizes.len, null, &scroll, &tvs, null));
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, raizes.len, &selected, null, &tvs, null));
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, &raizes, raizes.len, &selected, &scroll, null, null));
    var broken_label = [_]ct.ZyntraTreeItem{.{ .label = .{ .ptr = null, .len = 3 } }};
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, &broken_label, 1, &selected, &scroll, &tvs, null));
    var broken_kids = [_]ct.ZyntraTreeItem{.{ .label = .{ .ptr = "x", .len = 1 }, .children_len = 2 }};
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, &broken_kids, 1, &selected, &scroll, &tvs, null));
    var ciclo: [1]ct.ZyntraTreeItem = undefined;
    ciclo[0] = .{ .label = .{ .ptr = "loop", .len = 4 } };
    ciclo[0].children = &ciclo;
    ciclo[0].children_len = 1;
    try eq(bad, zyntra_widget_tree_view(ctx_handle, id, bounds, &ciclo, 1, &selected, &scroll, &tvs, null));

    // Árvore maior que o scratch da pilha (70 nós): caminho com alocação.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    var muitos: [70]ct.ZyntraTreeItem = undefined;
    for (&muitos) |*n| n.* = .{ .label = .{ .ptr = "no", .len = 2 } };
    var msel: usize = 0;
    var mscroll: f32 = 0;
    try eq(ok, zyntra_widget_tree_view(ctx_handle, id, bounds, &muitos, muitos.len, &msel, &mscroll, &tvs, &res));
    try stdt.testing.expect(msel == 0 and res.selected == 0);
    try eq(ok, zyntra_context_end_frame(ctx_handle));
}

test "C-ABI teclado: foco, teclas e texto" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const bad_event = ct.ZyntraResult.invalid_event;

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 240, .h = 200 }, &handle));
    defer zyntra_context_destroy(handle);

    const menu_id = zyntra_id_from_string("c:keys:menu", 11);
    const table_id = zyntra_id_from_string("c:keys:table", 12);
    const outro_id = zyntra_id_from_string("c:keys:outro", 12);
    var focused: bool = true;

    // Foco: vai e volta; leitura por id.
    try eq(ok, zyntra_context_focus(handle, menu_id));
    try eq(ok, zyntra_context_has_focus(handle, menu_id, &focused));
    try stdt.testing.expect(focused);
    try eq(ok, zyntra_context_has_focus(handle, outro_id, &focused));
    try stdt.testing.expect(!focused);
    try eq(bad, zyntra_context_has_focus(handle, menu_id, null));
    try eq(bad, zyntra_context_focus(null, menu_id));
    try eq(ok, zyntra_context_focus(handle, 0));
    try eq(ok, zyntra_context_has_focus(handle, menu_id, &focused));
    try stdt.testing.expect(!focused);

    // Teclas: valor fora de `ZyntraKey` e bits reservados são argumento
    // inválido; modificadores válidos entram na fila.
    try eq(bad, zyntra_context_push_key(handle, 999, true, 0));
    try eq(bad, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.enter), true, 0x10));
    try eq(bad, zyntra_context_push_key(null, @backingInt(ct.ZyntraKey.enter), true, 0));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.enter), true, 0x03));
    var ev_len: usize = 0;
    try eq(ok, zyntra_context_pending_events(handle, &ev_len));
    try stdt.testing.expect(ev_len == 1);
    // Texto: codepoint válido entra; fora da faixa ou substituto é evento
    // inválido (não entra na fila).
    try eq(ok, zyntra_context_push_text(handle, 'A'));
    try eq(bad_event, zyntra_context_push_text(handle, 0x110000));
    try eq(bad_event, zyntra_context_push_text(handle, 0xD800));
    try eq(ok, zyntra_context_pending_events(handle, &ev_len));
    try stdt.testing.expect(ev_len == 2);

    var fb_handle: ?*ZyntraFramebuffer = null;
    try eq(ok, zyntra_framebuffer_create(240, 200, &fb_handle));
    defer zyntra_framebuffer_destroy(fb_handle);
    var ms: ct.ZyntraMenuStyle = undefined;
    var ts: ct.ZyntraTableStyle = undefined;
    try eq(ok, zyntra_style_menu(0, &ms));
    try eq(ok, zyntra_style_table(0, &ts));

    const menu_bounds: ct.ZyntraRect = .{ .x = 8, .y = 8, .w = 160, .h = 104 };
    const table_bounds: ct.ZyntraRect = .{ .x = 8, .y = 120, .w = 220, .h = 72 };
    const menu_items = [_]ct.ZyntraMenuItem{
        .{ .label = .{ .ptr = "Abrir", .len = 5 } },
        .{ .label = .{ .ptr = "", .len = 0 }, .separator = true },
        .{ .label = .{ .ptr = "Salvar", .len = 6 } },
        .{ .label = .{ .ptr = "Sair", .len = 4 }, .enabled = false },
    };
    const columns = [_]ct.ZyntraTableColumn{
        .{ .title = .{ .ptr = "Nome", .len = 4 }, .width = 220 },
    };
    const row_cells = [_][1]ct.ZyntraStr{
        .{.{ .ptr = "um", .len = 2 }},
        .{.{ .ptr = "dois", .len = 4 }},
        .{.{ .ptr = "tres", .len = 4 }},
    };
    const rows = [_]ct.ZyntraTableRow{
        .{ .cells = &row_cells[0], .cells_len = 1 },
        .{ .cells = &row_cells[1], .cells_len = 1 },
        .{ .cells = &row_cells[2], .cells_len = 1 },
    };
    var mres: ct.ZyntraMenuResult = .{};
    var tres: ct.ZyntraTableResult = .{};
    var active: usize = 0;
    var selected: usize = 0;
    var scroll: f32 = 0;
    var px: ct.ZyntraColor = .{};
    const clear = ct.ZyntraColor{ .r = 24, .g = 24, .b = 28, .a = 255 };

    // Foco realça a linha ativa do menu (linha 0 sem mouse).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 236, .y = 196 }));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_focus(handle, menu_id));
    try eq(ok, zyntra_widget_menu(handle, menu_id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(active == 0 and mres.chosen == -1 and !mres.hovered);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 50, 20, &px));
    try eq(ms.item_hover.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));

    // `down` pula o separador (linha 1) e para na linha 2.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.down), true, 0));
    try eq(ok, zyntra_widget_menu(handle, menu_id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(active == 2);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 50, 70, &px));
    try eq(ms.item_hover.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 50, 20, &px));
    try eq(ms.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));

    // `up` volta e `enter` escolhe a linha ativa (one-shot).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.up), true, 0));
    try eq(ok, zyntra_widget_menu(handle, menu_id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(active == 0 and mres.chosen == -1);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.down), true, 0));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.enter), true, 0));
    try eq(ok, zyntra_widget_menu(handle, menu_id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(mres.chosen == 2 and active == 2 and !mres.dismissed);
    try eq(ok, zyntra_context_end_frame(handle));

    // `escape` dispensa e solta o foco.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.escape), true, 0));
    try eq(ok, zyntra_widget_menu(handle, menu_id, menu_bounds, &menu_items, menu_items.len, &active, 16, &ms, &mres));
    try stdt.testing.expect(mres.dismissed);
    try eq(ok, zyntra_context_has_focus(handle, menu_id, &focused));
    try stdt.testing.expect(!focused);
    try eq(ok, zyntra_context_end_frame(handle));

    // Tabela com foco: `down` move a seleção (linha 0 → 1).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 236, .y = 196 }));
    try eq(ok, zyntra_context_focus(handle, table_id));
    try eq(ok, zyntra_widget_table(handle, table_id, table_bounds, &columns, columns.len, &rows, rows.len, &selected, &scroll, &ts, &tres));
    try stdt.testing.expect(selected == 0 and !tres.changed);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 158, &px));
    try eq(ts.bg_selected.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.down), true, 0));
    try eq(ok, zyntra_widget_table(handle, table_id, table_bounds, &columns, columns.len, &rows, rows.len, &selected, &scroll, &ts, &tres));
    try stdt.testing.expect(selected == 1 and tres.changed and tres.selected == 1);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 182, &px));
    try eq(ts.bg_selected.r, px.r);
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 20, 158, &px));
    try eq(ts.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI campos de texto: digitação, caret e seleção" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;

    var tis: ct.ZyntraTextInputStyle = undefined;
    try eq(ok, zyntra_style_text_input(0, &tis));
    try eq(bad, zyntra_style_text_input(7, &tis));
    try eq(bad, zyntra_style_text_input(0, null));

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 240, .h = 200 }, &handle));
    defer zyntra_context_destroy(handle);
    var fb_handle: ?*ZyntraFramebuffer = null;
    try eq(ok, zyntra_framebuffer_create(240, 200, &fb_handle));
    defer zyntra_framebuffer_destroy(fb_handle);
    try eq(ok, zyntra_context_set_viewport(handle, .{ .x = 0, .y = 0, .w = 240, .h = 200 }));

    const ti_id = zyntra_id_from_string("c:ti", 4);
    const ta_id = zyntra_id_from_string("c:ta", 4);
    const ti_bounds: ct.ZyntraRect = .{ .x = 8, .y = 8, .w = 160, .h = 24 };
    const ta_bounds: ct.ZyntraRect = .{ .x = 8, .y = 44, .w = 200, .h = 96 };
    const clear = ct.ZyntraColor{ .r = 24, .g = 24, .b = 28, .a = 255 };
    var ti_buf: [8]u8 = undefined;
    var ti_len: usize = 0;
    var ti_cursor: usize = 0;
    var ti_anchor: usize = 0;
    var ta_buf: [32]u8 = undefined;
    var ta_len: usize = 0;
    var ta_cursor: usize = 0;
    var ta_anchor: usize = 0;
    var ta_scroll: f32 = 0;
    var res: ct.ZyntraTextInputResult = .{};
    var ares: ct.ZyntraTextAreaResult = .{};
    var px: ct.ZyntraColor = .{};

    // Frame frio: sem foco o texto digitado é ignorado e a caixa usa `bg`.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 236, .y = 196 }));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_push_text(handle, 'a'));
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, 10, &tis, &res));
    try stdt.testing.expect(!res.focused and !res.changed and ti_len == 0);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 150, 20, &px));
    try eq(tis.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));

    // Com foco, o texto entra no buffer do chamador (len/cursor e bytes).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_focus(handle, ti_id));
    try eq(ok, zyntra_context_push_text(handle, 'a'));
    try eq(ok, zyntra_context_push_text(handle, 'b'));
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, 10, &tis, &res));
    try stdt.testing.expect(res.focused and res.changed and res.len == 2 and ti_len == 2 and ti_cursor == 2);
    try stdt.testing.expectEqualStrings("ab", ti_buf[0..ti_len]);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 150, 20, &px));
    try eq(tis.bg_focus.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));

    // Seta para a esquerda move o caret e a digitação insere no meio.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.left), true, 0));
    try eq(ok, zyntra_context_push_text(handle, 'X'));
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, 10, &tis, &res));
    try stdt.testing.expect(res.changed and ti_len == 3 and ti_cursor == 2);
    try stdt.testing.expectEqualStrings("aXb", ti_buf[0..ti_len]);
    try eq(ok, zyntra_context_end_frame(handle));

    // Backspace apaga o codepoint antes do caret.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.backspace), true, 0));
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, 10, &tis, &res));
    try stdt.testing.expect(res.changed and ti_len == 2 and ti_cursor == 1);
    try stdt.testing.expectEqualStrings("ab", ti_buf[0..ti_len]);
    try eq(ok, zyntra_context_end_frame(handle));

    // Capacidade do chamador limita a digitação: o excedente vira
    // `overflowed` sem tocar o buffer.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_text(handle, 'c'));
    try eq(ok, zyntra_context_push_text(handle, 'd'));
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, 3, &ti_len, &ti_cursor, 10, &tis, &res));
    try stdt.testing.expect(res.overflowed and ti_len == 3);
    try stdt.testing.expectEqualStrings("acb", ti_buf[0..ti_len]); // inserido no caret (1)
    // Buffer sem capacidade: aceito com ponteiro nulo (len/cursor zerados).
    var vazio_len: usize = 0;
    var vazio_cursor: usize = 0;
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, null, 0, &vazio_len, &vazio_cursor, 10, &tis, null));
    try eq(ok, zyntra_context_end_frame(handle));

    // Enter submete mantendo o foco; Escape solta o foco (caixa volta a `bg`).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.enter), true, 0));
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, 3, &ti_len, &ti_cursor, 10, &tis, &res));
    try stdt.testing.expect(res.submitted and res.focused);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.escape), true, 0));
    try eq(ok, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, 3, &ti_len, &ti_cursor, 10, &tis, &res));
    try stdt.testing.expect(!res.focused);
    var focused: bool = true;
    try eq(ok, zyntra_context_has_focus(handle, ti_id, &focused));
    try stdt.testing.expect(!focused);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 150, 20, &px));
    try eq(tis.bg.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));

    // Variante com seleção: Shift estende a faixa e digitar a substitui.
    ti_len = 0;
    ti_cursor = 0;
    ti_anchor = 0;
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_focus(handle, ti_id));
    try eq(ok, zyntra_context_push_text(handle, 'A'));
    try eq(ok, zyntra_context_push_text(handle, 'B'));
    try eq(ok, zyntra_widget_text_input_selected(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, &ti_anchor, 10, &tis, &res));
    try stdt.testing.expect(!res.selected and ti_len == 2 and ti_cursor == 2 and ti_anchor == 2);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.left), true, 0));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.left), true, ct.key_modifiers_mask & 0x01));
    try eq(ok, zyntra_widget_text_input_selected(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, &ti_anchor, 10, &tis, &res));
    try stdt.testing.expect(res.selected and ti_cursor == 0 and ti_anchor == 1);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_text(handle, 'Z'));
    try eq(ok, zyntra_widget_text_input_selected(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, &ti_anchor, 10, &tis, &res));
    try stdt.testing.expect(res.changed and !res.selected and ti_len == 2 and ti_cursor == 1);
    try stdt.testing.expectEqualStrings("ZB", ti_buf[0..ti_len]);
    try eq(ok, zyntra_context_end_frame(handle));

    // Área de texto: várias linhas (newline digitado) e fundo de foco.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_draw_clear(handle, clear));
    try eq(ok, zyntra_context_focus(handle, ta_id));
    try eq(ok, zyntra_context_push_text(handle, 'a'));
    try eq(ok, zyntra_context_push_text(handle, 'b'));
    try eq(ok, zyntra_context_push_text(handle, '\n'));
    try eq(ok, zyntra_context_push_text(handle, 'c'));
    try eq(ok, zyntra_context_push_text(handle, 'd'));
    try eq(ok, zyntra_widget_text_area(handle, ta_id, ta_bounds, &ta_buf, ta_buf.len, &ta_len, &ta_cursor, &ta_anchor, &ta_scroll, 10, &tis, &ares));
    try stdt.testing.expect(ares.focused and ares.changed and ares.len == 5 and ta_len == 5 and ta_cursor == 5);
    try stdt.testing.expectEqualStrings("ab\ncd", ta_buf[0..ta_len]);
    try eq(ok, zyntra_framebuffer_render(fb_handle, handle, null));
    try eq(ok, zyntra_framebuffer_pixel(fb_handle, 192, 100, &px));
    try eq(tis.bg_focus.r, px.r);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos: estados nulos, buffer nulo com capacidade, cursor/anchor
    // fora da faixa declarada e `size` não-positivo.
    try eq(bad, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, 0, &tis, null));
    try eq(bad, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, null, 10, &tis, null));
    try eq(bad, zyntra_widget_text_input(handle, ti_id, ti_bounds, null, 4, &ti_len, &ti_cursor, 10, &tis, null));
    try eq(bad, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, 10, null, null));
    try eq(bad, zyntra_widget_text_input(null, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, 10, &tis, null));
    var cursor_ruim: usize = ti_len + 1;
    try eq(bad, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &cursor_ruim, 10, &tis, null));
    var len_ruim: usize = ti_buf.len + 1;
    try eq(bad, zyntra_widget_text_input(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &len_ruim, &ti_cursor, 10, &tis, null));
    var anchor_ruim: usize = ti_len + 1;
    try eq(bad, zyntra_widget_text_input_selected(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, &anchor_ruim, 10, &tis, null));
    try eq(bad, zyntra_widget_text_input_selected(handle, ti_id, ti_bounds, &ti_buf, ti_buf.len, &ti_len, &ti_cursor, null, 10, &tis, null));
    try eq(bad, zyntra_widget_text_area(handle, ta_id, ta_bounds, &ta_buf, ta_buf.len, &ta_len, &ta_cursor, &ta_anchor, null, 10, &tis, null));
    try eq(bad, zyntra_widget_text_area(handle, ta_id, ta_bounds, &ta_buf, ta_buf.len, &ta_len, &ta_cursor, &ta_anchor, &ta_scroll, 10, null, null));
    try eq(bad, zyntra_widget_text_area(handle, ta_id, ta_bounds, &ta_buf, ta_buf.len, &ta_len, null, &ta_anchor, &ta_scroll, 10, &tis, null));
}

// ---------------------------------------------------------------------------
// M114 — Draw moderno: gradiente radial, contorno e círculo tracejado
// ---------------------------------------------------------------------------

test "C-ABI draw: gradiente radial aceita e rejeita entradas inválidas" {
    const stdt = @import("std");
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_context_create(.{ .x = 0, .y = 0, .w = 200, .h = 100 }, &handle),
    );
    defer zyntra_context_destroy(handle);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_begin_frame(handle));

    const white: ct.ZyntraColor = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const dark: ct.ZyntraColor = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const rect: ct.ZyntraRect = .{ .x = 10, .y = 10, .w = 40, .h = 40 };

    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_gradient_radial(handle, rect, 20, white, dark),
    );
    // Handle nulo é invalid_argument.
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_draw_gradient_radial(null, rect, 20, white, dark),
    );
    // Raio negativo é invalid_command (rejeitado pelo isValid).
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_gradient_radial(handle, rect, -1, white, dark),
    );

    var n: usize = 0;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_count(handle, &n));
    try stdt.testing.expectEqual(@as(usize, 1), n);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_end_frame(handle));
}

test "C-ABI draw: contorno e círculo tracejado" {
    const stdt = @import("std");
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_context_create(.{ .x = 0, .y = 0, .w = 200, .h = 100 }, &handle),
    );
    defer zyntra_context_destroy(handle);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_begin_frame(handle));

    const white: ct.ZyntraColor = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const center: ct.ZyntraVec2 = .{ .x = 30, .y = 20 };

    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_circle_outline(handle, center, 10, white, 2),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_circle_dashed(handle, center, 12, white, 1.5, 4, 2),
    );

    // Inválidos rejeitados sem enfileirar:
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_circle_outline(handle, center, 10, white, 0),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_circle_dashed(handle, center, 12, white, 1, 0, 2),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_circle_dashed(handle, center, 12, white, 1, 4, -1),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_draw_circle_outline(null, center, 10, white, 2),
    );

    var n: usize = 0;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_count(handle, &n));
    try stdt.testing.expectEqual(@as(usize, 2), n);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_end_frame(handle));
}

test "C-ABI draw: gradiente cônico e linha tracejada" {
    const stdt = @import("std");
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_context_create(.{ .x = 0, .y = 0, .w = 200, .h = 100 }, &handle),
    );
    defer zyntra_context_destroy(handle);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_begin_frame(handle));

    const white: ct.ZyntraColor = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const dark: ct.ZyntraColor = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const rect: ct.ZyntraRect = .{ .x = 0, .y = 0, .w = 40, .h = 40 };
    const center: ct.ZyntraVec2 = .{ .x = 20, .y = 20 };

    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_gradient_conic(handle, rect, center, 0, 6.2831855, white, dark),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.ok,
        zyntra_draw_line_dashed(handle, .{ .x = 0, .y = 0 }, .{ .x = 40, .y = 40 }, white, 2, 4, 2),
    );

    // Inválidos rejeitados:
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_gradient_conic(handle, rect, center, std.math.nan(f32), 1, white, dark),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_line_dashed(handle, .{ .x = 0, .y = 0 }, .{ .x = 40, .y = 40 }, white, 2, 0, 2),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_command,
        zyntra_draw_line_dashed(handle, .{ .x = 0, .y = 0 }, .{ .x = 40, .y = 40 }, white, 2, 4, -1),
    );
    try stdt.testing.expectEqual(
        ct.ZyntraResult.invalid_argument,
        zyntra_draw_gradient_conic(null, rect, center, 0, 1, white, dark),
    );

    var n: usize = 0;
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_draw_count(handle, &n));
    try stdt.testing.expectEqual(@as(usize, 2), n);
    try stdt.testing.expectEqual(ct.ZyntraResult.ok, zyntra_context_end_frame(handle));
}

test "C-ABI docking: modelo, consultas e widget dock_view" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;

    // Ciclo de vida: create/destroy, null-safe e out nulo.
    var dock: ?*ZyntraDock = null;
    try eq(ok, zyntra_dock_create(7, &dock));
    defer zyntra_dock_destroy(dock);
    try stdt.testing.expect(dock != null);
    zyntra_dock_destroy(null); // null-safe
    try eq(bad, zyntra_dock_create(7, null));
    try eq(bad, zyntra_dock_init(null, 0));
    try eq(bad, zyntra_dock_set_ratio(null, 0, 0.5));

    // Estilo do tema embutido; kind fora da faixa é rejeitado.
    var ds: ct.ZyntraDockStyle = undefined;
    try eq(ok, zyntra_style_dock(0, &ds));
    try stdt.testing.expect(ds.isValid());
    try eq(bad, zyntra_style_dock(9, &ds));
    try eq(bad, zyntra_style_dock(0, null));

    const bounds: ct.ZyntraRect = .{ .x = 0, .y = 0, .w = 400, .h = 300 };
    var panes: [16]ct.ZyntraDockPaneInfo = undefined;
    var splits: [16]ct.ZyntraDockSplitInfo = undefined;
    var group: ct.ZyntraDockGroup = undefined;
    var count: usize = 0;
    var leaf: u8 = 0;
    var leaf2: u8 = 0;

    // Layout único (create com painel 7): 1 folha, 0 splits.
    try eq(ok, zyntra_dock_panes(dock, bounds, 6, &panes, panes.len, &count));
    try eq(@as(usize, 1), count);
    try eq(@as(u8, 0), panes[0].node);
    try eq(@as(u16, 7), panes[0].group.panes[0]);
    try eq(@as(u8, 1), panes[0].group.count);
    try eq(@as(u8, 0), panes[0].group.active);
    try eq(ok, zyntra_dock_splits(dock, bounds, 6, &splits, splits.len, &count));
    try eq(@as(usize, 0), count);

    // Split horizontal 0.5 ⇒ duas folhas com a divisória no meio.
    try eq(ok, zyntra_dock_split(dock, 0, 0, 0.5, 9, &leaf));
    try eq(ok, zyntra_dock_panes(dock, bounds, 6, &panes, panes.len, &count));
    try eq(@as(usize, 2), count);
    try eq(@as(u16, 7), panes[0].group.panes[0]);
    try eq(@as(u16, 9), panes[1].group.panes[0]);
    try eq((ct.ZyntraRect){ .x = 0, .y = 0, .w = 400, .h = 147 }, panes[0].rect);
    try eq((ct.ZyntraRect){ .x = 0, .y = 153, .w = 400, .h = 147 }, panes[1].rect);
    try eq(ok, zyntra_dock_splits(dock, bounds, 6, &splits, splits.len, &count));
    try eq(@as(usize, 1), count);
    try eq(@as(u8, 0), splits[0].node);
    try eq(@as(u8, 0), splits[0].orientation); // horizontal
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), splits[0].ratio, 0.0001);

    // Segment vertical na segunda folha ⇒ 3 grupos, 2 splits (base das
    // checagens de buffer pequeno abaixo).
    try eq(ok, zyntra_dock_split(dock, leaf, 1, 0.5, 11, &leaf2));
    try eq(ok, zyntra_dock_panes(dock, bounds, 6, &panes, panes.len, &count));
    try eq(@as(usize, 3), count);
    try eq(ok, zyntra_dock_splits(dock, bounds, 6, &splits, splits.len, &count));
    try eq(@as(usize, 2), count);
    try eq(@as(u8, 1), splits[1].orientation); // vertical

    // Buffer pequeno e saída nula são recusados sem escrever.
    var one_pane: [1]ct.ZyntraDockPaneInfo = undefined;
    var one_split: [1]ct.ZyntraDockSplitInfo = undefined;
    try eq(bad, zyntra_dock_panes(dock, bounds, 6, &one_pane, 1, &count));
    try eq(bad, zyntra_dock_splits(dock, bounds, 6, &one_split, 1, &count));
    try eq(bad, zyntra_dock_panes(dock, bounds, 6, null, 0, null));
    try eq(bad, zyntra_dock_splits(dock, bounds, 6, &splits, splits.len, null));
    // Só a contagem: `out` nulo com `out_len == 0` é válido.
    try eq(ok, zyntra_dock_panes(dock, bounds, 6, null, 0, &count));
    try eq(@as(usize, 3), count);
    // Argumentos inválidos nos mutadores/consultas.
    try eq(bad, zyntra_dock_split(dock, 99, 0, 0.5, 1, &leaf));
    try eq(bad, zyntra_dock_split(dock, 0, 9, 0.5, 1, &leaf));
    try eq(bad, zyntra_dock_split(dock, 0, 0, 0.5, 1, null));
    try eq(bad, zyntra_dock_group(dock, 99, &group));
    try eq(bad, zyntra_dock_group(dock, 0, null));
    try eq(bad, zyntra_dock_add_tab(null, 0, 1, null));

    // Abas: o grupo do painel 9 (folha real, nó 3) recebe uma aba, ativa e
    // remove. `leaf` virou nó interno no split vertical, então reuso a folha
    // consultada em pré-ordem (panes[1] == painel 9).
    const leaf9 = panes[1].node;
    try eq(ok, zyntra_dock_group(dock, leaf9, &group));
    try eq(@as(u8, 1), group.count);
    try eq(@as(u16, 9), group.panes[0]);
    var added = false;
    try eq(ok, zyntra_dock_add_tab(dock, leaf9, 13, &added));
    try eq(true, added);
    var set = false;
    try eq(ok, zyntra_dock_set_active_tab(dock, leaf9, 1, &set));
    try eq(true, set);
    try eq(ok, zyntra_dock_group(dock, leaf9, &group));
    try eq(@as(u8, 2), group.count);
    try eq(@as(u8, 1), group.active);
    try eq(@as(u16, 9), group.panes[0]);
    try eq(@as(u16, 13), group.panes[1]);
    var removed = false;
    try eq(ok, zyntra_dock_remove_pane(dock, 13, &removed));
    try eq(true, removed);
    try eq(ok, zyntra_dock_group(dock, leaf9, &group));
    try eq(@as(u8, 1), group.count);

    // Reset + widget: fundo e divisória desenhadas, geometria no lugar.
    try eq(ok, zyntra_dock_init(dock, 7));
    try eq(ok, zyntra_dock_split(dock, 0, 0, 0.5, 9, &leaf));
    var ctx_handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 400, .h = 300 }, &ctx_handle));
    defer zyntra_context_destroy(ctx_handle);
    const id = zyntra_id_from_string("c:dock", 6);
    var res: ct.ZyntraDockViewResult = .{};

    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_draw_clear(ctx_handle, .{ .r = 0, .g = 0, .b = 0, .a = 255 }));
    var before: usize = 0;
    try eq(ok, zyntra_draw_count(ctx_handle, &before));
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    var after: usize = 0;
    try eq(ok, zyntra_draw_count(ctx_handle, &after));
    try eq(@as(usize, 2), after - before); // fundo + divisória
    try eq(@as(usize, 2), res.pane_count);
    try eq(@as(usize, 1), res.split_count);
    try eq(false, res.changed);
    try eq(@as(i64, -1), res.hovered);
    try eq(@as(i64, -1), res.dragging);
    try eq(false, res.has_drop);
    try eq(false, res.has_dropped);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Hover na faixa (y ∈ [147,153)) ⇒ hovered == 0, sem mudança.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 200, .y = 150 }));
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    try eq(@as(i64, 0), res.hovered);
    try eq(false, res.changed);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Press captura a divisória; o arraste muda o ratio no mesmo frame.
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 200, .y = 150 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, true, .{ .x = 200, .y = 150 }));
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    try eq(@as(i64, 0), res.dragging);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 200, .y = 210 }));
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    try eq(@as(i64, 0), res.dragging);
    try eq(true, res.changed);
    try eq(ok, zyntra_context_end_frame(ctx_handle));
    try eq(ok, zyntra_dock_splits(dock, bounds, 6, &splits, splits.len, &count));
    try eq(@as(usize, 1), count);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.7), splits[0].ratio, 0.0001);

    // Soltar encerra o arraste (sem mudança de geometria).
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 200, .y = 210 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, false, .{ .x = 200, .y = 210 }));
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    try eq(@as(i64, -1), res.dragging);
    try eq(false, res.changed);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    // Drop de painel: 9 arrastado sobre 7 no centro ⇒ realce; no release a
    // aba é acoplada e o grupo alvo passa a ter 2 painéis.
    try eq(ok, zyntra_dock_init(dock, 7));
    try eq(ok, zyntra_dock_split(dock, 0, 0, 0.5, 9, &leaf));
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 200, .y = 50 }));
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, 9, 0.25, &ds, &res));
    try eq(true, res.has_drop);
    try eq(false, res.has_dropped);
    try eq(@as(u16, 9), res.drop.pane);
    try eq(@as(u16, 7), res.drop.target);
    try eq(@as(ct.ZyntraDockZone, .center), res.drop.zone);
    try eq(ok, zyntra_context_end_frame(ctx_handle));

    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(ok, zyntra_context_push_mouse_move(ctx_handle, .{ .x = 200, .y = 50 }));
    try eq(ok, zyntra_context_push_mouse_button(ctx_handle, 0, false, .{ .x = 200, .y = 50 }));
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, 9, 0.25, &ds, &res));
    try eq(true, res.has_dropped);
    try eq(true, res.changed);
    try eq(@as(usize, 1), res.pane_count);
    try eq(ok, zyntra_context_end_frame(ctx_handle));
    try eq(ok, zyntra_dock_group(dock, panes[0].node, &group));
    try eq(@as(u8, 2), group.count);
    try eq(@as(u16, 7), group.panes[0]);
    try eq(@as(u16, 9), group.panes[1]);
    try eq(@as(u8, 1), group.active);

    // Argumentos inválidos: nunca crasham e devolvem invalid_argument.
    try eq(ok, zyntra_dock_init(dock, 7));
    try eq(ok, zyntra_dock_split(dock, 0, 0, 0.5, 9, &leaf));
    try eq(ok, zyntra_context_begin_frame(ctx_handle));
    try eq(bad, zyntra_widget_dock_view(null, id, bounds, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, null, &panes, panes.len, -1, 0.25, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.25, null, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, 0, bounds, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, 0, -1, 0.25, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, null, 5, -1, 0.25, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -2, 0.25, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, 70000, 0.25, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.9, &ds, &res));
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, .{ .x = 0, .y = 0, .w = -1, .h = 10 }, dock, &panes, panes.len, -1, 0.25, &ds, &res));
    var tiny: [1]ct.ZyntraDockPaneInfo = undefined;
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &tiny, 1, -1, 0.25, &ds, &res));
    var bad_ds = ds;
    bad_ds.divider = -1;
    try eq(bad, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, &panes, panes.len, -1, 0.25, &bad_ds, &res));
    // Modo "só desenha": `panes` nulo com `out_len == 0` é válido.
    try eq(ok, zyntra_widget_dock_view(ctx_handle, id, bounds, dock, null, 0, -1, 0.25, &ds, &res));
    try eq(@as(usize, 2), res.pane_count);
    try eq(ok, zyntra_context_end_frame(ctx_handle));
}

test "C-ABI widgets M115: combo, splitter, spinner, groupbox e tooltip" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const nan = std.math.nan(f32);

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 800, .h = 600 }, &handle));
    defer zyntra_context_destroy(handle);

    // Estilos do tema embutido; kind fora da faixa e out nulo são recusados.
    var spst: ct.ZyntraSplitterStyle = undefined;
    var sps: ct.ZyntraSpinnerStyle = undefined;
    var gbs: ct.ZyntraGroupBoxStyle = undefined;
    var tts: ct.ZyntraTooltipStyle = undefined;
    try eq(ok, zyntra_style_splitter(0, &spst));
    try eq(ok, zyntra_style_spinner(1, &sps));
    try eq(ok, zyntra_style_group_box(0, &gbs));
    try eq(ok, zyntra_style_tooltip(1, &tts));
    try stdt.testing.expect(spst.isValid() and sps.isValid());
    try stdt.testing.expect(gbs.isValid() and tts.isValid());
    try eq(bad, zyntra_style_splitter(9, &spst));
    try eq(bad, zyntra_style_spinner(0, null));
    try eq(bad, zyntra_style_group_box(9, &gbs));
    try eq(bad, zyntra_style_tooltip(0, null));

    var bst: ct.ZyntraButtonStyle = undefined;
    var mst: ct.ZyntraMenuStyle = undefined;
    try eq(ok, zyntra_style_button(0, &bst));
    try eq(ok, zyntra_style_menu(0, &mst));

    // Combo: press fecha, release abre, press no item escolhe.
    const labels = [_][]const u8{ "A", "B", "C" };
    var opts: [3]ct.ZyntraStr = undefined;
    for (labels, 0..) |lbl, i| opts[i] = .{ .ptr = lbl.ptr, .len = lbl.len };
    const combo_bounds: ct.ZyntraRect = .{ .x = 10, .y = 10, .w = 120, .h = 28 };
    const combo_id: ct.ZyntraId = 0xC0;
    var selected: usize = 0;
    var open = false;
    var cbres: ct.ZyntraComboResult = undefined;

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 20, .y = 20 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 20, .y = 20 }));
    try eq(ok, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, &selected, &open, 10, &bst, &mst, &cbres));
    try stdt.testing.expect(!cbres.open and !open and !cbres.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 20, .y = 20 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 20, .y = 20 }));
    try eq(ok, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, &selected, &open, 10, &bst, &mst, &cbres));
    try stdt.testing.expect(cbres.open and open and !cbres.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Item 2: y = 38 + 2 * 18.625 + 5 ≈ 80.25.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 20, .y = 80 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 20, .y = 80 }));
    try eq(ok, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, &selected, &open, 10, &bst, &mst, &cbres));
    try stdt.testing.expect(cbres.changed and !cbres.open and !open);
    try eq(@as(usize, 2), selected);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos: handles/ponteiros nulos, lista vazia/grande demais, fonte.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(bad, zyntra_widget_combo(null, combo_id, combo_bounds, &opts, opts.len, &selected, &open, 10, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, 0, combo_bounds, &opts, opts.len, &selected, &open, 10, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, null, 0, &selected, &open, 10, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, 0, &selected, &open, 10, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, 257, &selected, &open, 10, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, null, &open, 10, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, &selected, null, 10, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, &selected, &open, 0, &bst, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, &selected, &open, 10, null, &mst, &cbres));
    try eq(bad, zyntra_widget_combo(handle, combo_id, combo_bounds, &opts, opts.len, &selected, &open, 10, &bst, null, &cbres));
    try eq(ok, zyntra_context_end_frame(handle));

    // Splitter: press captura, drag muda a posição, release encerra.
    const sp_bounds: ct.ZyntraRect = .{ .x = 0, .y = 0, .w = 200, .h = 200 };
    const sp_id: ct.ZyntraId = 0x5B;
    var pos: f32 = 100;
    var spres: ct.ZyntraSplitterResult = undefined;

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 100, .y = 100 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 100, .y = 100 }));
    try eq(ok, zyntra_widget_splitter(handle, sp_id, sp_bounds, 0, &pos, &spst, &spres));
    try stdt.testing.expect(spres.dragging and spres.hovered and !spres.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 100, .y = 140 }));
    try eq(ok, zyntra_widget_splitter(handle, sp_id, sp_bounds, 0, &pos, &spst, &spres));
    try stdt.testing.expect(spres.dragging and spres.changed);
    try eq(@as(f32, 140), pos);
    try eq(@as(f32, 140), spres.pos);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 100, .y = 140 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 100, .y = 140 }));
    try eq(ok, zyntra_widget_splitter(handle, sp_id, sp_bounds, 0, &pos, &spst, &spres));
    try stdt.testing.expect(!spres.dragging and !spres.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos: orientação fora da faixa, pos nulo, estilo nulo, id nulo.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(bad, zyntra_widget_splitter(null, sp_id, sp_bounds, 0, &pos, &spst, &spres));
    try eq(bad, zyntra_widget_splitter(handle, 0, sp_bounds, 0, &pos, &spst, &spres));
    try eq(bad, zyntra_widget_splitter(handle, sp_id, sp_bounds, 9, &pos, &spst, &spres));
    try eq(bad, zyntra_widget_splitter(handle, sp_id, sp_bounds, 0, null, &spst, &spres));
    try eq(bad, zyntra_widget_splitter(handle, sp_id, sp_bounds, 0, &pos, null, &spres));
    try eq(bad, zyntra_widget_splitter(handle, sp_id, .{ .x = 0, .y = 0, .w = 0, .h = 10 }, 0, &pos, &spst, &spres));
    var bad_sp = spst;
    bad_sp.handle_w = -1;
    try eq(bad, zyntra_widget_splitter(handle, sp_id, sp_bounds, 0, &pos, &bad_sp, &spres));
    try eq(ok, zyntra_context_end_frame(handle));

    // Spinner: display puro; valida centro/tempo e estilo.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_spinner(handle, .{ .x = 400, .y = 50 }, 0, &sps));
    try eq(bad, zyntra_widget_spinner(null, .{ .x = 0, .y = 0 }, 0, &sps));
    try eq(bad, zyntra_widget_spinner(handle, .{ .x = nan, .y = 0 }, 0, &sps));
    try eq(bad, zyntra_widget_spinner(handle, .{ .x = 0, .y = 0 }, nan, &sps));
    try eq(bad, zyntra_widget_spinner(handle, .{ .x = 0, .y = 0 }, 0, null));
    var bad_sps = sps;
    bad_sps.dots = 1;
    try eq(bad, zyntra_widget_spinner(handle, .{ .x = 0, .y = 0 }, 0, &bad_sps));
    try eq(ok, zyntra_context_end_frame(handle));

    // Groupbox: devolve a área útil (pad 8 + reserva lineHeight/2 no topo).
    const gb_bounds: ct.ZyntraRect = .{ .x = 10, .y = 10, .w = 200, .h = 100 };
    var content: ct.ZyntraRect = undefined;
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_group_box(handle, gb_bounds, "G", 1, 10, &gbs, &content));
    try eq(@as(f32, 18), content.x);
    try stdt.testing.expectApproxEqAbs(@as(f32, 23.3125), content.y, 0.001);
    try eq(@as(f32, 184), content.w);
    try stdt.testing.expectApproxEqAbs(@as(f32, 78.6875), content.h, 0.001);
    try eq(bad, zyntra_widget_group_box(null, gb_bounds, "G", 1, 10, &gbs, &content));
    try eq(bad, zyntra_widget_group_box(handle, gb_bounds, null, 1, 10, &gbs, &content));
    try eq(bad, zyntra_widget_group_box(handle, gb_bounds, "G", 1, nan, &gbs, &content));
    try eq(bad, zyntra_widget_group_box(handle, gb_bounds, "G", 1, 10, null, &content));
    try eq(bad, zyntra_widget_group_box(handle, .{ .x = 0, .y = 0, .w = 0, .h = 10 }, "G", 1, 10, &gbs, &content));
    var bad_gbs = gbs;
    bad_gbs.padding = -1;
    try eq(bad, zyntra_widget_group_box(handle, gb_bounds, "G", 1, 10, &bad_gbs, &content));
    // Título malformado: recusado sem deixar comandos parciais.
    try eq(ct.ZyntraResult.invalid_argument, zyntra_widget_group_box(handle, gb_bounds, "\xff", 1, 10, &gbs, &content));
    // `out_content` nulo é válido (só desenha).
    try eq(ok, zyntra_widget_group_box(handle, gb_bounds, "G", 1, 10, &gbs, null));
    try eq(ok, zyntra_context_end_frame(handle));

    // Tooltip: conta frames de hover e só aparece ao atingir o atraso.
    const tip_anchor: ct.ZyntraRect = .{ .x = 0, .y = 0, .w = 100, .h = 50 };
    const tip_id: ct.ZyntraId = 0x71;
    var tstate = ct.ZyntraTooltipState{};
    var mtres: ct.ZyntraTooltipResult = undefined;

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "Tip", 3, 10, &tts, 3, &tstate, &mtres));
    try stdt.testing.expect(mtres.hovered and !mtres.visible);
    try eq(@as(u32, 1), tstate.hover_frames);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 11, .y = 11 }));
    try eq(ok, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "Tip", 3, 10, &tts, 3, &tstate, &mtres));
    try stdt.testing.expect(mtres.hovered and !mtres.visible);
    try eq(@as(u32, 2), tstate.hover_frames);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 12, .y = 12 }));
    try eq(ok, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "Tip", 3, 10, &tts, 3, &tstate, &mtres));
    try stdt.testing.expect(mtres.hovered and mtres.visible);
    try eq(@as(u32, 3), tstate.hover_frames);
    var n_draw: usize = 0;
    try eq(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expect(n_draw >= 3); // caixa + borda + texto
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 500, .y = 500 }));
    try eq(ok, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "Tip", 3, 10, &tts, 3, &tstate, &mtres));
    try stdt.testing.expect(!mtres.hovered and !mtres.visible);
    try eq(@as(u32, 0), tstate.hover_frames);
    // Inválidos: id/handle/estado/estilo/âncora/fonte/texto.
    try eq(bad, zyntra_widget_tooltip(null, tip_id, tip_anchor, "T", 1, 10, &tts, 0, &tstate, &mtres));
    try eq(bad, zyntra_widget_tooltip(handle, 0, tip_anchor, "T", 1, 10, &tts, 0, &tstate, &mtres));
    try eq(bad, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "T", 1, 10, &tts, 0, null, &mtres));
    try eq(bad, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "T", 1, 10, null, 0, &tstate, &mtres));
    try eq(bad, zyntra_widget_tooltip(handle, tip_id, .{ .x = 0, .y = 0, .w = 0, .h = 50 }, "T", 1, 10, &tts, 0, &tstate, &mtres));
    try eq(bad, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "T", 1, 0, &tts, 0, &tstate, &mtres));
    try eq(bad, zyntra_widget_tooltip(handle, tip_id, tip_anchor, null, 1, 10, &tts, 0, &tstate, &mtres));
    var bad_tts = tts;
    bad_tts.padding = -1;
    try eq(bad, zyntra_widget_tooltip(handle, tip_id, tip_anchor, "T", 1, 10, &bad_tts, 0, &tstate, &mtres));
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI containers M116: scroll, popup e modal" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const nan = std.math.nan(f32);

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 300, .h = 200 }, &handle));
    defer zyntra_context_destroy(handle);

    // Estilos do tema embutido; kind fora da faixa e out nulo são recusados.
    var scs: ct.ZyntraScrollStyle = undefined;
    var pps: ct.ZyntraPopupStyle = undefined;
    var mds: ct.ZyntraModalStyle = undefined;
    try eq(ok, zyntra_style_scroll(0, &scs));
    try eq(ok, zyntra_style_popup(1, &pps));
    try eq(ok, zyntra_style_modal(0, &mds));
    try stdt.testing.expect(scs.isValid() and pps.isValid() and mds.isValid());
    try eq(bad, zyntra_style_scroll(9, &scs));
    try eq(bad, zyntra_style_popup(0, null));
    try eq(bad, zyntra_style_modal(9, &mds));

    // popupPlace: abre abaixo, vira para cima e prende na horizontal.
    var placed: ct.ZyntraRect = undefined;
    try eq(ok, zyntra_popup_place(
        .{ .x = 100, .y = 100, .w = 40, .h = 20 },
        .{ .w = 100, .h = 80 },
        .{ .x = 0, .y = 0, .w = 200, .h = 150 },
        &placed,
    ));
    try eq(@as(f32, 100), placed.x);
    try eq(@as(f32, 20), placed.y);
    try eq(@as(f32, 100), placed.w);
    try eq(@as(f32, 80), placed.h);
    try eq(bad, zyntra_popup_place(.{}, .{}, .{}, null));

    // Popup: hover dentro, dispensa com press fora e com Escape.
    const pop_bounds: ct.ZyntraRect = .{ .x = 100, .y = 100, .w = 160, .h = 80 };
    const pop_id: ct.ZyntraId = 0xA0;
    var pres: ct.ZyntraPopupResult = undefined;

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 110, .y = 110 }));
    try eq(ok, zyntra_widget_popup_begin(handle, pop_id, pop_bounds, &pps, &pres));
    try stdt.testing.expect(pres.hovered and !pres.dismissed);
    try eq(ok, zyntra_widget_popup_end(handle));
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_widget_popup_begin(handle, pop_id, pop_bounds, &pps, &pres));
    try stdt.testing.expect(pres.dismissed and !pres.hovered);
    try eq(ok, zyntra_widget_popup_end(handle));
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.escape), true, 0));
    try eq(ok, zyntra_widget_popup_begin(handle, pop_id, pop_bounds, &pps, &pres));
    try stdt.testing.expect(pres.dismissed);
    try eq(ok, zyntra_widget_popup_end(handle));
    // Inválidos: handle/id/estilo/retângulo.
    try eq(bad, zyntra_widget_popup_begin(null, pop_id, pop_bounds, &pps, &pres));
    try eq(bad, zyntra_widget_popup_begin(handle, 0, pop_bounds, &pps, &pres));
    try eq(bad, zyntra_widget_popup_begin(handle, pop_id, pop_bounds, null, &pres));
    try eq(bad, zyntra_widget_popup_begin(handle, pop_id, .{ .x = 0, .y = 0, .w = 0, .h = 10 }, &pps, &pres));
    var bad_pps = pps;
    bad_pps.border_width = -1;
    try eq(bad, zyntra_widget_popup_begin(handle, pop_id, pop_bounds, &bad_pps, &pres));
    try eq(bad, zyntra_widget_popup_end(null));
    try eq(ok, zyntra_context_end_frame(handle));

    // Modal básico: hover dentro e dispensa fora.
    const modal_bounds: ct.ZyntraRect = .{ .x = 50, .y = 50, .w = 120, .h = 90 };
    const modal_id: ct.ZyntraId = 0xB0;
    var mres: ct.ZyntraModalResult = undefined;

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 60, .y = 60 }));
    try eq(ok, zyntra_widget_modal_begin(handle, modal_id, modal_bounds, &mds, &mres));
    try stdt.testing.expect(mres.hovered and !mres.dismissed and !mres.dragging);
    try eq(ok, zyntra_widget_modal_end(handle));
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_widget_modal_begin(handle, modal_id, modal_bounds, &mds, &mres));
    try stdt.testing.expect(mres.dismissed and !mres.hovered);
    try eq(ok, zyntra_widget_modal_end(handle));
    // Inválidos: handle/id/estilo/retângulo.
    try eq(bad, zyntra_widget_modal_begin(null, modal_id, modal_bounds, &mds, &mres));
    try eq(bad, zyntra_widget_modal_begin(handle, 0, modal_bounds, &mds, &mres));
    try eq(bad, zyntra_widget_modal_begin(handle, modal_id, modal_bounds, null, &mres));
    try eq(bad, zyntra_widget_modal_begin(handle, modal_id, .{ .x = 0, .y = 0, .w = 0, .h = 10 }, &mds, &mres));
    try eq(bad, zyntra_widget_modal_end(null));
    try eq(ok, zyntra_context_end_frame(handle));

    // Modal com título arrastável: press na barra captura; mover desloca
    // `bounds`, clampado ao viewport.
    var tbounds = ct.ZyntraRect{ .x = 50, .y = 50, .w = 120, .h = 90 };
    var tdrag = ct.ZyntraModalDragState{};

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 60, .y = 55 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 60, .y = 55 }));
    try eq(ok, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, 10, 20, &tdrag, &mds, &mres));
    try stdt.testing.expect(mres.dragging and !mres.dismissed);
    try eq(@as(f32, 50), tbounds.x);
    try eq(@as(f32, 50), tbounds.y);
    try eq(ok, zyntra_widget_modal_end(handle));
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 70, .y = 65 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 70, .y = 65 }));
    try eq(ok, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, 10, 20, &tdrag, &mds, &mres));
    try stdt.testing.expect(mres.dragging);
    try eq(@as(f32, 60), tbounds.x);
    try eq(@as(f32, 60), tbounds.y);
    try eq(ok, zyntra_widget_modal_end(handle));
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 70, .y = 65 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 70, .y = 65 }));
    try eq(ok, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, 10, 20, &tdrag, &mds, &mres));
    try stdt.testing.expect(!mres.dragging);
    try eq(ok, zyntra_widget_modal_end(handle));
    // Inválidos: bounds/drag/título/fonte/title_h/estilo.
    try eq(bad, zyntra_widget_modal_titled(null, modal_id, &tbounds, "T", 1, 10, 20, &tdrag, &mds, &mres));
    try eq(bad, zyntra_widget_modal_titled(handle, 0, &tbounds, "T", 1, 10, 20, &tdrag, &mds, &mres));
    try eq(bad, zyntra_widget_modal_titled(handle, modal_id, null, "T", 1, 10, 20, &tdrag, &mds, &mres));
    try eq(bad, zyntra_widget_modal_titled(handle, modal_id, &tbounds, null, 1, 10, 20, &tdrag, &mds, &mres));
    try eq(bad, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, nan, 20, &tdrag, &mds, &mres));
    try eq(bad, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, 10, 0, &tdrag, &mds, &mres));
    try eq(bad, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, 10, 20, null, &mds, &mres));
    try eq(bad, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, 10, 20, &tdrag, null, &mres));
    var bad_mds = mds;
    bad_mds.border_width = -1;
    try eq(bad, zyntra_widget_modal_titled(handle, modal_id, &tbounds, "T", 1, 10, 20, &tdrag, &bad_mds, &mres));
    try eq(ok, zyntra_context_end_frame(handle));

    // Scroll: clip + scrollbar; press no thumb posiciona o offset e o
    // release encerra o arrasto. End com foco vai ao máximo.
    const sc_bounds: ct.ZyntraRect = .{ .x = 0, .y = 0, .w = 200, .h = 100 };
    const sc_id: ct.ZyntraId = 0x51;
    var off: f32 = 0;
    var sres: ct.ZyntraScrollResult = undefined;

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 24, &scs, &sres));
    try eq(@as(f32, 0), sres.offset);
    try eq(@as(f32, 200), sres.max_offset);
    try eq(@as(f32, 0), sres.content.y);
    try stdt.testing.expect(sres.hovered and !sres.scrolled and !sres.dragging);
    try eq(ok, zyntra_widget_scroll_end(handle, sc_bounds, off, 300, &scs));
    try eq(ok, zyntra_context_end_frame(handle));

    // Press no topo do thumb captura o arrasto.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 196, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 196, .y = 10 }));
    try eq(ok, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 24, &scs, &sres));
    try eq(@as(f32, 0), off);
    try eq(@as(f32, 0), sres.offset);
    try stdt.testing.expect(sres.dragging);
    try eq(ok, zyntra_widget_scroll_end(handle, sc_bounds, off, 300, &scs));
    try eq(ok, zyntra_context_end_frame(handle));

    // Mover o thumb até o meio (y=50) → offset 100 no mesmo frame.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 196, .y = 50 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 196, .y = 50 }));
    try eq(ok, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 24, &scs, &sres));
    try eq(@as(f32, 100), off);
    try eq(@as(f32, 100), sres.offset);
    try eq(@as(f32, -100), sres.content.y);
    try stdt.testing.expect(sres.dragging);
    try eq(ok, zyntra_widget_scroll_end(handle, sc_bounds, off, 300, &scs));
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 196, .y = 50 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 196, .y = 50 }));
    try eq(ok, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 24, &scs, &sres));
    try stdt.testing.expect(!sres.dragging);
    try eq(ok, zyntra_widget_scroll_end(handle, sc_bounds, off, 300, &scs));
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_key(handle, @backingInt(ct.ZyntraKey.end), true, 0));
    try eq(ok, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 24, &scs, &sres));
    try eq(@as(f32, 200), off);
    try stdt.testing.expect(sres.scrolled);
    try eq(ok, zyntra_widget_scroll_end(handle, sc_bounds, off, 300, &scs));
    try eq(ok, zyntra_context_end_frame(handle));

    // Roda com hover: dy=+5 reduz o offset em 5*speed (200 → 80).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_wheel(handle, 0, 5, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 24, &scs, &sres));
    try eq(@as(f32, 80), off);
    try stdt.testing.expect(sres.scrolled);
    try eq(ok, zyntra_widget_scroll_end(handle, sc_bounds, off, 300, &scs));
    // Deltas/posição não-finitos são eventos inválidos.
    try eq(ct.ZyntraResult.invalid_event, zyntra_context_push_mouse_wheel(handle, nan, 0, .{}));
    try eq(ct.ZyntraResult.invalid_event, zyntra_context_push_mouse_wheel(handle, 0, nan, .{}));
    try eq(ct.ZyntraResult.invalid_event, zyntra_context_push_mouse_wheel(handle, 0, 0, .{ .x = nan, .y = 0 }));
    // Inválidos: handle/id/scroll/style/geometria.
    try eq(bad, zyntra_widget_scroll_begin(null, sc_id, sc_bounds, &off, 300, 24, &scs, &sres));
    try eq(bad, zyntra_widget_scroll_begin(handle, 0, sc_bounds, &off, 300, 24, &scs, &sres));
    try eq(bad, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, null, 300, 24, &scs, &sres));
    try eq(bad, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, -1, 24, &scs, &sres));
    try eq(bad, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 0, &scs, &sres));
    try eq(bad, zyntra_widget_scroll_begin(handle, sc_id, .{ .x = 0, .y = 0, .w = 0, .h = 10 }, &off, 300, 24, &scs, &sres));
    var bad_scs = scs;
    bad_scs.bar_width = 0;
    try eq(bad, zyntra_widget_scroll_begin(handle, sc_id, sc_bounds, &off, 300, 24, &bad_scs, &sres));
    try eq(bad, zyntra_widget_scroll_end(null, sc_bounds, off, 300, &scs));
    try eq(bad, zyntra_widget_scroll_end(handle, sc_bounds, off, 300, null));
    try eq(bad, zyntra_widget_scroll_end(handle, .{ .x = 0, .y = 0, .w = 0, .h = 10 }, off, 300, &scs));
    try eq(bad, zyntra_widget_scroll_end(handle, sc_bounds, nan, 300, &scs));
    try eq(bad, zyntra_widget_scroll_end(handle, sc_bounds, off, -1, &scs));
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI DnD M117: begin, accept, drop, cancel e drag ghost" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 300, .h = 200 }, &handle));
    defer zyntra_context_destroy(handle);

    var dgs: ct.ZyntraDragGhostStyle = undefined;
    try eq(ok, zyntra_style_drag_ghost(0, &dgs));
    try stdt.testing.expect(dgs.isValid());
    try eq(bad, zyntra_style_drag_ghost(9, &dgs));
    try eq(bad, zyntra_style_drag_ghost(0, null));
    var dgres: ct.ZyntraDragGhostResult = undefined;

    // Sem arraste: nenhum comando e resultado vazio.
    try eq(ok, zyntra_context_begin_frame(handle));
    var n_before: usize = 0;
    var n_after: usize = 0;
    try eq(ok, zyntra_draw_count(handle, &n_before));
    try eq(ok, zyntra_widget_drag_ghost(handle, &dgs, 10, &dgres));
    try stdt.testing.expect(!dgres.drawn);
    try eq(ct.ZyntraRect{}, dgres.rect);
    try eq(ct.ZyntraTextMetrics{}, dgres.metrics);
    try eq(ok, zyntra_draw_count(handle, &n_after));
    try eq(n_before, n_after);
    // Inválidos do ghost: handle/estilo/fonte.
    try eq(bad, zyntra_widget_drag_ghost(null, &dgs, 10, &dgres));
    try eq(bad, zyntra_widget_drag_ghost(handle, null, 10, &dgres));
    try eq(bad, zyntra_widget_drag_ghost(handle, &dgs, 0, &dgres));
    var bad_dgs = dgs;
    bad_dgs.pad = -1;
    try eq(bad, zyntra_widget_drag_ghost(handle, &bad_dgs, 10, &dgres));
    try eq(ok, zyntra_context_end_frame(handle));

    // Inicia o arraste e move: distância 5 (3-4-5), alvo sob o cursor.
    const src: ct.ZyntraId = 0xD1;
    const target: ct.ZyntraId = 0xD2;
    const target_bounds: ct.ZyntraRect = .{ .x = 10, .y = 20, .w = 80, .h = 60 };
    var data_value: u32 = 42;
    const data_ptr: *const anyopaque = @ptrCast(&data_value);

    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 20, .y = 30 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 20, .y = 30 }));
    try eq(ok, zyntra_dnd_begin(handle, src, "chip", 4, data_ptr, "chip", 4));
    var dragging = false;
    try eq(ok, zyntra_dnd_is_dragging(handle, &dragging));
    try stdt.testing.expect(dragging);

    var got_src: ct.ZyntraId = 0;
    try eq(ok, zyntra_dnd_drag_source(handle, &got_src));
    try eq(src, got_src);
    var pos: ct.ZyntraVec2 = .{};
    var origin: ct.ZyntraVec2 = .{};
    try eq(ok, zyntra_dnd_drag_position(handle, &pos));
    try eq(@as(f32, 20), pos.x);
    try eq(@as(f32, 30), pos.y);
    try eq(ok, zyntra_dnd_drag_origin(handle, &origin));
    try eq(pos, origin);
    var dist: f32 = -1;
    try eq(ok, zyntra_dnd_drag_distance(handle, &dist));
    try eq(@as(f32, 0), dist);

    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 23, .y = 34 }));
    try eq(ok, zyntra_dnd_drag_distance(handle, &dist));
    try eq(@as(f32, 5), dist);
    var exceeds = false;
    try eq(ok, zyntra_dnd_drag_exceeds(handle, 4, &exceeds));
    try stdt.testing.expect(exceeds);
    try eq(ok, zyntra_dnd_drag_exceeds(handle, 5, &exceeds));
    try stdt.testing.expect(!exceeds);

    var accept: ct.ZyntraDndAccept = .none;
    try eq(ok, zyntra_dnd_accept(handle, target, target_bounds, &accept));
    try eq(ct.ZyntraDndAccept.hover, accept);
    var hover: ct.ZyntraId = 0;
    try eq(ok, zyntra_dnd_hover_target(handle, &hover));
    try eq(target, hover);

    // Ghost: caixa 48×22.625 sob o cursor + offset 10, rótulo "chip".
    try eq(ok, zyntra_widget_drag_ghost(handle, &dgs, 10, &dgres));
    try stdt.testing.expect(dgres.drawn);
    try eq(@as(f32, 33), dgres.rect.x);
    try eq(@as(f32, 44), dgres.rect.y);
    try eq(@as(f32, 48), dgres.rect.w);
    try stdt.testing.expectApproxEqAbs(@as(f32, 22.625), dgres.rect.h, 0.001);
    try eq(@as(f32, 24), dgres.metrics.width);
    try eq(ok, zyntra_draw_count(handle, &n_after));
    try stdt.testing.expect(n_after >= n_before + 4); // sombra + caixa + borda + texto
    // `out_result` nulo é válido (só desenha).
    try eq(ok, zyntra_widget_drag_ghost(handle, &dgs, 10, null));
    try eq(ok, zyntra_context_end_frame(handle));

    // Release encerra o arraste; o solto é resolvido no begin_frame seguinte.
    // O alvo precisa ser registrado também neste frame (accept todo frame).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 23, .y = 34 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 23, .y = 34 }));
    accept = .none;
    try eq(ok, zyntra_dnd_accept(handle, target, target_bounds, &accept));
    try eq(ct.ZyntraDndAccept.hover, accept);
    try eq(ok, zyntra_context_end_frame(handle));

    try eq(ok, zyntra_context_begin_frame(handle));
    dragging = true;
    try eq(ok, zyntra_dnd_is_dragging(handle, &dragging));
    try stdt.testing.expect(!dragging);
    var drop: ct.ZyntraDndDrop = undefined;
    try eq(ok, zyntra_dnd_last_drop(handle, &drop));
    try stdt.testing.expect(drop.present and !drop.cancelled);
    try eq(target, drop.target);
    try eq(src, drop.source);
    try eq(@as(usize, 4), drop.kind.len);
    try stdt.testing.expectEqualStrings("chip", drop.kind.ptr.?[0..drop.kind.len]);
    try stdt.testing.expectEqualStrings("chip", drop.label.ptr.?[0..drop.label.len]);
    try stdt.testing.expect(drop.data == data_ptr);
    accept = .none;
    try eq(ok, zyntra_dnd_accept(handle, target, target_bounds, &accept));
    try eq(ct.ZyntraDndAccept.dropped, accept);
    accept = .none;
    try eq(ok, zyntra_dnd_accept(handle, 0xDEAD, target_bounds, &accept));
    try eq(ct.ZyntraDndAccept.none, accept);
    try eq(ok, zyntra_context_end_frame(handle));

    // O solto vale por um frame apenas.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_dnd_last_drop(handle, &drop));
    try stdt.testing.expect(!drop.present and !drop.cancelled);
    try eq(@as(ct.ZyntraId, 0), drop.target);
    try eq(@as(usize, 0), drop.kind.len);
    try eq(ok, zyntra_context_end_frame(handle));

    // Cancelamento explícito: sem alvo e `cancelled`.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 10, .y = 10 }));
    try eq(ok, zyntra_dnd_begin(handle, src, "node", 4, null, null, 0));
    try eq(ok, zyntra_dnd_is_dragging(handle, &dragging));
    try stdt.testing.expect(dragging);
    try eq(ok, zyntra_dnd_cancel(handle));
    try eq(ok, zyntra_dnd_is_dragging(handle, &dragging));
    try stdt.testing.expect(!dragging);
    try eq(ok, zyntra_dnd_last_drop(handle, &drop));
    try stdt.testing.expect(drop.present and drop.cancelled);
    try eq(@as(ct.ZyntraId, 0), drop.target);
    try eq(src, drop.source);
    try stdt.testing.expectEqualStrings("node", drop.kind.ptr.?[0..drop.kind.len]);
    try eq(@as(usize, 0), drop.label.len);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos: handle/id/kind/label/UTF-8/out nulos.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 10, .y = 10 }));
    try eq(bad, zyntra_dnd_begin(null, src, "k", 1, null, null, 0));
    try eq(bad, zyntra_dnd_begin(handle, 0, "k", 1, null, null, 0));
    try eq(bad, zyntra_dnd_begin(handle, src, null, 1, null, null, 0));
    try eq(bad, zyntra_dnd_begin(handle, src, "k", 0, null, null, 0));
    try eq(bad, zyntra_dnd_begin(handle, src, "k", 1, null, null, 1));
    try eq(bad, zyntra_dnd_begin(handle, src, "\xff", 1, null, null, 0));
    try eq(bad, zyntra_dnd_begin(handle, src, "k", 1, null, "\xff", 1));
    try eq(bad, zyntra_dnd_cancel(null));
    try eq(bad, zyntra_dnd_is_dragging(null, &dragging));
    try eq(bad, zyntra_dnd_is_dragging(handle, null));
    try eq(bad, zyntra_dnd_accept(null, target, target_bounds, &accept));
    try eq(bad, zyntra_dnd_accept(handle, target, target_bounds, null));
    try eq(bad, zyntra_dnd_last_drop(null, &drop));
    try eq(bad, zyntra_dnd_last_drop(handle, null));
    try eq(bad, zyntra_dnd_drag_source(null, &got_src));
    try eq(bad, zyntra_dnd_drag_source(handle, null));
    try eq(bad, zyntra_dnd_hover_target(null, &hover));
    try eq(bad, zyntra_dnd_drag_position(null, &pos));
    try eq(bad, zyntra_dnd_drag_origin(handle, null));
    try eq(bad, zyntra_dnd_drag_distance(null, &dist));
    try eq(bad, zyntra_dnd_drag_exceeds(null, 1, &exceeds));
    try eq(bad, zyntra_dnd_drag_exceeds(handle, 1, null));
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI barras M118: toolbar e statusbar" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const nan = std.math.nan(f32);

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 300, .h = 200 }, &handle));
    defer zyntra_context_destroy(handle);

    var tbs: ct.ZyntraToolbarStyle = undefined;
    var sbs: ct.ZyntraStatusBarStyle = undefined;
    var ses: ct.ZyntraSeparatorStyle = undefined;
    try eq(ok, zyntra_style_toolbar(0, &tbs));
    try eq(ok, zyntra_style_status_bar(1, &sbs));
    try eq(ok, zyntra_style_separator(0, &ses));
    try stdt.testing.expect(tbs.isValid() and sbs.isValid() and ses.isValid());
    try eq(bad, zyntra_style_toolbar(9, &tbs));
    try eq(bad, zyntra_style_status_bar(0, null));
    ses.thickness = 2;

    // Toolbar: chrome, conteúdo, itens, separador e overflow.
    var tbar: ct.ZyntraToolbar = undefined;
    var r: ct.ZyntraRect = undefined;
    var rem: f32 = -1;
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_toolbar(handle, .{ .x = 0, .y = 0, .w = 200, .h = 40 }, &tbs, &tbar));
    try eq(ct.ZyntraRect{ .x = 8, .y = 6, .w = 184, .h = 28 }, tbar.content);
    try eq(@as(f32, 28), tbar.item_h);
    try eq(@as(f32, 6), tbar.spacing);
    try stdt.testing.expect(!tbar.overflowed);
    try eq(ok, zyntra_toolbar_next_item(&tbar, 50, &r));
    try eq(ct.ZyntraRect{ .x = 8, .y = 6, .w = 50, .h = 28 }, r);
    try eq(ok, zyntra_toolbar_next_item(&tbar, 30, &r));
    try eq(ct.ZyntraRect{ .x = 64, .y = 6, .w = 30, .h = 28 }, r);
    try eq(ok, zyntra_toolbar_remaining(&tbar, &rem));
    try eq(@as(f32, 92), rem);
    try eq(ok, zyntra_toolbar_separator(handle, &tbar, &ses));
    try eq(@as(f32, 108), tbar.cursor);
    try eq(ok, zyntra_toolbar_remaining(&tbar, &rem));
    try eq(@as(f32, 84), rem);
    try stdt.testing.expect(!tbar.overflowed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Overflow: segundo item pede 60, só restam 18.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_toolbar(handle, .{ .x = 0, .y = 0, .w = 100, .h = 40 }, &tbs, &tbar));
    try eq(ok, zyntra_toolbar_next_item(&tbar, 60, &r));
    try eq(@as(f32, 60), r.w);
    try eq(ok, zyntra_toolbar_next_item(&tbar, 60, &r));
    try eq(@as(f32, 18), r.w);
    try stdt.testing.expect(tbar.overflowed);
    try eq(ok, zyntra_toolbar_remaining(&tbar, &rem));
    try eq(@as(f32, 0), rem);
    try eq(ok, zyntra_context_end_frame(handle));

    // Statusbar: esquerda, direita, texto e separador.
    var sbar: ct.ZyntraStatusBar = undefined;
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_status_bar(handle, .{ .x = 0, .y = 0, .w = 200, .h = 28 }, &sbs, &sbar));
    try eq(ct.ZyntraRect{ .x = 8, .y = 4, .w = 184, .h = 20 }, sbar.content);
    try eq(@as(f32, 20), sbar.item_h);
    try eq(ok, zyntra_status_bar_next_item(&sbar, 50, &r));
    try eq(ct.ZyntraRect{ .x = 8, .y = 4, .w = 50, .h = 20 }, r);
    try eq(ok, zyntra_status_bar_next_right(&sbar, 30, &r));
    try eq(ct.ZyntraRect{ .x = 162, .y = 4, .w = 30, .h = 20 }, r);
    try eq(ok, zyntra_status_bar_remaining(&sbar, &rem));
    try eq(@as(f32, 92), rem);
    try stdt.testing.expect(!sbar.overflowed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Texto "OK" (2 glifos × 6 = 12) posiciona e emite 1 comando.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_status_bar(handle, .{ .x = 0, .y = 0, .w = 200, .h = 28 }, &sbs, &sbar));
    var n0: usize = 0;
    var n1: usize = 0;
    try eq(ok, zyntra_draw_count(handle, &n0));
    try eq(ok, zyntra_status_bar_text(handle, &sbar, "OK", 2, 10, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, &r));
    try eq(ct.ZyntraRect{ .x = 8, .y = 4, .w = 12, .h = 20 }, r);
    try eq(ok, zyntra_draw_count(handle, &n1));
    try eq(n0 + 1, n1);
    try eq(@as(f32, 26), sbar.left_cursor);
    // `out_rect` nulo é válido (só desenha).
    try eq(ok, zyntra_status_bar_text(handle, &sbar, "!", 1, 10, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, null));
    try eq(ok, zyntra_status_bar_separator(handle, &sbar, &ses));
    try eq(ok, zyntra_context_end_frame(handle));

    // Overflow dos dois lados: nunca se sobrepõem.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_status_bar(handle, .{ .x = 0, .y = 0, .w = 100, .h = 28 }, &sbs, &sbar));
    try eq(ok, zyntra_status_bar_next_item(&sbar, 60, &r));
    try eq(@as(f32, 60), r.w);
    try eq(ok, zyntra_status_bar_next_right(&sbar, 60, &r));
    try eq(@as(f32, 18), r.w);
    try eq(@as(f32, 74), r.x);
    try stdt.testing.expect(sbar.overflowed);
    try eq(ok, zyntra_status_bar_remaining(&sbar, &rem));
    try eq(@as(f32, 0), rem);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos: handle/out/estado corrompido/fonte/texto.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(bad, zyntra_widget_toolbar(null, .{ .x = 0, .y = 0, .w = 100, .h = 40 }, &tbs, &tbar));
    try eq(bad, zyntra_widget_toolbar(handle, .{ .x = 0, .y = 0, .w = 100, .h = 40 }, null, &tbar));
    try eq(bad, zyntra_widget_toolbar(handle, .{ .x = 0, .y = 0, .w = 0, .h = 40 }, &tbs, &tbar));
    try eq(bad, zyntra_widget_toolbar(handle, .{ .x = 0, .y = 0, .w = 100, .h = 40 }, &tbs, null));
    var bad_ts = tbs;
    bad_ts.spacing = -1;
    try eq(bad, zyntra_widget_toolbar(handle, .{ .x = 0, .y = 0, .w = 100, .h = 40 }, &bad_ts, &tbar));
    try eq(ok, zyntra_widget_toolbar(handle, .{ .x = 0, .y = 0, .w = 200, .h = 40 }, &tbs, &tbar));
    try eq(bad, zyntra_toolbar_next_item(null, 10, &r));
    try eq(bad, zyntra_toolbar_next_item(&tbar, 10, null));
    try eq(bad, zyntra_toolbar_remaining(null, &rem));
    try eq(bad, zyntra_toolbar_remaining(&tbar, null));
    try eq(bad, zyntra_toolbar_separator(null, &tbar, &ses));
    try eq(bad, zyntra_toolbar_separator(handle, null, &ses));
    try eq(bad, zyntra_toolbar_separator(handle, &tbar, null));
    var bad_bar = tbar;
    bad_bar.item_h = nan;
    try eq(bad, zyntra_toolbar_next_item(&bad_bar, 10, &r));
    bad_bar = tbar;
    bad_bar.cursor = nan;
    try eq(bad, zyntra_toolbar_next_item(&bad_bar, 10, &r));
    bad_bar = tbar;
    bad_bar.content.w = -1;
    try eq(bad, zyntra_toolbar_remaining(&bad_bar, &rem));
    var bad_sep = ses;
    bad_sep.thickness = 0;
    try eq(bad, zyntra_toolbar_separator(handle, &tbar, &bad_sep));

    try eq(bad, zyntra_widget_status_bar(null, .{ .x = 0, .y = 0, .w = 100, .h = 28 }, &sbs, &sbar));
    try eq(bad, zyntra_widget_status_bar(handle, .{ .x = 0, .y = 0, .w = 100, .h = 28 }, null, &sbar));
    try eq(bad, zyntra_widget_status_bar(handle, .{ .x = 0, .y = 0, .w = 100, .h = 28 }, &sbs, null));
    try eq(ok, zyntra_widget_status_bar(handle, .{ .x = 0, .y = 0, .w = 200, .h = 28 }, &sbs, &sbar));
    try eq(bad, zyntra_status_bar_next_item(null, 10, &r));
    try eq(bad, zyntra_status_bar_next_item(&sbar, 10, null));
    try eq(bad, zyntra_status_bar_next_right(null, 10, &r));
    try eq(bad, zyntra_status_bar_next_right(&sbar, 10, null));
    try eq(bad, zyntra_status_bar_remaining(null, &rem));
    try eq(bad, zyntra_status_bar_remaining(&sbar, null));
    try eq(bad, zyntra_status_bar_text(null, &sbar, "T", 1, 10, .{}, &r));
    try eq(bad, zyntra_status_bar_text(handle, null, "T", 1, 10, .{}, &r));
    try eq(bad, zyntra_status_bar_text(handle, &sbar, "T", 1, 0, .{}, &r));
    try eq(bad, zyntra_status_bar_text(handle, &sbar, null, 1, 10, .{}, &r));
    try eq(bad, zyntra_status_bar_text(handle, &sbar, "\xff", 1, 10, .{}, &r));
    try eq(bad, zyntra_status_bar_separator(null, &sbar, &ses));
    try eq(bad, zyntra_status_bar_separator(handle, null, &ses));
    try eq(bad, zyntra_status_bar_separator(handle, &sbar, null));
    var bad_sbar = sbar;
    bad_sbar.right_x = nan;
    try eq(bad, zyntra_status_bar_next_right(&bad_sbar, 10, &r));
    bad_sbar = sbar;
    bad_sbar.left_cursor = nan;
    try eq(bad, zyntra_status_bar_next_item(&bad_sbar, 10, &r));
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI grafo M119: estilo, estado, hover, arraste, pan e zoom" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const nan = std.math.nan(f32);

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 400, .h = 300 }, &handle));
    defer zyntra_context_destroy(handle);

    var style: ct.ZyntraGraphStyle = undefined;
    var state: ct.ZyntraGraphViewState = undefined;
    var options: ct.ZyntraGraphViewOptions = undefined;
    try eq(ok, zyntra_style_graph(0, &style));
    try stdt.testing.expect(style.isValid());
    try eq(bad, zyntra_style_graph(9, &style));
    try eq(bad, zyntra_style_graph(0, null));
    try eq(ok, zyntra_graph_view_state_init(&state));
    try eq(@as(f32, 1), state.transform.zoom);
    try eq(@as(i64, -1), state.selected);
    try eq(@as(i64, -1), state.drag_node);
    try stdt.testing.expect(!state.panning);
    try eq(ok, zyntra_graph_view_options_default(&options));
    try stdt.testing.expectEqual(ct.ZyntraGraphViewOptions{}, options);
    try eq(bad, zyntra_graph_view_state_init(null));
    try eq(bad, zyntra_graph_view_options_default(null));

    var nodes = [_]ct.ZyntraGraphNode{
        .{
            .pos = .{ .x = 0, .y = 0 },
            .size = .{ .x = 100, .y = 60 },
            .title = .{ .ptr = "A", .len = 1 },
            .inputs = 0,
            .outputs = 1,
        },
        .{
            .pos = .{ .x = 150, .y = 0 },
            .size = .{ .x = 100, .y = 60 },
            .title = .{ .ptr = "B", .len = 1 },
            .inputs = 1,
            .outputs = 0,
        },
    };
    const edges = [_]ct.ZyntraGraphEdge{.{ .from = 0, .to = 1 }};
    const bounds = ct.ZyntraRect{ .x = 0, .y = 0, .w = 400, .h = 300 };
    var res: ct.ZyntraGraphViewResult = undefined;
    var n_draw: usize = 0;

    // Frame 1: desenho sem cursor.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.hovered);
    try eq(@as(i64, -1), res.selected);
    try eq(@as(i64, -1), res.dragging);
    try stdt.testing.expect(!res.changed and !res.panning and !res.zoom_changed);
    try eq(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expect(n_draw > 0);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 2: hover no nó A.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 50, .y = 30 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 0), res.hovered);
    try stdt.testing.expect(!res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 3: press seleciona e captura o nó A.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 50, .y = 30 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 50, .y = 30 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 0), res.selected);
    try eq(@as(i64, 0), res.dragging);
    try stdt.testing.expect(res.changed);
    try eq(@as(i64, 0), state.selected);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 4: arraste move o nó em mundo e escreve `pos` de volta no C.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 80, .y = 40 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 0), res.dragging);
    try eq(@as(f32, 30), res.drag_delta.x);
    try eq(@as(f32, 10), res.drag_delta.y);
    try eq(@as(f32, 30), nodes[0].pos.x);
    try eq(@as(f32, 10), nodes[0].pos.y);
    try stdt.testing.expect(res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 5: release encerra o arraste, mantendo a seleção.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 80, .y = 40 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 80, .y = 40 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.dragging);
    try eq(@as(i64, 0), res.selected);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 6: press no vazio inicia o pan.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 300, .y = 200 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 300, .y = 200 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(res.panning);
    try eq(@as(i64, -1), res.hovered);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 7: pan incremental.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 310, .y = 220 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(@as(f32, 10), res.pan_delta.x);
    try eq(@as(f32, 20), res.pan_delta.y);
    try eq(@as(f32, 10), state.transform.pan.x);
    try eq(@as(f32, 20), state.transform.pan.y);
    try stdt.testing.expect(res.panning and res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 8: release do pan.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 310, .y = 220 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 310, .y = 220 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(!res.panning);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 9: roda dá zoom (passo 1.25) mantendo o cursor como âncora.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 200, .y = 150 }));
    try eq(ok, zyntra_context_push_mouse_wheel(handle, 0, 1, .{ .x = 200, .y = 150 }));
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(res.zoom_changed);
    try eq(@as(f32, 1.25), state.transform.zoom);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos: handle/id/ponteiros/geometria/estado/opções/fonte.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(bad, zyntra_widget_graph_view(null, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, null, 1, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, null, 1, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, .{ .x = 0, .y = 0, .w = 0, .h = 300 }, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, null, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, null, &style, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, null, 10, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, 0, &res));
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &options, &style, nan, &res));

    var bad_nodes = nodes;
    bad_nodes[0].size.x = 0;
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &bad_nodes, bad_nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));
    bad_nodes = nodes;
    bad_nodes[0].title = .{ .ptr = null, .len = 1 };
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &bad_nodes, bad_nodes.len, &edges, edges.len, &state, &options, &style, 10, &res));

    var bad_state = state;
    bad_state.transform.zoom = 0;
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &bad_state, &options, &style, 10, &res));

    var bad_options = options;
    bad_options.edge_segments = 0;
    try eq(bad, zyntra_widget_graph_view(handle, 0x6101, bounds, &nodes, nodes.len, &edges, edges.len, &state, &bad_options, &style, 10, &res));

    // Conjunto vazio é aceito e `out_result` nulo é válido.
    try eq(ok, zyntra_widget_graph_view(handle, 0x6101, bounds, null, 0, null, 0, &state, &options, &style, 10, null));
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI timeline M120: hover, chave, scrub, zoom e write-back" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const nan = std.math.nan(f32);

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 260, .h = 160 }, &handle));
    defer zyntra_context_destroy(handle);

    var style: ct.ZyntraTimelineStyle = undefined;
    var state: ct.ZyntraTimelineViewState = undefined;
    var options: ct.ZyntraTimelineViewOptions = undefined;
    try eq(ok, zyntra_style_timeline(0, &style));
    try stdt.testing.expect(style.isValid());
    try eq(bad, zyntra_style_timeline(9, &style));
    try eq(bad, zyntra_style_timeline(0, null));
    try eq(ok, zyntra_timeline_view_state_init(&state));
    try eq(@as(f32, 10), state.duration);
    try eq(@as(f32, 80), state.transform.pps);
    try eq(@as(i64, -1), state.selected_track);
    try eq(@as(i64, -1), state.drag_key);
    try eq(@as(i32, 0), state.drag);
    try eq(ok, zyntra_timeline_view_options_default(&options));
    try stdt.testing.expectEqual(ct.ZyntraTimelineViewOptions{}, options);
    try eq(bad, zyntra_timeline_view_state_init(null));
    try eq(bad, zyntra_timeline_view_options_default(null));
    options.snap_keys = false; // passo exato de 0.125 s no arraste

    var keys = [_]ct.ZyntraTimelineKey{
        .{ .t = 0.5, .tag = 7 },
        .{ .t = 1.0, .tag = 8 },
    };
    var tracks = [_]ct.ZyntraTimelineTrack{
        .{ .name = .{ .ptr = "T", .len = 1 }, .keys = &keys, .keys_len = keys.len },
    };
    const bounds = ct.ZyntraRect{ .x = 0, .y = 0, .w = 240, .h = 120 };
    var res: ct.ZyntraTimelineViewResult = undefined;
    var n_draw: usize = 0;

    // Frame 1: desenho.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.hovered_track);
    try eq(@as(i64, -1), res.hovered_key);
    try eq(@as(i64, -1), res.selected_track);
    try eq(@as(i64, -1), res.dragging_track);
    try eq(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expect(n_draw > 0);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 2: hover na chave 0 (t=0.5 ⇒ x=130, y=34).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 130, .y = 34 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 0), res.hovered_track);
    try eq(@as(i64, 0), res.hovered_key);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 3: press seleciona e captura a chave.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 130, .y = 34 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 130, .y = 34 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 0), res.selected_track);
    try eq(@as(i64, 0), res.selected_key);
    try eq(@as(i64, 0), res.dragging_track);
    try eq(@as(i64, 0), res.dragging_key);
    try stdt.testing.expect(res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 4: arraste para t=0.625, write-back em keys[0].t, tag intacta.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 140, .y = 34 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try eq(@as(f32, 0.125), res.key_delta);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.625), keys[0].t, 0.0001);
    try eq(@as(u32, 7), keys[0].tag);
    try eq(@as(i64, 0), res.dragging_key);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 5: release encerra o arraste.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 140, .y = 34 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 140, .y = 34 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.dragging_track);
    try eq(@as(i64, 0), res.selected_track);
    try eq(@as(i64, 0), res.selected_key);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 6: scrub na régua (y=10) ⇒ playhead 0.375.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 120, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 120, .y = 10 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(res.scrubbing);
    try eq(@as(f32, 0.375), res.playhead);
    try stdt.testing.expect(res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 7: arraste da régua ⇒ playhead 0.75.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 10 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(res.scrubbing);
    try eq(@as(f32, 0.75), res.playhead);
    try eq(@as(f32, 0.75), state.playhead);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 8: release do scrub.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 150, .y = 10 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(!res.scrubbing);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 9: roda dá zoom (80 → 100 px/s).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 50 }));
    try eq(ok, zyntra_context_push_mouse_wheel(handle, 0, 1, .{ .x = 150, .y = 50 }));
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(res.zoom_changed);
    try eq(@as(f32, 100), state.transform.pps);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos: handle/id/ponteiros/estado/opções/fonte/track.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(bad, zyntra_widget_timeline_view(null, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_timeline_view(handle, 0, bounds, &tracks, tracks.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, null, 1, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, null, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, null, &style, 10, &res));
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, null, 10, &res));
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, 0, &res));
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &options, &style, nan, &res));

    var bad_tracks = tracks;
    bad_tracks[0].name = .{ .ptr = null, .len = 1 };
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &bad_tracks, bad_tracks.len, &state, &options, &style, 10, &res));
    bad_tracks = tracks;
    bad_tracks[0].keys = null;
    bad_tracks[0].keys_len = 1;
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &bad_tracks, bad_tracks.len, &state, &options, &style, 10, &res));

    var bad_state = state;
    bad_state.transform.pps = 0;
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &bad_state, &options, &style, 10, &res));
    bad_state = state;
    bad_state.duration = 0;
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &bad_state, &options, &style, 10, &res));
    bad_state = state;
    bad_state.playhead = nan;
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &bad_state, &options, &style, 10, &res));
    bad_state = state;
    bad_state.drag = 9;
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &bad_state, &options, &style, 10, &res));

    var bad_options = options;
    bad_options.min_pps = 0;
    try eq(bad, zyntra_widget_timeline_view(handle, 0x7101, bounds, &tracks, tracks.len, &state, &bad_options, &style, 10, &res));

    // Conjunto vazio e `out_result` nulo são válidos.
    try eq(ok, zyntra_widget_timeline_view(handle, 0x7101, bounds, null, 0, &state, &options, &style, 10, null));
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI inspector M121: bool, inteiro, real, escolha e rolagem" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const nan = std.math.nan(f32);

    var handle: ?*ZyntraContext = null;
    try eq(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 260, .h = 160 }, &handle));
    defer zyntra_context_destroy(handle);

    var style: ct.ZyntraInspectorStyle = undefined;
    var state: ct.ZyntraInspectorViewState = undefined;
    var options: ct.ZyntraInspectorViewOptions = undefined;
    try eq(ok, zyntra_style_inspector(0, &style));
    try stdt.testing.expect(style.isValid());
    try eq(bad, zyntra_style_inspector(9, &style));
    try eq(bad, zyntra_style_inspector(0, null));
    try eq(ok, zyntra_inspector_view_state_init(&state));
    try eq(@as(i64, -1), state.active);
    try eq(@as(i64, -1), state.dragging);
    try eq(@as(f32, 0), state.scroll);
    try eq(ok, zyntra_inspector_view_options_default(&options));
    try stdt.testing.expectEqual(ct.ZyntraInspectorViewOptions{}, options);
    try eq(bad, zyntra_inspector_view_state_init(null));
    try eq(bad, zyntra_inspector_view_options_default(null));

    var c_bool = false;
    var c_integer: i64 = 10;
    var c_real: f32 = 1.5;
    var c_choice: u32 = 0;
    var c_extra: i64 = 0;
    const c_opts = [_]ct.ZyntraStr{
        .{ .ptr = "One", .len = 3 },
        .{ .ptr = "Two", .len = 3 },
    };
    var props = [_]ct.ZyntraInspectorProperty{
        .{ .name = .{ .ptr = "A", .len = 1 }, .kind = 0, .value = &c_bool },
        .{ .name = .{ .ptr = "B", .len = 1 }, .kind = 1, .value = &c_integer },
        .{ .name = .{ .ptr = "C", .len = 1 }, .kind = 2, .value = &c_real },
        .{ .name = .{ .ptr = "D", .len = 1 }, .kind = 3, .readonly = true, .text = .{ .ptr = "read", .len = 4 } },
        .{ .name = .{ .ptr = "E", .len = 1 }, .kind = 4, .choice = .{ .index = @ptrCast(&c_choice), .options = @ptrCast(&c_opts), .options_len = c_opts.len } },
        .{ .name = .{ .ptr = "F", .len = 1 }, .kind = 1, .value = &c_extra },
    };
    const bounds = ct.ZyntraRect{ .x = 0, .y = 0, .w = 260, .h = 120 };
    var res: ct.ZyntraInspectorViewResult = undefined;
    var n_draw: usize = 0;

    // Frame 1: desenho.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.hovered);
    try eq(@as(i64, -1), res.active);
    try eq(@as(i64, -1), res.changed);
    try eq(@as(i64, -1), res.dragging);
    try eq(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expect(n_draw > 0);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 2: hover na linha 1.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 30 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 1), res.hovered);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 3: press na linha 0 alterna o booleano.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 30, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 30, .y = 10 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(c_bool);
    try eq(@as(i64, 0), res.active);
    try stdt.testing.expect(res.active_changed);
    try eq(@as(i64, 0), res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 4: release.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 30, .y = 10 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 30, .y = 10 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.dragging);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 5: press na linha 1 inicia o arraste do inteiro.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 30 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 150, .y = 30 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 1), res.active);
    try eq(@as(i64, 1), res.dragging);
    try eq(@as(f32, 10), state.drag_anchor);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 6: dx=+10 ⇒ inteiro 10 → 20 (passo 1).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 160, .y = 30 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 20), c_integer);
    try eq(@as(i64, 1), res.changed);
    try eq(@as(i64, 1), res.dragging);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 7: release.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 160, .y = 30 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 160, .y = 30 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.dragging);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 8: press na linha 2 inicia o arraste do real.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 60 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 150, .y = 60 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, 2), res.dragging);
    try eq(@as(f32, 1.5), state.drag_anchor);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 9: dx=+5, passo 0.01 ⇒ 1.5 → 1.55.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 155, .y = 60 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try stdt.testing.expectApproxEqAbs(@as(f32, 1.55), c_real, 0.0001);
    try eq(@as(i64, 2), res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 10: release.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 155, .y = 60 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 155, .y = 60 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(i64, -1), res.dragging);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 11: press na escolha (linha 4) avança para a opção 1.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 110 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, true, .{ .x = 150, .y = 110 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(@as(u32, 1), c_choice);
    try eq(@as(i64, 4), res.active);
    try eq(@as(i64, 4), res.changed);
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 12: release.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 110 }));
    try eq(ok, zyntra_context_push_mouse_button(handle, 0, false, .{ .x = 150, .y = 110 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(ok, zyntra_context_end_frame(handle));

    // Frame 13: roda rola 24 px (6 linhas × 24 − 120).
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(ok, zyntra_context_push_mouse_move(handle, .{ .x = 150, .y = 60 }));
    try eq(ok, zyntra_context_push_mouse_wheel(handle, 0, -1, .{ .x = 150, .y = 60 }));
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try stdt.testing.expect(res.scrolled);
    try eq(@as(f32, 24), state.scroll);
    try eq(@as(f32, 24), res.scroll_delta);
    try eq(ok, zyntra_context_end_frame(handle));

    // Inválidos.
    try eq(ok, zyntra_context_begin_frame(handle));
    try eq(bad, zyntra_widget_inspector_view(null, 0x7201, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_inspector_view(handle, 0, bounds, &props, props.len, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, null, 1, &state, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, null, &options, &style, 10, &res));
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, null, &style, 10, &res));
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, null, 10, &res));
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, 0, &res));
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &options, &style, nan, &res));

    var bad_props = props;
    bad_props[0].name = .{ .ptr = null, .len = 1 };
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[0].kind = 9;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[0].value = null;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[3].text = .{ .ptr = null, .len = 1 };
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[4].choice.options = null;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[4].choice.options_len = 0;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[4].choice.index = null;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[2].has_step = true;
    bad_props[2].step = 0;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[2].has_decimals = true;
    bad_props[2].decimals = 7;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));
    bad_props = props;
    bad_props[1].has_range = true;
    bad_props[1].range = .{ .min = nan, .max = 1 };
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &bad_props, bad_props.len, &state, &options, &style, 10, &res));

    var bad_state = state;
    bad_state.scroll = nan;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &bad_state, &options, &style, 10, &res));
    var bad_options = options;
    bad_options.step = 0;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &bad_options, &style, 10, &res));
    bad_options = options;
    bad_options.decimals = 7;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &bad_options, &style, 10, &res));
    bad_options = options;
    bad_options.scroll_step = -1;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &bad_options, &style, 10, &res));
    bad_options = options;
    bad_options.coarse_factor = 0.5;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &bad_options, &style, 10, &res));
    bad_options = options;
    bad_options.fine_factor = 0;
    try eq(bad, zyntra_widget_inspector_view(handle, 0x7201, bounds, &props, props.len, &state, &bad_options, &style, 10, &res));

    // Conjunto vazio e `out_result` nulo são válidos.
    try eq(ok, zyntra_widget_inspector_view(handle, 0x7201, bounds, null, 0, &state, &options, &style, 10, null));
    try eq(ok, zyntra_context_end_frame(handle));
}

test "C-ABI animação M122: easing, tween, timer e cor" {
    const stdt = @import("std");
    const eq = stdt.testing.expectEqual;
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    const nan = std.math.nan(f32);

    var v: f32 = -1;
    try eq(ok, zyntra_ease_apply(0, 0.5, &v));
    try eq(@as(f32, 0.5), v);
    try eq(ok, zyntra_ease_apply(2, 0.5, &v));
    try eq(@as(f32, 0.75), v);
    try eq(ok, zyntra_ease_apply(5, 0.5, &v));
    try eq(@as(f32, 0.875), v);
    try eq(ok, zyntra_ease_apply(0, nan, &v));
    try eq(@as(f32, 0), v);
    try eq(ok, zyntra_ease_apply(0, 9, &v));
    try eq(@as(f32, 1), v);
    try eq(bad, zyntra_ease_apply(9, 0.5, &v));
    try eq(bad, zyntra_ease_apply(0, 0.5, null));

    var tw: ct.ZyntraTween = undefined;
    try eq(ok, zyntra_tween_init(&tw, 0, 100, 2, 0));
    try eq(@as(f32, 0), tw.from);
    try eq(@as(f32, 100), tw.to);
    try eq(@as(f32, 2), tw.duration);
    try eq(@as(i32, 0), tw.ease);
    try eq(ok, zyntra_tween_value_at(&tw, 1, &v));
    try eq(@as(f32, 50), v);
    try eq(ok, zyntra_tween_value_at(&tw, 3, &v));
    try eq(@as(f32, 100), v);
    try eq(ok, zyntra_tween_value_at(&tw, -1, &v));
    try eq(@as(f32, 0), v);
    var done = true;
    try eq(ok, zyntra_tween_done_at(&tw, 1.9, &done));
    try stdt.testing.expect(!done);
    try eq(ok, zyntra_tween_done_at(&tw, 2, &done));
    try stdt.testing.expect(done);
    try eq(bad, zyntra_tween_init(null, 0, 1, 1, 0));
    try eq(bad, zyntra_tween_init(&tw, 0, 1, 0, 0));
    try eq(bad, zyntra_tween_init(&tw, nan, 1, 1, 0));
    try eq(bad, zyntra_tween_init(&tw, 0, 1, 1, 9));
    try eq(bad, zyntra_tween_value_at(null, 0, &v));
    try eq(bad, zyntra_tween_value_at(&tw, 0, null));
    try eq(bad, zyntra_tween_done_at(null, 0, &done));
    try eq(bad, zyntra_tween_done_at(&tw, 0, null));
    var bad_tw = tw;
    bad_tw.duration = 0;
    try eq(bad, zyntra_tween_value_at(&bad_tw, 0, &v));
    bad_tw = tw;
    bad_tw.ease = 9;
    try eq(bad, zyntra_tween_value_at(&bad_tw, 0, &v));

    var tm: ct.ZyntraAnimTimer = undefined;
    try eq(ok, zyntra_anim_timer_init(&tm, 1, false));
    try eq(@as(f32, 1), tm.duration);
    try eq(@as(f32, 0), tm.elapsed);
    try stdt.testing.expect(!tm.looping);
    try eq(ok, zyntra_anim_timer_tick(&tm, 0.5));
    try eq(@as(f32, 0.5), tm.elapsed);
    try eq(ok, zyntra_anim_timer_progress(&tm, &v));
    try eq(@as(f32, 0.5), v);
    try eq(ok, zyntra_anim_timer_done(&tm, &done));
    try stdt.testing.expect(!done);
    try eq(ok, zyntra_anim_timer_tick(&tm, -1));
    try eq(@as(f32, 0.5), tm.elapsed);
    try eq(ok, zyntra_anim_timer_tick(&tm, nan));
    try eq(@as(f32, 0.5), tm.elapsed);
    try eq(ok, zyntra_anim_timer_tick(&tm, 0.7));
    try eq(ok, zyntra_anim_timer_progress(&tm, &v));
    try eq(@as(f32, 1), v);
    try eq(ok, zyntra_anim_timer_done(&tm, &done));
    try stdt.testing.expect(done);
    try eq(ok, zyntra_anim_timer_reset(&tm));
    try eq(@as(f32, 0), tm.elapsed);
    try eq(bad, zyntra_anim_timer_init(null, 1, false));
    try eq(bad, zyntra_anim_timer_init(&tm, 0, false));
    try eq(bad, zyntra_anim_timer_init(&tm, nan, true));
    try eq(bad, zyntra_anim_timer_tick(null, 1));
    try eq(bad, zyntra_anim_timer_reset(null));
    try eq(bad, zyntra_anim_timer_progress(null, &v));
    try eq(bad, zyntra_anim_timer_progress(&tm, null));
    try eq(bad, zyntra_anim_timer_done(null, &done));
    try eq(bad, zyntra_anim_timer_done(&tm, null));
    var bad_tm = tm;
    bad_tm.elapsed = nan;
    try eq(bad, zyntra_anim_timer_tick(&bad_tm, 1));
    try eq(bad, zyntra_anim_timer_progress(&bad_tm, &v));
    try eq(bad, zyntra_anim_timer_done(&bad_tm, &done));
    try eq(bad, zyntra_anim_timer_reset(&bad_tm));

    var loop: ct.ZyntraAnimTimer = undefined;
    try eq(ok, zyntra_anim_timer_init(&loop, 1, true));
    try eq(ok, zyntra_anim_timer_tick(&loop, 2.5));
    try eq(ok, zyntra_anim_timer_progress(&loop, &v));
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), v, 0.0001);
    try eq(ok, zyntra_anim_timer_done(&loop, &done));
    try stdt.testing.expect(!done);

    var col: ct.ZyntraColor = undefined;
    try eq(ok, zyntra_anim_lerp_color(.{ .r = 0, .g = 0, .b = 0, .a = 255 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 0.5, &col));
    try eq(@as(u8, 128), col.r);
    try eq(@as(u8, 128), col.g);
    try eq(@as(u8, 128), col.b);
    try eq(@as(u8, 255), col.a);
    try eq(ok, zyntra_anim_lerp_color(.{ .r = 10, .g = 20, .b = 30, .a = 40 }, .{ .r = 200, .g = 210, .b = 220, .a = 230 }, 0, &col));
    try eq(@as(u8, 10), col.r);
    try eq(@as(u8, 40), col.a);
    try eq(bad, zyntra_anim_lerp_color(.{}, .{}, 0.5, null));
}

test "C-ABI M129: imagem RGBA8 e escala DPI" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{
        .x = 0,
        .y = 0,
        .w = 200,
        .h = 200,
    }, &handle));
    defer zyntra_context_destroy(handle);

    // Imagem 2x2: vermelho, verde / azul, branco.
    const pixels = [16]u8{
        255, 0, 0,   255, 0,   255, 0,   255,
        0,   0, 255, 255, 255, 255, 255, 255,
    };
    const white = ct.ZyntraColor{ .r = 255, .g = 255, .b = 255, .a = 255 };

    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_draw_image(
        handle,
        .{ .x = 0, .y = 0, .w = 2, .h = 2 },
        &pixels,
        2,
        2,
        8,
        white,
    ));
    // Região de origem (sprite).
    try stdt.testing.expectEqual(ok, zyntra_draw_image_region(
        handle,
        .{ .x = 4, .y = 4, .w = 1, .h = 1 },
        &pixels,
        2,
        2,
        8,
        1,
        1,
        1,
        1,
        white,
    ));
    var n_draw: usize = 0;
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 2), n_draw);

    // Inválidos: pixels nulos, dimensões zero, stride curto, região fora.
    try stdt.testing.expectEqual(bad, zyntra_draw_image(handle, .{}, null, 2, 2, 8, white));
    try stdt.testing.expectEqual(bad, zyntra_draw_image(handle, .{}, &pixels, 0, 2, 8, white));
    try stdt.testing.expectEqual(bad, zyntra_draw_image(handle, .{}, &pixels, 2, 2, 4, white));
    try stdt.testing.expectEqual(bad, zyntra_draw_image_region(handle, .{}, &pixels, 2, 2, 8, 2, 0, 1, 1, white));
    try stdt.testing.expectEqual(bad, zyntra_draw_image_region(handle, .{}, &pixels, 2, 2, 8, 0, 0, 0, 1, white));
    // Handle nulo nunca crasha.
    try stdt.testing.expectEqual(bad, zyntra_draw_image(null, .{}, &pixels, 2, 2, 8, white));
    // A contagem não mudou com as rejeições.
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 2), n_draw);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // A imagem chega ao rasterizador (pixel exato).
    var fb: ?*ZyntraFramebuffer = null;
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_create(4, 4, &fb));
    defer zyntra_framebuffer_destroy(fb);
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_draw_image(
        handle,
        .{ .x = 0, .y = 0, .w = 2, .h = 2 },
        &pixels,
        2,
        2,
        8,
        white,
    ));
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_render(fb, handle, null));
    var px: ct.ZyntraColor = .{};
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_pixel(fb, 0, 0, &px));
    try stdt.testing.expectEqual(@as(u8, 255), px.r);
    try stdt.testing.expectEqual(@as(u8, 0), px.g);
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_pixel(fb, 1, 0, &px));
    try stdt.testing.expectEqual(@as(u8, 255), px.g);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Escala DPI: fator, viewport e mouse em pixels de dispositivo.
    try stdt.testing.expectEqual(ok, zyntra_context_set_scale(handle, 2.0));
    var factor: f32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_context_get_scale(handle, &factor));
    try stdt.testing.expectEqual(@as(f32, 2.0), factor);
    try stdt.testing.expectEqual(bad, zyntra_context_set_scale(handle, 0));
    try stdt.testing.expectEqual(bad, zyntra_context_set_scale(handle, std.math.nan(f32)));
    try stdt.testing.expectEqual(bad, zyntra_context_get_scale(handle, null));
    // A escala inválida não alterou a vigente.
    try stdt.testing.expectEqual(ok, zyntra_context_get_scale(handle, &factor));
    try stdt.testing.expectEqual(@as(f32, 2.0), factor);
    try stdt.testing.expectEqual(ok, zyntra_context_set_device_viewport(handle, .{
        .x = 0,
        .y = 0,
        .w = 400,
        .h = 400,
    }));

    // Mouse em pixels de dispositivo vira posição lógica: (100,50) ⇒ (50,25),
    // que cai dentro do botão (0,0,100,30).
    var bstyle: ct.ZyntraButtonStyle = undefined;
    try stdt.testing.expectEqual(ok, zyntra_style_button(0, &bstyle));
    var bres: ct.ZyntraButtonResult = .{};
    const bid = zyntra_id_from_string("m129:btn", 7);
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_context_push_device_mouse_move(handle, .{ .x = 100, .y = 50 }));
    try stdt.testing.expectEqual(ok, zyntra_widget_button(handle, bid, .{
        .x = 0,
        .y = 0,
        .w = 100,
        .h = 30,
    }, &bstyle, &bres));
    try stdt.testing.expect(bres.hovered);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Botão inválido é recusado.
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(bad, zyntra_context_push_device_mouse_button(handle, 9, true, .{}));
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));
}

test "C-ABI M130: composição de IME no campo de texto" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{
        .x = 0,
        .y = 0,
        .w = 400,
        .h = 200,
    }, &handle));
    defer zyntra_context_destroy(handle);

    var pre: [16]u8 = undefined;
    var comp = ct.ZyntraImeComposition{ .buf = &pre, .cap = pre.len };
    try stdt.testing.expectEqual(ok, zyntra_ime_update(&comp, "ni", 2, 2));
    try stdt.testing.expectEqual(@as(usize, 2), comp.len);
    try stdt.testing.expectEqual(@as(usize, 2), comp.cursor);
    try stdt.testing.expect(comp.active);
    try stdt.testing.expectEqual(ok, zyntra_ime_commit(&comp));
    try stdt.testing.expect(comp.committed);
    try stdt.testing.expect(!comp.active);
    try stdt.testing.expectEqual(ok, zyntra_ime_cancel(&comp));
    try stdt.testing.expect(!comp.committed);
    try stdt.testing.expectEqual(@as(usize, 0), comp.len);

    // Inválidos: handle/ponteiro nulo, UTF-8 malformado e buffer pequeno.
    try stdt.testing.expectEqual(bad, zyntra_ime_update(null, "a", 1, 0));
    try stdt.testing.expectEqual(bad, zyntra_ime_commit(null));
    try stdt.testing.expectEqual(bad, zyntra_ime_cancel(null));
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_text, zyntra_ime_update(&comp, "\xff", 1, 0));
    var tiny: [1]u8 = undefined;
    var small = ct.ZyntraImeComposition{ .buf = &tiny, .cap = tiny.len };
    try stdt.testing.expectEqual(bad, zyntra_ime_update(&small, "ab", 2, 0));
    // Composição sem buffer é recusada.
    var nobuf = ct.ZyntraImeComposition{};
    try stdt.testing.expectEqual(bad, zyntra_ime_update(&nobuf, "a", 1, 0));

    // O commit entra no buffer do campo.
    var style: ct.ZyntraTextInputStyle = undefined;
    try stdt.testing.expectEqual(ok, zyntra_style_text_input(0, &style));
    var buf: [32]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    const id = zyntra_id_from_string("m130:ti", 7);
    var res: ct.ZyntraTextInputResult = .{};

    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_context_focus(handle, id));
    try stdt.testing.expectEqual(ok, zyntra_ime_update(&comp, "ni", 2, 2));
    try stdt.testing.expectEqual(ok, zyntra_widget_text_input_ime(
        handle,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 30 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        &comp,
        10.0,
        &style,
        &res,
    ));
    try stdt.testing.expect(res.focused);
    // Em composição, o texto ainda não está no buffer.
    try stdt.testing.expectEqual(@as(usize, 0), len);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_ime_commit(&comp));
    try stdt.testing.expectEqual(ok, zyntra_widget_text_input_ime(
        handle,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 30 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        &comp,
        10.0,
        &style,
        &res,
    ));
    try stdt.testing.expect(res.changed);
    try stdt.testing.expectEqual(@as(usize, 2), len);
    try stdt.testing.expectEqualStrings("ni", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    try stdt.testing.expect(!comp.committed);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Handle nulo nunca crasha.
    try stdt.testing.expectEqual(bad, zyntra_widget_text_input_ime(
        null,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 30 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        &comp,
        10.0,
        &style,
        &res,
    ));
}

test "C-ABI M139: atlas de glifos (fonte real) na fronteira C" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{
        .x = 0,
        .y = 0,
        .w = 200,
        .h = 100,
    }, &handle));
    defer zyntra_context_destroy(handle);

    // Atlas 16x16 com dois glifos 5x7 ('A' avanço 5, 'B' avanço 3).
    var atlas: ?*ZyntraFontAtlas = null;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_create(16, 16, 1, &atlas));
    defer _ = zyntra_font_atlas_destroy(atlas);

    var gx: u32 = 0;
    var gy: u32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_add_glyph(atlas, 'A', 5, 7, 5.0, -7.0, &gx, &gy));
    try stdt.testing.expectEqual(@as(u32, 0), gx);
    try stdt.testing.expectEqual(@as(u32, 0), gy);
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_add_glyph(atlas, 'B', 5, 7, 3.0, -7.0, &gx, &gy));
    try stdt.testing.expectEqual(@as(u32, 6), gx);
    // Codepoint inválido e glifo duplicado são recusados.
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_add_glyph(atlas, 0x110000, 5, 7, 5.0, -7.0, &gx, &gy));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_add_glyph(atlas, 'A', 5, 7, 5.0, -7.0, &gx, &gy));
    // Avanço negativo é recusado.
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_add_glyph(atlas, 'C', 5, 7, -1.0, -7.0, &gx, &gy));
    // Glifo que não cabe no atlas é recusado.
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_add_glyph(atlas, 'C', 32, 32, 5.0, -7.0, &gx, &gy));

    // Imagem 16x16 RGBA8 (o chamador rasteriza os glifos).
    var pixels: [16 * 16 * 4]u8 = undefined;
    for (&pixels, 0..) |*p, i| p.* = @truncate(i);
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_set_image(atlas, &pixels, 16, 16, 16 * 4));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_set_image(atlas, null, 16, 16, 16 * 4));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_set_image(atlas, &pixels, 0, 16, 16 * 4));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_set_image(atlas, &pixels, 16, 16, 4));

    // Medição com os avanços reais: "AB" = 5 + 3 = 8.
    var width: f32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_measure(atlas, "AB", 2, &width));
    try stdt.testing.expectEqual(@as(f32, 8), width);
    var line_h: f32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_line_height(atlas, &line_h));
    try stdt.testing.expectEqual(@as(f32, 7), line_h);
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_measure(atlas, "AB", 2, null));
    try stdt.testing.expectEqual(ct.ZyntraResult.invalid_text, zyntra_font_atlas_measure(atlas, "\xff", 1, &width));

    // Desenho: um comando de run com os dois glifos.
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_draw_run(handle, atlas, "AB", 2, .{ .x = 4, .y = 2 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }));
    var n_draw: usize = 0;
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 1), n_draw);
    // O rótulo com atlas também emite um run.
    try stdt.testing.expectEqual(ok, zyntra_widget_label_atlas(handle, zyntra_id_from_string("m139:label", 10), .{ .x = 0, .y = 20, .w = 100, .h = 12 }, "AB", 2, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, atlas));
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 2), n_draw);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Nulos nunca crasham.
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_create(16, 16, 1, null));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_create(0, 16, 1, &atlas));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_add_glyph(null, 'A', 5, 7, 5.0, -7.0, &gx, &gy));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_measure(null, "A", 1, &width));
    try stdt.testing.expectEqual(bad, zyntra_font_atlas_draw_run(handle, null, "A", 1, .{}, .{}));
    try stdt.testing.expectEqual(bad, zyntra_widget_label_atlas(handle, 0, .{}, "A", 1, .{}, atlas));
}

test "C-ABI M140: alfa global (fade) nos draw commands" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{
        .x = 0,
        .y = 0,
        .w = 8,
        .h = 8,
    }, &handle));
    defer zyntra_context_destroy(handle);

    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_draw_alpha(handle, 0.5));
    try stdt.testing.expectEqual(ok, zyntra_draw_rect_filled(handle, .{ .x = 0, .y = 0, .w = 2, .h = 2 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }));
    try stdt.testing.expectEqual(ok, zyntra_draw_alpha(handle, 1.0));
    try stdt.testing.expectEqual(ok, zyntra_draw_rect_filled(handle, .{ .x = 2, .y = 0, .w = 2, .h = 2 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }));
    var n_draw: usize = 0;
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 4), n_draw); // 2 alfa + 2 retângulos
    // Alfa inválido é recusado.
    try stdt.testing.expectEqual(bad, zyntra_draw_alpha(handle, -0.5));
    try stdt.testing.expectEqual(bad, zyntra_draw_alpha(handle, std.math.nan(f32)));
    try stdt.testing.expectEqual(bad, zyntra_draw_alpha(null, 0.5));
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 4), n_draw);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // No rasterizador: o retângulo atenuado sai cinza 128.
    var fb: ?*ZyntraFramebuffer = null;
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_create(4, 4, &fb));
    defer zyntra_framebuffer_destroy(fb);
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_draw_clear(handle, .{ .r = 0, .g = 0, .b = 0, .a = 255 }));
    try stdt.testing.expectEqual(ok, zyntra_draw_alpha(handle, 0.5));
    try stdt.testing.expectEqual(ok, zyntra_draw_rect_filled(handle, .{ .x = 0, .y = 0, .w = 2, .h = 2 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }));
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_render(fb, handle, null));
    var px: ct.ZyntraColor = .{};
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_pixel(fb, 0, 0, &px));
    try stdt.testing.expectEqual(@as(u8, 128), px.r);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));
}

test "C-ABI M144: fonte de bitmap global no contexto C" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{
        .x = 0,
        .y = 0,
        .w = 64,
        .h = 32,
    }, &handle));
    defer zyntra_context_destroy(handle);

    // Atlas monoespaçado com avanço 6 (= métricas com size 10).
    var atlas: ?*ZyntraFontAtlas = null;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_create(16, 16, 1, &atlas));
    defer _ = zyntra_font_atlas_destroy(atlas);
    var gx: u32 = 0;
    var gy: u32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_add_glyph(atlas, 'A', 5, 7, 6.0, -7.0, &gx, &gy));
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_add_glyph(atlas, 'B', 5, 7, 6.0, -7.0, &gx, &gy));
    var pixels: [16 * 16 * 4]u8 = undefined;
    for (&pixels, 0..) |*p, i| p.* = @truncate(i);
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_set_image(atlas, &pixels, 16, 16, 16 * 4));

    // Tamanho incompatível (avanço 6 ≠ size 16 → 9.6) é recusado.
    try stdt.testing.expectEqual(bad, zyntra_context_set_bitmap_font(handle, atlas, 16.0));
    try stdt.testing.expectEqual(bad, zyntra_context_set_bitmap_font(handle, null, 10.0));
    try stdt.testing.expectEqual(bad, zyntra_context_set_bitmap_font(handle, atlas, 0.0));
    try stdt.testing.expectEqual(bad, zyntra_context_set_bitmap_font(null, atlas, 10.0));

    // Com a fonte registrada, o texto vira blits.
    try stdt.testing.expectEqual(ok, zyntra_context_set_bitmap_font(handle, atlas, 10.0));
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_draw_text(handle, .{ .x = 1, .y = 2 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 10.0, "AB", 2));
    var n_draw: usize = 0;
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 1), n_draw); // um run com os 2 glifos
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Removendo a fonte, o texto volta a ser comando `.text`.
    try stdt.testing.expectEqual(ok, zyntra_context_clear_bitmap_font(handle));
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_draw_text(handle, .{ .x = 1, .y = 2 }, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, 10.0, "AB", 2));
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expectEqual(@as(usize, 1), n_draw);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Nulos nunca crasham.
    try stdt.testing.expectEqual(bad, zyntra_context_clear_bitmap_font(null));
}

test "C-ABI M150: área de texto com atlas (fonte real)" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{
        .x = 0,
        .y = 0,
        .w = 200,
        .h = 100,
    }, &handle));
    defer zyntra_context_destroy(handle);

    // Atlas com 'A' (avanço 5) e 'B' (avanço 3).
    var atlas: ?*ZyntraFontAtlas = null;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_create(16, 16, 1, &atlas));
    defer _ = zyntra_font_atlas_destroy(atlas);
    var gx: u32 = 0;
    var gy: u32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_add_glyph(atlas, 'A', 4, 8, 5.0, -8.0, &gx, &gy));
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_add_glyph(atlas, 'B', 4, 8, 3.0, -8.0, &gx, &gy));
    var pixels: [16 * 16 * 4]u8 = undefined;
    for (&pixels, 0..) |*p, i| p.* = @truncate(i);
    // Glifo 'A' (região 0,0,4,8) pintado de branco.
    for (0..8) |row| {
        for (0..4) |col| {
            const o = (@as(usize, row) * 16 + col) * 4;
            pixels[o] = 255;
            pixels[o + 1] = 255;
            pixels[o + 2] = 255;
            pixels[o + 3] = 255;
        }
    }
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_set_image(atlas, &pixels, 16, 16, 16 * 4));

    var style: ct.ZyntraTextInputStyle = undefined;
    try stdt.testing.expectEqual(ok, zyntra_style_text_input(0, &style));
    var buf: [32]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;
    const id = zyntra_id_from_string("m150:ta", 7);
    var res: ct.ZyntraTextAreaResult = .{};

    // Digita "AB" e confere o buffer + o run de glifos.
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_context_focus(handle, id));
    try stdt.testing.expectEqual(ok, zyntra_context_push_text(handle, 'A'));
    try stdt.testing.expectEqual(ok, zyntra_context_push_text(handle, 'B'));
    try stdt.testing.expectEqual(ok, zyntra_widget_text_area_atlas(
        handle,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 60 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        &scroll,
        atlas,
        &style,
        &res,
    ));
    try stdt.testing.expect(res.focused and res.changed);
    try stdt.testing.expectEqual(@as(usize, 2), len);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    var n_draw: usize = 0;
    try stdt.testing.expectEqual(ok, zyntra_draw_count(handle, &n_draw));
    try stdt.testing.expect(n_draw > 0);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // O texto sai do atlas: o glifo aparece no framebuffer.
    var fb: ?*ZyntraFramebuffer = null;
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_create(16, 16, &fb));
    defer zyntra_framebuffer_destroy(fb);
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_widget_text_area_atlas(
        handle,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 60 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        &scroll,
        atlas,
        &style,
        &res,
    ));
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_render(fb, handle, null));
    var px: ct.ZyntraColor = .{};
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_pixel(fb, 4, 4, &px));
    // O glifo aparece (a cor é a do tema, não branco puro).
    try stdt.testing.expect(px.r > 150);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Contratos: atlas nulo e handle nulo.
    try stdt.testing.expectEqual(bad, zyntra_widget_text_area_atlas(
        handle,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 60 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        &scroll,
        null,
        &style,
        &res,
    ));
    try stdt.testing.expectEqual(bad, zyntra_widget_text_area_atlas(
        null,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 60 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        &scroll,
        atlas,
        &style,
        &res,
    ));
}

test "C-ABI M151: campo de texto com atlas e bloco de texto" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var handle: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{
        .x = 0,
        .y = 0,
        .w = 200,
        .h = 100,
    }, &handle));
    defer zyntra_context_destroy(handle);

    // Atlas com 'A' (avanço 5).
    var atlas: ?*ZyntraFontAtlas = null;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_create(16, 16, 1, &atlas));
    defer _ = zyntra_font_atlas_destroy(atlas);
    var gx: u32 = 0;
    var gy: u32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_add_glyph(atlas, 'A', 4, 8, 5.0, -8.0, &gx, &gy));
    var pixels: [16 * 16 * 4]u8 = undefined;
    for (&pixels, 0..) |*p, i| p.* = @truncate(i);
    try stdt.testing.expectEqual(ok, zyntra_font_atlas_set_image(atlas, &pixels, 16, 16, 16 * 4));

    var style: ct.ZyntraTextInputStyle = undefined;
    try stdt.testing.expectEqual(ok, zyntra_style_text_input(0, &style));

    // Campo de texto com atlas: digita e confere o buffer.
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    const id = zyntra_id_from_string("m151:ti", 7);
    var res: ct.ZyntraTextInputResult = .{};
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_context_focus(handle, id));
    try stdt.testing.expectEqual(ok, zyntra_context_push_text(handle, 'A'));
    try stdt.testing.expectEqual(ok, zyntra_widget_text_input_atlas(
        handle,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 30 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        atlas,
        &style,
        &res,
    ));
    try stdt.testing.expect(res.focused and res.changed);
    try stdt.testing.expectEqual(@as(usize, 1), len);
    try stdt.testing.expectEqual(@as(usize, 1), cursor);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Bloco de texto: quebra e alinha.
    var bres: ct.ZyntraTextBlockResult = .{};
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(handle));
    try stdt.testing.expectEqual(ok, zyntra_widget_text_block(
        handle,
        zyntra_id_from_string("m151:tb", 7),
        .{ .x = 0, .y = 0, .w = 20, .h = 100 },
        "aaa bbb",
        7,
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        10.0,
        1,
        &bres,
    ));
    try stdt.testing.expectEqual(@as(u32, 2), bres.lines);
    try stdt.testing.expect(!bres.truncated);
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(handle));

    // Contratos.
    try stdt.testing.expectEqual(bad, zyntra_widget_text_block(
        handle,
        zyntra_id_from_string("m151:tb", 7),
        .{ .x = 0, .y = 0, .w = 20, .h = 100 },
        "a",
        1,
        .{},
        10.0,
        9, // alinhamento inválido
        &bres,
    ));
    try stdt.testing.expectEqual(bad, zyntra_widget_text_input_atlas(
        handle,
        id,
        .{ .x = 0, .y = 0, .w = 200, .h = 30 },
        &buf,
        buf.len,
        &len,
        &cursor,
        &anchor,
        null,
        &style,
        &res,
    ));
}

test "C-ABI M146: viewport 3D em C (cena, render, picking)" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var vp: ?*ZyntraViewport3D = null;
    try stdt.testing.expectEqual(ok, zyntra_vp3d_create(32, 24, &vp));
    defer _ = zyntra_vp3d_destroy(vp);

    try stdt.testing.expectEqual(ok, zyntra_vp3d_camera(vp, 5.0, 0.7, 0.4, 0, 0, 0));
    try stdt.testing.expectEqual(ok, zyntra_vp3d_add_object(vp, 7, 0, 0, 0, 1.6, 220, 200, 120));
    try stdt.testing.expectEqual(ok, zyntra_vp3d_render(vp));

    // Os pixels estão lá e a cena desenhou algo.
    var px: [*]const u8 = undefined;
    var w: u32 = 0;
    var h: u32 = 0;
    var stride: u32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_vp3d_pixels(vp, &px, &w, &h, &stride));
    try stdt.testing.expectEqual(@as(u32, 32), w);
    try stdt.testing.expectEqual(@as(u32, 24), h);
    try stdt.testing.expectEqual(@as(u32, 32 * 4), stride);
    try stdt.testing.expect(@intFromPtr(px) != 0);

    // O clique no centro acerta o objeto.
    var picked: u32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_vp3d_pick(vp, 16, 12, &picked));
    try stdt.testing.expectEqual(@as(u32, 7), picked);

    // Redimensionar e limpar a cena.
    try stdt.testing.expectEqual(ok, zyntra_vp3d_resize(vp, 16, 16));
    try stdt.testing.expectEqual(ok, zyntra_vp3d_pixels(vp, &px, &w, &h, &stride));
    try stdt.testing.expectEqual(@as(u32, 16), w);
    try stdt.testing.expectEqual(ok, zyntra_vp3d_clear_objects(vp));
    try stdt.testing.expectEqual(ok, zyntra_vp3d_render(vp));
    try stdt.testing.expectEqual(ok, zyntra_vp3d_pick(vp, 8, 8, &picked));
    try stdt.testing.expectEqual(@as(u32, 0), picked);

    // Erros e nulos.
    try stdt.testing.expectEqual(bad, zyntra_vp3d_create(0, 24, &vp));
    try stdt.testing.expectEqual(bad, zyntra_vp3d_camera(null, 5, 0, 0, 0, 0, 0));
    try stdt.testing.expectEqual(bad, zyntra_vp3d_add_object(vp, 1, 0, 0, 0, -1, 0, 0, 0));
    try stdt.testing.expectEqual(bad, zyntra_vp3d_pick(vp, 0, 0, null));
    try stdt.testing.expectEqual(bad, zyntra_vp3d_pixels(vp, &px, &w, &h, null));
}

test "C-ABI M146: modos de ajuste da imagem" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var dest: ct.ZyntraRect = .{};
    var sx: u32 = 0;
    var sy: u32 = 0;
    var sw: u32 = 0;
    var sh: u32 = 0;
    const bounds = ct.ZyntraRect{ .x = 0, .y = 0, .w = 100, .h = 50 };

    // contain: 2x2 numa caixa 100x50 ⇒ 50x50 centralizado.
    try stdt.testing.expectEqual(ok, zyntra_image_fit_rect(bounds, 2, 2, 1, &dest, &sx, &sy, &sw, &sh));
    try stdt.testing.expectEqual(@as(f32, 50), dest.w);
    try stdt.testing.expectEqual(@as(f32, 50), dest.h);
    try stdt.testing.expectEqual(@as(u32, 2), sw);

    // stretch: preenche a caixa.
    try stdt.testing.expectEqual(ok, zyntra_image_fit_rect(bounds, 2, 2, 0, &dest, &sx, &sy, &sw, &sh));
    try stdt.testing.expectEqual(@as(f32, 100), dest.w);

    // cover: a imagem 4x4 numa caixa 100x50 é recortada na ALTURA
    // (a largura cabe inteira).
    try stdt.testing.expectEqual(ok, zyntra_image_fit_rect(bounds, 4, 4, 2, &dest, &sx, &sy, &sw, &sh));
    try stdt.testing.expectEqual(@as(u32, 4), sw);
    try stdt.testing.expectEqual(@as(u32, 2), sh);

    // Modo inválido e dimensões zero.
    try stdt.testing.expectEqual(bad, zyntra_image_fit_rect(bounds, 2, 2, 9, &dest, &sx, &sy, &sw, &sh));
    try stdt.testing.expectEqual(bad, zyntra_image_fit_rect(bounds, 0, 2, 0, &dest, &sx, &sy, &sw, &sh));
    try stdt.testing.expectEqual(bad, zyntra_image_fit_rect(bounds, 2, 2, 0, null, &sx, &sy, &sw, &sh));
}

test "C-ABI M161: caminhos vetoriais (pontos, contornos e path SVG)" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var ctx: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 64, .h = 64 }, &ctx));
    defer _ = zyntra_context_destroy(ctx);

    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(ctx));
    const pts = [_]ct.ZyntraVec2{
        .{ .x = 10, .y = 10 },
        .{ .x = 40, .y = 10 },
        .{ .x = 40, .y = 40 },
        .{ .x = 10, .y = 40 },
    };
    const contours = [_]ct.ZyntraPathContour{.{ .start = 0, .len = 4, .closed = 1 }};
    try stdt.testing.expectEqual(ok, zyntra_draw_path(
        ctx,
        &pts,
        4,
        &contours,
        1,
        ct.ZyntraColor{ .r = 240, .g = 200, .b = 90, .a = 255 },
        0,
        0,
        1,
        0,
    ));
    // Traço do mesmo caminho.
    try stdt.testing.expectEqual(ok, zyntra_draw_path(
        ctx,
        &pts,
        4,
        &contours,
        1,
        ct.ZyntraColor{ .r = 30, .g = 30, .b = 40, .a = 255 },
        2,
        0,
        1,
        1,
    ));
    // Path SVG.
    const svg = "M 10 50 L 25 60 L 40 50 Z";
    try stdt.testing.expectEqual(ok, zyntra_draw_svg_path(
        ctx,
        svg,
        @intCast(svg.len),
        ct.ZyntraColor{ .r = 120, .g = 200, .b = 240, .a = 255 },
        0,
        0,
        1,
        0,
    ));
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(ctx));

    // O framebuffer mostra o caminho.
    var fb: ?*ZyntraFramebuffer = null;
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_create(64, 64, &fb));
    defer _ = zyntra_framebuffer_destroy(fb);
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_render(fb, ctx, null));
    var lit: u32 = 0;
    var y: u32 = 0;
    while (y < 64) : (y += 1) {
        var x: u32 = 0;
        while (x < 64) : (x += 1) {
            var px = ct.ZyntraColor{};
            try stdt.testing.expectEqual(ok, zyntra_framebuffer_pixel(fb, x, y, &px));
            if (px.r > 40 or px.g > 40 or px.b > 40) lit += 1;
        }
    }
    try stdt.testing.expect(lit > 100);

    // Erros.
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(ctx));
    try stdt.testing.expectEqual(bad, zyntra_draw_path(ctx, null, 4, &contours, 1, ct.ZyntraColor{}, 0, 0, 1, 0));
    try stdt.testing.expectEqual(bad, zyntra_draw_path(ctx, &pts, 4, &contours, 1, ct.ZyntraColor{}, 0, 9, 1, 0));
    try stdt.testing.expectEqual(bad, zyntra_draw_path(ctx, &pts, 4, &contours, 1, ct.ZyntraColor{}, -1, 0, 1, 0));
    const bad_contour = [_]ct.ZyntraPathContour{.{ .start = 0, .len = 99, .closed = 1 }};
    try stdt.testing.expectEqual(bad, zyntra_draw_path(ctx, &pts, 4, &bad_contour, 1, ct.ZyntraColor{}, 0, 0, 1, 0));
    try stdt.testing.expectEqual(bad, zyntra_draw_svg_path(ctx, "zzz", 3, ct.ZyntraColor{}, 0, 0, 1, 0));
    try stdt.testing.expectEqual(bad, zyntra_draw_svg_path(ctx, null, 3, ct.ZyntraColor{}, 0, 0, 1, 0));
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(ctx));
}

test "C-ABI M163: ícone SVG (bbox e desenho transformado)" {
    const stdt = @import("std");
    const ok = ct.ZyntraResult.ok;
    const bad = ct.ZyntraResult.invalid_argument;
    var ctx: ?*ZyntraContext = null;
    try stdt.testing.expectEqual(ok, zyntra_context_create(.{ .x = 0, .y = 0, .w = 64, .h = 64 }, &ctx));
    defer _ = zyntra_context_destroy(ctx);
    try stdt.testing.expectEqual(ok, zyntra_context_begin_frame(ctx));

    const svg = "M 0 0 L 10 0 L 10 10 Z";
    var x: f32 = 0;
    var y: f32 = 0;
    var w: f32 = 0;
    var h: f32 = 0;
    try stdt.testing.expectEqual(ok, zyntra_svg_path_bounds(svg, @intCast(svg.len), &x, &y, &w, &h));
    try stdt.testing.expectApproxEqAbs(@as(f32, 10), w, 0.001);
    try stdt.testing.expectApproxEqAbs(@as(f32, 10), h, 0.001);

    // O desenho transformado escala o caminho.
    try stdt.testing.expectEqual(ok, zyntra_draw_svg_path_transformed(
        ctx,
        svg,
        @intCast(svg.len),
        ct.ZyntraColor{ .r = 200, .g = 120, .b = 240, .a = 255 },
        0,
        0,
        1,
        0,
        2.0,
        4.0,
        4.0,
    ));
    try stdt.testing.expectEqual(ok, zyntra_context_end_frame(ctx));

    // O caminho transformado aparece no framebuffer (o triângulo
    // escalado por 2 e deslocado por (4,4)).
    var fb: ?*ZyntraFramebuffer = null;
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_create(64, 64, &fb));
    defer _ = zyntra_framebuffer_destroy(fb);
    try stdt.testing.expectEqual(ok, zyntra_framebuffer_render(fb, ctx, null));
    var lit: u32 = 0;
    var py: u32 = 0;
    while (py < 64) : (py += 1) {
        var px: u32 = 0;
        while (px < 64) : (px += 1) {
            var color = ct.ZyntraColor{};
            try stdt.testing.expectEqual(ok, zyntra_framebuffer_pixel(fb, px, py, &color));
            if (color.r > 40 or color.g > 40 or color.b > 40) lit += 1;
        }
    }
    try stdt.testing.expect(lit > 20);

    // Erros.
    try stdt.testing.expectEqual(bad, zyntra_svg_path_bounds("zzz", 3, &x, &y, &w, &h));
    try stdt.testing.expectEqual(bad, zyntra_svg_path_bounds(svg, @intCast(svg.len), null, &y, &w, &h));
    try stdt.testing.expectEqual(bad, zyntra_draw_svg_path_transformed(
        ctx,
        svg,
        @intCast(svg.len),
        ct.ZyntraColor{},
        0,
        0,
        1,
        0,
        0.0,
        0.0,
        0.0,
    ));
}
