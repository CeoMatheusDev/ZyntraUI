//! ZyntraUI — leitura de mouse para widgets (widgets/input).
//! Helper interno (não é API pública estável ainda): extrai a última
//! posição conhecida e se houve pressão esquerda dentro de `bounds`.
//! Sem alocação; apenas itera `events` do frame.

const types = @import("../core/types.zig");
const event_mod = @import("../event/event.zig");

pub const MouseScan = struct {
    pos: ?types.Vec2 = null,
    hovered: bool = false,
    pressed: bool = false,

    pub fn scan(events: []const event_mod.Event, bounds: types.Rect) MouseScan {
        var out = MouseScan{};
        for (events) |ev| {
            switch (ev) {
                .mouse_move => |m| {
                    out.pos = m.pos;
                },
                .mouse_button => |b| {
                    out.pos = b.pos;
                    if (b.pressed and b.button == .left and bounds.contains(b.pos)) {
                        out.pressed = true;
                    }
                },
                .mouse_wheel => |w| {
                    out.pos = w.pos;
                },
                else => {},
            }
        }
        if (out.pos) |p| out.hovered = bounds.contains(p);
        return out;
    }
};

/// Eventos de botão esquerdo do frame, sem âncora espacial.
/// Widgets combinam com `Context.mouse_pos` (retido) e `press_owner`
/// (captura) para release-to-activate.
pub const FrameMouse = struct {
    pressed_pos: ?types.Vec2 = null,
    released_pos: ?types.Vec2 = null,

    pub fn scan(events: []const event_mod.Event) FrameMouse {
        var out = FrameMouse{};
        for (events) |ev| {
            if (ev != .mouse_button) continue;
            const b = ev.mouse_button;
            if (b.button != .left) continue;
            if (b.pressed) {
                out.pressed_pos = b.pos;
            } else {
                out.released_pos = b.pos;
            }
        }
        return out;
    }

    pub fn pressedInside(self: FrameMouse, bounds: types.Rect) bool {
        const p = self.pressed_pos orelse return false;
        return bounds.contains(p);
    }
};

test "MouseScan detecta hover e press-inside" {
    const stdt = @import("std");
    const bounds = types.Rect.init(10, 10, 100, 40);
    const evs = [_]event_mod.Event{
        .{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } },
        .{ .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 20) } },
    };
    const s = MouseScan.scan(&evs, bounds);
    try stdt.testing.expect(s.hovered);
    try stdt.testing.expect(s.pressed);

    const outside = [_]event_mod.Event{
        .{ .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) } },
    };
    const s2 = MouseScan.scan(&outside, bounds);
    try stdt.testing.expect(!s2.hovered);
    try stdt.testing.expect(!s2.pressed);
}

test "FrameMouse separa press e release" {
    const stdt = @import("std");
    const bounds = types.Rect.init(10, 10, 100, 40);
    const evs = [_]event_mod.Event{
        .{ .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 20) } },
        .{ .mouse_button = .{ .button = .right, .pressed = true, .pos = types.Vec2.init(20, 20) } },
        .{ .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(500, 500) } },
    };
    const fm = FrameMouse.scan(&evs);
    try stdt.testing.expect(fm.pressedInside(bounds));
    try stdt.testing.expect(fm.released_pos != null);
    const none = FrameMouse.scan(&.{ .quit, .quit });
    try stdt.testing.expect(none.pressed_pos == null);
    try stdt.testing.expect(none.released_pos == null);
    try stdt.testing.expect(!none.pressedInside(bounds));
}
