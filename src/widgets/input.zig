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
