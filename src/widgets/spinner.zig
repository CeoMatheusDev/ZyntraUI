//! ZyntraUI — spinner de carregamento (widgets/spinner).
//!
//! Modelo M64 (display puro, sem interação, sem estado retido):
//! complementa `progress` (determinado) com um indicador **indeterminado**.
//! - `spinner(ctx, center, t, style)`: `t` = tempo decorrido em segundos
//!   (fornecido pelo chamador, ex.: `AnimTimer.elapsed`). O quadro é uma
//!   função pura de `t` — sem relógio interno, determinístico e testável.
//! - Desenho: `style.dots` círculos em anel ao redor de `center`; o
//!   "cabeça" (`head`) avança um passo a cada `1/speed` s no sentido
//!   horário; os demais usam `track`.
//! - `SpinnerStyle` + `Theme.spinnerStyle()`.
//! Contratos: `center` finito; `t` finito; estilo válido.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const style_mod = @import("../style/style.zig");

/// Passos do giro por segundo (um "tick" por passo).
pub const spinner_speed: f32 = 8.0;

/// Índice da cabeça para `dots` posições no tempo `t` (segundos).
/// Aceita `t` finito (inclusive negativo) e extremos; sempre retorna
/// `[0, dots)`. Usa precisão f64 no módulo para não estourar `f32`
/// (t grande × velocidade → `inf`, e `inf - inf` seria `NaN`).
pub fn spinnerHeadIndex(dots: u8, t: f32) usize {
    if (dots == 0) return 0;
    const n: f64 = @floatFromInt(dots);
    const step = @floor(@as(f64, t) * @as(f64, spinner_speed));
    const wrapped = step - n * @floor(step / n); // [0, n) para qualquer sinal
    return @intFromFloat(wrapped);
}

/// Centro do dot `i` em um anel de `dots` posições; `i = 0` no topo.
pub fn spinnerDotCenter(center: types.Vec2, i: usize, dots: u8, radius: f32) types.Vec2 {
    const n: f32 = @floatFromInt(dots);
    const ang = std.math.tau * @as(f32, @floatFromInt(i)) / n - std.math.pi / 2.0;
    return types.Vec2.init(center.x + radius * @cos(ang), center.y + radius * @sin(ang));
}

pub fn spinner(
    ctx: *context_mod.Context,
    center: types.Vec2,
    t: f32,
    style: style_mod.SpinnerStyle,
) context_mod.ContextError!void {
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(center.x) or !std.math.isFinite(center.y)) return error.InvalidArgument;
    if (!std.math.isFinite(t)) return error.InvalidArgument;

    // O quadro muda a cada instante ⇒ a área precisa ser repintada
    // (o spinner não tem id: ele marca o próprio retângulo).
    const radius = style.radius + style.dot_radius;
    ctx.mark_dirty(types.Rect.init(
        center.x - radius,
        center.y - radius,
        radius * 2,
        radius * 2,
    ));

    // Acessibilidade (M164): indicador de progresso indeterminado.
    try ctx.pushA11y(.{
        .role = .progressbar,
        .bounds = types.Rect.init(
            center.x - radius,
            center.y - radius,
            radius * 2,
            radius * 2,
        ),
    });

    const head = spinnerHeadIndex(style.dots, t);
    var i: usize = 0;
    while (i < @as(usize, style.dots)) : (i += 1) {
        const p = spinnerDotCenter(center, i, style.dots, style.radius);
        const color = if (i == head) style.head else style.track;
        ctx.draw.circleFilled(ctx.allocator, p, style.dot_radius, color) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
}

test "spinner desenha dots, gira e valida" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().spinnerStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const center = types.Vec2.init(50, 50);

    // t=0 → cabeça no índice 0; um comando por dot; 1º dot no topo.
    ctx.beginFrame();
    try spinner(&ctx, center, 0, style);
    try stdt.testing.expectEqual(@as(usize, style.dots), ctx.drawCommands().len);
    const first = ctx.drawCommands()[0].circle_filled;
    try stdt.testing.expectApproxEqAbs(@as(f32, 50), first.center.x, 0.001);
    try stdt.testing.expectApproxEqAbs(50 - style.radius, first.center.y, 0.001);
    try stdt.testing.expectEqual(@as(f32, style.dot_radius), first.radius);
    ctx.endFrame();

    // Cabeça avança com o tempo e faz wrap.
    try stdt.testing.expectEqual(@as(usize, 0), spinnerHeadIndex(style.dots, 0));
    try stdt.testing.expectEqual(@as(usize, 1), spinnerHeadIndex(style.dots, 1.0 / spinner_speed));
    try stdt.testing.expectEqual(@as(usize, 0), spinnerHeadIndex(style.dots, @as(f32, @floatFromInt(style.dots)) / spinner_speed));
    // Valores extremos de `t` (finitos) não estouram nem retornam fora da faixa.
    const big = std.math.floatMax(f32);
    try stdt.testing.expect(spinnerHeadIndex(style.dots, big) < style.dots);
    try stdt.testing.expect(spinnerHeadIndex(style.dots, -big) < style.dots);

    // Entradas inválidas.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, spinner(&ctx, types.Vec2.init(std.math.nan(f32), 0), 0, style));
    try stdt.testing.expectError(error.InvalidArgument, spinner(&ctx, center, std.math.inf(f32), style));
    const bad_style = style_mod.SpinnerStyle{
        .track = .{},
        .head = .{},
        .dots = 1,
        .radius = 10,
        .dot_radius = 2,
    };
    try stdt.testing.expectError(error.InvalidArgument, spinner(&ctx, center, 0, bad_style));
    ctx.endFrame();
}
