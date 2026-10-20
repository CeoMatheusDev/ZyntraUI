//! ZyntraUI — widget de viewport 3D (viewport3d/viewport).
//!
//! Escopo M156: o WIDGET do viewport 3D. Ele é **desacoplado do
//! rasterizador**: recebe uma IMAGEM pronta (de qualquer produtor — o
//! rasterizador interno, um renderizador externo ou um backend GPU
//! futuro) e a apresenta. O app controla o estado (câmera, foco,
//! arraste); o widget só desenha e interpreta o mouse.
//!
//! Formato: RGBA8 com stride (o mesmo do `SoftwareFramebuffer`).
//! A imagem é **emprestada** e precisa viver durante o frame.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const image_mod = @import("../draw/image.zig");
const input = @import("../widgets/input.zig");

const Color = types.Color;

/// Imagem apresentada no viewport (RGBA8, emprestada).
pub const ImageSource = struct {
    pixels: []const u8 = &.{},
    width: u32 = 0,
    height: u32 = 0,
    /// Bytes por linha (pode ser > width*4).
    stride: u32 = 0,

    pub fn isValid(self: ImageSource) bool {
        if (self.width == 0 or self.height == 0) return false;
        if (self.stride < self.width * 4) return false;
        return self.pixels.len >= @as(usize, self.stride) * self.height;
    }

    /// Vista como `draw.Image` (a referência é emprestada).
    pub fn asImage(self: ImageSource) image_mod.Image {
        return .{
            .width = self.width,
            .height = self.height,
            .stride = self.stride,
            .pixels = self.pixels,
        };
    }
};

/// Estado de interação do viewport (pertence ao app).
pub const State = struct {
    /// Ângulo de órbita em Y (radianos).
    yaw: f32 = 0,
    /// Ângulo de órbita em X (radianos).
    pitch: f32 = 0,
    /// Distância da câmera (zoom).
    distance: f32 = 5,
    /// O viewport tem o foco do teclado.
    focused: bool = false,
    /// Arraste em andamento.
    dragging: bool = false,
    /// Posição do mouse no último frame (para o delta do arraste).
    last_mouse: types.Vec2 = .{},

    pub fn isValid(self: State) bool {
        if (!std.math.isFinite(self.yaw) or !std.math.isFinite(self.pitch)) return false;
        if (!std.math.isFinite(self.distance) or self.distance <= 0) return false;
        return true;
    }
};

/// Opções do widget.
pub const Options = struct {
    /// Cor de fundo (sob a imagem).
    background: Color = .{ .r = 18, .g = 20, .b = 26, .a = 255 },
    /// Cor da borda.
    border: Color = .{ .r = 70, .g = 74, .b = 86, .a = 255 },
    /// Espessura da borda (0 = sem borda).
    border_width: f32 = 1,
    /// Sensibilidade da órbita (radianos por pixel).
    orbit_sensitivity: f32 = 0.01,
    /// Fator do zoom por evento de roda (0.1 = 10% por degrau).
    zoom_step: f32 = 0.1,
    /// Limite do pitch da órbita (±89°).
    pitch_limit: f32 = 89.0 * (std.math.pi * (1.0 / 180.0)),
};

/// Resultado do widget no frame.
pub const Result = struct {
    focused: bool = false,
    dragging: bool = false,
    /// O zoom foi alterado neste frame.
    zoomed: bool = false,
    /// A órbita foi alterada neste frame.
    orbited: bool = false,
};

