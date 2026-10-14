//! ZyntraUI — campo de texto (widgets/text_input).
//!
//! Modelo M9 (foco + buffer do chamador, caret no fim):
//! - `buffer`/`len`: buffer UTF-8 de tamanho fixo do CHAMADOR (zero
//!   alocação na lib); `len.*` = bytes usados (0..buffer.len).
//! - Click dentro assume o foco (`focus_owner`); `Escape` ou
//!   `clearFocus` liberam. Só o focado consome `.text`/teclas.
//! - `.text` anexa o codepoint (codificado aqui); backspace (`.key`,
//!   só `pressed`) remove o último codepoint (multibyte-safe).
//! - Buffer cheio: descarta o excedente com `overflowed=true` (sem
//!   truncar no meio de codepoint). `Enter` → `submitted=true`.
//! - Limitações documentadas: sem caret navegável (sempre no fim),
//!   sem seleção, sem Tab-navigation (M10+).
//! Desenho: caixa (destaque quando focado) + texto + caret fina no fim
//! quando focado. `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const input = @import("input.zig");

pub const TextInputResult = struct {
    focused: bool = false,
    changed: bool = false,
    submitted: bool = false,
    overflowed: bool = false,
    len: usize = 0,
};

/// Codifica `codepoint` (0..0x10FFFF, sem surrogates) em UTF-8.
/// Chamar só após validar a faixa; fora dela retorna erro.
fn encodeUtf8(codepoint: u32, out: *[4]u8) !u3 {
    if (codepoint > 0x10FFFF) return error.InvalidUtf8;
    if (codepoint >= 0xD800 and codepoint <= 0xDFFF) return error.InvalidUtf8;
    if (codepoint < 0x80) {
        out[0] = @intCast(codepoint);
        return 1;
    } else if (codepoint < 0x800) {
        out[0] = @intCast(0xC0 | (codepoint >> 6));
        out[1] = @intCast(0x80 | (codepoint & 0x3F));
        return 2;
    } else if (codepoint < 0x10000) {
        out[0] = @intCast(0xE0 | (codepoint >> 12));
        out[1] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        out[2] = @intCast(0x80 | (codepoint & 0x3F));
        return 3;
    } else {
        out[0] = @intCast(0xF0 | (codepoint >> 18));
        out[1] = @intCast(0x80 | ((codepoint >> 12) & 0x3F));
        out[2] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        out[3] = @intCast(0x80 | (codepoint & 0x3F));
        return 4;
    }
}

/// Remove o último codepoint de `buf[0..len]`. Retorna o novo `len`.
fn popCodepoint(buf: []u8, len: usize) usize {
    var i = len;
    if (i == 0) return 0;
    i -= 1;
    // Recua sobre bytes de continuação (10xxxxxx).
    while (i > 0 and buf[i] & 0xC0 == 0x80) : (i -= 1) {}
    return i;
}

pub fn textInput(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextInputResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (len.* > buffer.len) return error.InvalidArgument;

    var res = TextInputResult{ .len = len.* };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());

    // Click dentro assume o foco (independe de captura de press).
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }
    const focused = ctx.hasFocus(id);
    res.focused = focused;

    if (focused) {
        for (ctx.pendingEvents()) |ev| {
            switch (ev) {
                .text => |t| {
                    var enc: [4]u8 = undefined;
                    const n = encodeUtf8(t.codepoint, &enc) catch continue; // defensivo; fila já valida
                    if (len.* + n <= buffer.len) {
                        @memcpy(buffer[len.*..][0..n], enc[0..n]);
                        len.* += n;
                        res.changed = true;
                    } else {
                        res.overflowed = true;
                    }
                },
                .key => |k| {
                    if (!k.pressed) continue;
                    switch (k.key) {
                        .backspace => {
                            const before = len.*;
                            len.* = popCodepoint(buffer, len.*);
                            if (len.* != before) res.changed = true;
                        },
                        .enter => res.submitted = true,
                        .escape => {
                            ctx.focus_owner = null;
                            res.focused = false;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    res.len = len.*;
    if (!ctx.hasFocus(id)) res.focused = false;

    const bg = if (res.focused) style.bg_focus else style.bg;
    const border = if (res.focused) style.border_focus else style.border;
    ctx.draw.rectFilled(ctx.allocator, bounds, bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    if (len.* > 0) {
        ctx.draw.pushText(
            ctx.allocator,
            .{ .x = bounds.x + 4, .y = bounds.y + (bounds.h - font.lineHeight()) / 2 },
            style.text,
            font,
            buffer[0..len.*],
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument, // buffer do chamador corrompido
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }
    if (res.focused) {
        // Caret no fim (largura medida + padding).
        const m = metrics_mod.measure(buffer[0..len.*], font) catch {
            return error.InvalidArgument;
        };
        const cx = bounds.x + 4 + m.width;
        const top = bounds.y + 4;
        const bottom = bounds.y + bounds.h - 4;
        if (bottom > top) {
            ctx.draw.line(
                ctx.allocator,
                .{ .x = cx, .y = top },
                .{ .x = cx, .y = bottom },
                style.caret,
                1.0,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }
    }
    return res;
}

test "text_input foco, digita, backspace multibyte, submit, escape" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti");
    var buf: [16]u8 = undefined;
    var len: usize = 0;

    // Sem foco: teclas ignoradas, 2 draws (caixa).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    const r0 = try textInput(&ctx, id, bounds, &buf, &len, font, style);
    try stdt.testing.expect(!r0.focused and !r0.changed);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    ctx.endFrame();

    // Click foca; digita "A€" (1 + 3 bytes).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 0x20AC } });
    const r1 = try textInput(&ctx, id, bounds, &buf, &len, font, style);
    try stdt.testing.expect(r1.focused and r1.changed);
    try stdt.testing.expectEqual(@as(usize, 4), len);
    try stdt.testing.expectEqualStrings("A€", buf[0..len]);
    ctx.endFrame();

    // Backspace remove o codepoint inteiro (€ = 3 bytes).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const r2 = try textInput(&ctx, id, bounds, &buf, &len, font, style);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqualStrings("A", buf[0..len]);
    // Backspace solto (pressed=false) não repete.
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = false, .modifiers = .{} } });
    const r2b = try textInput(&ctx, id, bounds, &buf, &len, font, style);
    try stdt.testing.expect(!r2b.changed);
    try stdt.testing.expectEqualStrings("A", buf[0..len]);
    ctx.endFrame();

    // Enter submete; Escape desfoca.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r3 = try textInput(&ctx, id, bounds, &buf, &len, font, style);
    try stdt.testing.expect(r3.submitted and r3.focused);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    const r4 = try textInput(&ctx, id, bounds, &buf, &len, font, style);
    try stdt.testing.expect(!r4.focused);
    try stdt.testing.expect(ctx.focus_owner == null);
    ctx.endFrame();

    // Buffer cheio: descarta sem corromper, sinaliza overflow.
    var tiny: [1]u8 = undefined;
    var tlen: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    const r5 = try textInput(&ctx, id, bounds, &tiny, &tlen, font, style);
    try stdt.testing.expect(r5.overflowed);
    try stdt.testing.expectEqualStrings("A", tiny[0..tlen]);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, .null, bounds, &buf, &len, font, style));
    var badlen: usize = 99;
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, id, bounds, &buf, &badlen, font, style));
    ctx.endFrame();
}
