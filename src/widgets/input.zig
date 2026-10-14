//! ZyntraUI — leitura de mouse para widgets (widgets/input).
//! Helper interno (não é API pública): extrai press/release do botão
//! esquerdo no frame. Widgets combinam com `Context.mouse_pos` (retido)
//! e `press_owner` (captura) para release-to-activate.
//! Sem alocação; apenas itera `events` do frame.

const types = @import("../core/types.zig");
const event_mod = @import("../event/event.zig");

/// Eventos de botão esquerdo do frame, sem âncora espacial.
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