/// Widget do viewport 3D: apresenta `source` em `bounds` e trata
/// mouse (arraste = órbita), roda (zoom) e foco.
pub fn viewport3d(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    source: ImageSource,
    state: *State,
    opts: Options,
) context_mod.ContextError!Result {
    if (id.isNull()) return error.InvalidArgument;
    if (!state.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h) or
        bounds.w <= 0 or bounds.h <= 0)
    {
        return error.InvalidArgument;
    }
    if (!std.math.isFinite(opts.orbit_sensitivity) or
        !std.math.isFinite(opts.zoom_step) or !std.math.isFinite(opts.border_width) or
        opts.border_width < 0)
    {
        return error.InvalidArgument;
    }

    var res = Result{ .focused = state.focused, .dragging = state.dragging };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());

    // Clique dentro: foco + início do arraste.
    if (fm.pressedInside(bounds)) {
        state.focused = true;
        ctx.focus_owner = id;
        state.dragging = true;
        if (fm.pressed_pos) |p| state.last_mouse = p;
        // Captura o arraste (o release vai para o dono da captura).
        if (ctx.press_owner == null) ctx.press_owner = id;
    }
    // Arraste: a órbita segue o mouse.
    if (state.dragging and ctx.press_owner == id and ctx.mouse_down_left) {
        if (ctx.mouse_pos) |p| {
            const dx = p.x - state.last_mouse.x;
            const dy = p.y - state.last_mouse.y;
            if (dx != 0 or dy != 0) {
                state.yaw += dx * opts.orbit_sensitivity;
                state.pitch = std.math.clamp(
                    state.pitch + dy * opts.orbit_sensitivity,
                    -opts.pitch_limit,
                    opts.pitch_limit,
                );
                state.last_mouse = p;
                res.orbited = true;
            }
        }
    }
    if (fm.released_pos != null) {
        state.dragging = false;
        if (ctx.press_owner == id) ctx.press_owner = null;
    }
    // Roda: zoom (a distância encolhe/encolhe).
    var wheel_dy: f32 = 0;
    for (ctx.pendingEvents()) |ev| {
        if (ev == .mouse_wheel) wheel_dy += ev.mouse_wheel.dy;
    }
    if (wheel_dy != 0 and opts.zoom_step > 0) {
        // Roda para cima (dy < 0) aproxima; para baixo, afasta.
        const factor = 1.0 + opts.zoom_step * wheel_dy;
        if (factor > 0.01) {
            state.distance = std.math.clamp(state.distance * factor, 0.01, 1.0e6);
            res.zoomed = true;
        }
    }
    res.focused = state.focused;
    res.dragging = state.dragging;

    // Desenho: fundo, imagem e borda.
    ctx.draw.rectFilled(ctx.allocator, bounds, opts.background) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    if (source.isValid()) {
        ctx.draw.imageRegion(
            ctx.allocator,
            bounds,
            source.asImage(),
            image_mod.Region.init(0, 0, source.width, source.height),
            types.Color.rgb(255, 255, 255),
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    if (opts.border_width > 0) {
        ctx.draw.rectOutline(ctx.allocator, bounds, opts.border, opts.border_width) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    // O widget participa do dirty rect (a imagem muda a cada frame).
    ctx.mark_hot(id, bounds, true) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArgument => return error.InvalidArgument,
        error.InvalidCommand => return error.InvalidCommand,
        error.InvalidEvent => return error.InvalidArgument,
    };
    return res;
}

test "viewport3d: apresenta a imagem e trata o arraste" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:vp3d");

    var pixels: [16 * 16 * 4]u8 = undefined;
    for (&pixels, 0..) |*p, i| p.* = @truncate(i);
    const source = ImageSource{ .pixels = &pixels, .width = 16, .height = 16, .stride = 16 * 4 };
    var state = State{};

    ctx.beginFrame();
    const r = try viewport3d(&ctx, id, types.Rect.init(0, 0, 32, 32), source, &state, .{});
    try stdt.testing.expect(!r.focused);
    // Fundo + imagem + borda = 3 comandos.
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len);
    ctx.endFrame();

    // Press dentro: foco e arraste.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(10, 10),
    } });
    const r2 = try viewport3d(&ctx, id, types.Rect.init(0, 0, 32, 32), source, &state, .{});
    try stdt.testing.expect(r2.focused and r2.dragging);
    try stdt.testing.expect(state.focused);
    ctx.endFrame();

    // Arrasto: a órbita muda.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 12) } });
    const r3 = try viewport3d(&ctx, id, types.Rect.init(0, 0, 32, 32), source, &state, .{});
    try stdt.testing.expect(r3.orbited);
    try stdt.testing.expect(state.yaw != 0);
    ctx.endFrame();

    // Roda: o zoom muda.
    const d0 = state.distance;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1, .pos = types.Vec2.init(10, 10) } });
    const r4 = try viewport3d(&ctx, id, types.Rect.init(0, 0, 32, 32), source, &state, .{});
    try stdt.testing.expect(r4.zoomed);
    try stdt.testing.expect(state.distance < d0);
    ctx.endFrame();

    // Contratos.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, viewport3d(&ctx, .null, types.Rect.init(0, 0, 32, 32), source, &state, .{}));
    try stdt.testing.expectError(error.InvalidArgument, viewport3d(&ctx, id, types.Rect.init(0, 0, 0, 32), source, &state, .{}));
    var bad_state = State{ .distance = -1 };
    try stdt.testing.expectError(error.InvalidArgument, viewport3d(&ctx, id, types.Rect.init(0, 0, 32, 32), source, &bad_state, .{}));
    ctx.endFrame();
}

test "viewport3d: imagem inválida desenha só o fundo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:vp3d2");
    var state = State{};

    ctx.beginFrame();
    _ = try viewport3d(&ctx, id, types.Rect.init(0, 0, 32, 32), .{}, &state, .{});
    // Fundo + borda (sem imagem).
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    ctx.endFrame();
}
