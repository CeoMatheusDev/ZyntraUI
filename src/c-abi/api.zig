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

pub export fn zyntra_version_major() callconv(.c) u32 {
    return types_mod.version_major;
}

pub export fn zyntra_version_minor() callconv(.c) u32 {
    return types_mod.version_minor;
}

pub export fn zyntra_version_patch() callconv(.c) u32 {
    return types_mod.version_patch;
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

pub export fn zyntra_draw_rect_filled(
    handle: ?*ZyntraContext,
    rect: ct.ZyntraRect,
    color: ct.ZyntraColor,
) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const ctx = toCtx(h);
    ctx.draw.rectFilled(ctx.allocator, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h }, .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    }) catch |err| switch (err) {
        error.OutOfMemory => return .out_of_memory,
        error.InvalidCommand => return .invalid_command,
    };
    return .ok;
}

pub export fn zyntra_draw_count(handle: ?*ZyntraContext, out_len: ?*usize) callconv(.c) ct.ZyntraResult {
    const h = checkHandle(handle) catch return .invalid_argument;
    const out = out_len orelse return .invalid_argument;
    out.* = toCtx(h).drawCommands().len;
    return .ok;
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
