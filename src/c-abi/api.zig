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
//! - Slices/strings Zig NUNCA cruzam a fronteira (M5 só trafega tipos
//!   de tamanho fixo; strings virão com text-runs em M6).
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
    ctx.draw.pushText(
        ctx.allocator,
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
