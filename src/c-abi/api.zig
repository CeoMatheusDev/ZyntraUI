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
