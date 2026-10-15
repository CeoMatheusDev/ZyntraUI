//! ZyntraUI — campo de texto (widgets/text_input).
//!
//! Modelo M10 (foco + buffer do chamador, caret navegável)://! - `buffer`/`len`/`cursor`: buffer UTF-8 de tamanho fixo do CHAMADOR
//!   (zero alocação na lib); `len.*` = bytes usados, `cursor.*` = offset
//!   de byte do caret (sempre fronteira UTF-8, 0..len).
//! - Click dentro assume o foco (`focus_owner`); `Escape` ou
//!   `clearFocus` liberam. Só o focado consome `.text`/teclas.
//! - `.text` insere no cursor (memmove do sufixo); setas movem por
//!   codepoint; `Home`/`End` saltam; backspace apaga antes, `Delete`
//!   apaga no cursor. Buffer cheio: descarta com `overflowed=true`.
//!   `Enter` → `submitted=true`; `Tab`/`Shift+Tab` circulam o foco
//!   entre focáveis registrados (aplicado no próximo `beginFrame`).
//! - Limitações documentadas: sem seleção (M12+).
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
    cursor: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextInputResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (len.* > buffer.len or cursor.* > len.*) return error.InvalidArgument;

    var res = TextInputResult{ .len = len.* };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());

    // Todo text-input é focável (registrado mesmo sem foco, para o Tab).
    try ctx.registerFocusable(id);

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
                        // Insere no cursor (desloca o sufixo para a direita).
                        std.mem.copyBackwards(u8, buffer[cursor.* + n .. len.* + n], buffer[cursor.*..len.*]);
                        @memcpy(buffer[cursor.*..][0..n], enc[0..n]);
                        cursor.* += n;
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
                            if (cursor.* > 0) {
                                const at = popCodepoint(buffer, cursor.*);
                                const n = cursor.* - at;
                                std.mem.copyForwards(u8, buffer[at .. len.* - n], buffer[cursor.*..len.*]);
                                cursor.* = at;
                                len.* -= n;
                                res.changed = true;
                            }
                        },
                        .delete => {
                            if (cursor.* < len.*) {
                                const d = metrics_mod.decodeOne(buffer[cursor.*..len.*]) catch {
                                    return error.InvalidArgument; // buffer do chamador corrompido
                                };
                                std.mem.copyForwards(u8, buffer[cursor.* .. len.* - d.len], buffer[cursor.* + d.len .. len.*]);
                                len.* -= d.len;
                                res.changed = true;
                            }
                        },
                        .left => {
                            if (cursor.* > 0) cursor.* = popCodepoint(buffer, cursor.*);
                        },
                        .right => {
                            if (cursor.* < len.*) {
                                const d = metrics_mod.decodeOne(buffer[cursor.*..len.*]) catch {
                                    return error.InvalidArgument;
                                };
                                cursor.* += d.len;
                            }
                        },
                        .home => cursor.* = 0,
                        .end => cursor.* = len.*,
                        .enter => res.submitted = true,
                        .tab => {
                            // Tab nunca vira texto: agenda avanço sobre o
                            // registro completo (aplicado no beginFrame).
                            ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next);
                        },
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
        // Caret na posição do cursor (mede o prefixo + padding).
        const m = metrics_mod.measure(buffer[0..cursor.*], font) catch {
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
    var cursor: usize = 0;

    // Sem foco: teclas ignoradas, 2 draws (caixa).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    const r0 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
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
    const r1 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(r1.focused and r1.changed);
    try stdt.testing.expectEqual(@as(usize, 4), len);
    try stdt.testing.expectEqualStrings("A€", buf[0..len]);
    ctx.endFrame();

    // Backspace remove o codepoint inteiro (€ = 3 bytes).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const r2 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqualStrings("A", buf[0..len]);
    // Backspace solto (pressed=false) não repete.
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = false, .modifiers = .{} } });
    const r2b = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!r2b.changed);
    try stdt.testing.expectEqualStrings("A", buf[0..len]);
    ctx.endFrame();

    // Enter submete; Escape desfoca.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r3 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(r3.submitted and r3.focused);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    const r4 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!r4.focused);
    try stdt.testing.expect(ctx.focus_owner == null);
    ctx.endFrame();

    // Buffer cheio: descarta sem corromper, sinaliza overflow.
    var tiny: [1]u8 = undefined;
    var tlen: usize = 0;
    var tcursor: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    const r5 = try textInput(&ctx, id, bounds, &tiny, &tlen, &tcursor, font, style);
    try stdt.testing.expect(r5.overflowed);
    try stdt.testing.expectEqualStrings("A", tiny[0..tlen]);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, .null, bounds, &buf, &len, &cursor, font, style));
    var badlen: usize = 99;
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, id, bounds, &buf, &badlen, &cursor, font, style));
    var badcur: usize = 50;
    var oklen: usize = 1;
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, id, bounds, &buf, &oklen, &badcur, font, style));
    ctx.endFrame();
}

test "text_input Tab circula foco entre campos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const b1 = types.Rect.init(0, 0, 200, 30);
    const b2 = types.Rect.init(0, 40, 200, 30);
    const id1 = id_mod.Id.fromString("test:ti1");
    const id2 = id_mod.Id.fromString("test:ti2");
    var buf1: [8]u8 = undefined;
    var len1: usize = 0;
    var cur1: usize = 0;
    var buf2: [8]u8 = undefined;
    var len2: usize = 0;
    var cur2: usize = 0;

    // F1: click no campo 1 foca; ambos registrados.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    const f1a = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    _ = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(f1a.focused);
    try stdt.testing.expect(ctx.hasFocus(id1));
    ctx.endFrame();

    // F2: Tab no campo 1 agenda; aplicado no F3 → campo 2.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    _ = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(ctx.hasFocus(id1)); // ainda 1 neste frame
    ctx.endFrame();
    ctx.beginFrame();
    const f3a = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    const f3b = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(!f3a.focused and f3b.focused);
    // Tab nunca virou texto em nenhum campo:
    try stdt.testing.expectEqual(@as(usize, 0), len1);
    try stdt.testing.expectEqual(@as(usize, 0), len2);
    ctx.endFrame();

    // F4: Shift+Tab no campo 2 volta ao 1 (aplicado no F5).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{ .shift = true } } });
    _ = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    _ = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    const f5a = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    const f5b = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(f5a.focused and !f5b.focused);
    ctx.endFrame();
}

test "text_input caret navega, insere no meio e deleta" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti-nav");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;

    // Foca e digita "AC" (cursor acompanha o fim).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'C' } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqualStrings("AC", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    ctx.endFrame();

    // Left + "B" insere no meio: "ABC".
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqualStrings("ABC", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    ctx.endFrame();

    // Left no início não sai de 0; right avança por codepoint.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), cursor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqual(@as(usize, 3), cursor);
    ctx.endFrame();

    // Delete no meio remove "B": "AC". Backspace no início é no-op.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqual(@as(usize, 1), cursor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .delete, .pressed = true, .modifiers = .{} } });
    const rd = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(rd.changed);
    try stdt.testing.expectEqualStrings("AC", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 1), cursor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const rb = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!rb.changed);
    try stdt.testing.expectEqualStrings("AC", buf[0..len]);
    ctx.endFrame();
}
