//! ZyntraUI — widget de imagem (widgets/image).
//!
//! Escopo M127: desenha uma imagem RGBA8 (ver `draw/image`) dentro de
//! um rect, com modo de ajuste e tint. Sem estado, sem alocação e sem
//! interação (a imagem é do chamador; a ela é emprestada).
//! - `Fit.stretch`: preenche o rect (ignora a proporção).
//! - `Fit.contain`: escala para CABER dentro do rect (proporção intacta,
//!   centralizado).
//! - `Fit.cover`: escala para COBRIR o rect (proporção intacta, o
//!   excedente é recortado na origem).
//! - `Fit.none`: 1:1 (tamanho original, centralizado).
//! Ownership: os pixels da imagem são emprestados e precisam viver até
//! o backend consumir o frame.
//! Validação: bounds finitos, imagem válida e tint válido.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const image_mod = @import("../draw/image.zig");

/// Modo de ajuste da imagem no rect.
pub const Fit = enum {
    /// Preenche o rect, distorcendo.
    stretch,
    /// Cabe dentro do rect, centralizado, sem distorcer.
    contain,
    /// Cobre o rect, centralizado, recortando o excedente.
    cover,
    /// Tamanho original (1:1), centralizado.
    none,
};

/// Opções do widget de imagem.
pub const ImageOptions = struct {
    fit: Fit = .contain,
    /// Modulação RGBA (branco opaco = identidade).
    tint: types.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

/// Resultado do ajuste: rect de destino (em pixels lógicos) e região de
/// origem (em pixels da imagem).
pub const Placement = struct {
    dest: types.Rect = .{},
    src: image_mod.Region = .{},
};

/// Calcula onde a imagem cai dentro de `bounds` para o modo `fit`.
/// `img` precisa ser válida (`Image.isValid`).
pub fn fitRect(bounds: types.Rect, img: image_mod.Image, fit: Fit) Placement {
    return fitRectSize(bounds, img.width, img.height, fit);
}

/// Como `fitRect`, mas só das DIMENSÕES da imagem (sem precisar dos
/// pixels) — é o que a fronteira C usa.
pub fn fitRectSize(bounds: types.Rect, img_width: u32, img_height: u32, fit: Fit) Placement {
    const iw: f32 = @floatFromInt(img_width);
    const ih: f32 = @floatFromInt(img_height);
    const full = image_mod.Region.init(0, 0, img_width, img_height);
    const bw = @max(0, bounds.w);
    const bh = @max(0, bounds.h);
    if (iw <= 0 or ih <= 0) return .{ .dest = bounds, .src = full };

    switch (fit) {
        .stretch => return .{ .dest = bounds, .src = full },
        .none => {
            const w = @min(iw, bw);
            const h = @min(ih, bh);
            return .{
                .dest = .{
                    .x = bounds.x + (bw - w) / 2,
                    .y = bounds.y + (bh - h) / 2,
                    .w = w,
                    .h = h,
                },
                .src = full,
            };
        },
        .contain => {
            const scale = @min(bw / iw, bh / ih);
            const w = iw * scale;
            const h = ih * scale;
            return .{
                .dest = .{
                    .x = bounds.x + (bw - w) / 2,
                    .y = bounds.y + (bh - h) / 2,
                    .w = w,
                    .h = h,
                },
                .src = full,
            };
        },
        .cover => {
            // Escala até cobrir e recorta o excedente na ORIGEM (pixels
            // inteiros) — o destino é o rect inteiro.
            const scale = @max(bw / iw, bh / ih);
            const src_w = @max(1, @as(u32, @intFromFloat(@floor(bw / scale))));
            const src_h = @max(1, @as(u32, @intFromFloat(@floor(bh / scale))));
            const src_x = @min(img_width - src_w, (img_width - src_w) / 2);
            const src_y = @min(img_height - src_h, (img_height - src_h) / 2);
            return .{
                .dest = bounds,
                .src = image_mod.Region.init(src_x, src_y, src_w, src_h),
            };
        },
    }
}

/// Desenha a imagem em `bounds` conforme `opts`.
///
/// Não é interativo: não registra foco nem estado quente. Quem muda a
/// imagem é responsável por marcar a região suja (`ctx.mark_dirty`).
pub fn image(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    img: image_mod.Image,
    opts: ImageOptions,
) context_mod.ContextError!void {
    if (!img.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w < 0 or bounds.h < 0) return error.InvalidArgument;

    const place = fitRect(bounds, img, opts.fit);
    if (place.dest.w <= 0 or place.dest.h <= 0) return; // nada a desenhar
    ctx.draw.imageRegion(ctx.allocator, place.dest, img, place.src, opts.tint) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "fitRect cobre os quatro modos de ajuste" {
    const stdt = @import("std");
    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try image_mod.Image.init(2, 2, &bytes);
    const bounds = types.Rect.init(0, 0, 100, 50);

    // stretch: preenche o rect.
    const stretch = fitRect(bounds, img, .stretch);
    try stdt.testing.expectEqual(bounds, stretch.dest);
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 2, 2), stretch.src);

    // contain: 100x50 cabendo 2x2 ⇒ escala 25 ⇒ 50x50, centralizado.
    const contain = fitRect(bounds, img, .contain);
    try stdt.testing.expectEqual(types.Rect.init(25, 0, 50, 50), contain.dest);
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 2, 2), contain.src);

    // none: 1:1 ⇒ 2x2, centralizado.
    const none = fitRect(bounds, img, .none);
    try stdt.testing.expectEqual(types.Rect.init(49, 24, 2, 2), none.dest);

    // cover: escala 50 ⇒ 100x100; recorta a altura (50/50 = 1 linha).
    const cover = fitRect(bounds, img, .cover);
    try stdt.testing.expectEqual(bounds, cover.dest);
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 2, 1), cover.src);
}

test "fitRect lida com imagens maiores que o rect" {
    const stdt = @import("std");
    var bytes: [64]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try image_mod.Image.init(4, 4, &bytes);
    const bounds = types.Rect.init(0, 0, 20, 10);

    // contain: escala 2.5 ⇒ 10x10 (menor que o rect), centralizado.
    const contain = fitRect(bounds, img, .contain);
    try stdt.testing.expectEqual(types.Rect.init(5, 0, 10, 10), contain.dest);

    // none: 4x4 (cabe), centralizado.
    const none = fitRect(bounds, img, .none);
    try stdt.testing.expectEqual(types.Rect.init(8, 3, 4, 4), none.dest);

    // cover: escala 5 ⇒ 20x20; recorta 2 linhas de altura.
    const cover = fitRect(bounds, img, .cover);
    try stdt.testing.expectEqual(image_mod.Region.init(0, 1, 4, 2), cover.src);
}

test "widget de imagem enfileira o comando com tint" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try image_mod.Image.init(2, 2, &bytes);

    ctx.beginFrame();
    try image(&ctx, types.Rect.init(0, 0, 100, 50), img, .{
        .fit = .stretch,
        .tint = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    });
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    const cmd = ctx.drawCommands()[0];
    try stdt.testing.expect(cmd == .image);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 100, 50), cmd.image.rect);
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 2, 2), cmd.image.src);
    try stdt.testing.expectEqual(
        types.Color{ .r = 255, .g = 0, .b = 0, .a = 255 },
        cmd.image.tint,
    );
    ctx.endFrame();

    // Imagem inválida e bounds não-finitos são recusados.
    var bad: [8]u8 = undefined;
    const bad_img = image_mod.Image.initStrided(2, 2, 8, &bad);
    try stdt.testing.expectError(error.InvalidImage, bad_img);
    try stdt.testing.expectError(error.InvalidArgument, image(
        &ctx,
        types.Rect.init(0, 0, 10, 10),
        image_mod.Image{ .width = 0, .height = 0, .stride = 0, .pixels = &.{} },
        .{},
    ));
    try stdt.testing.expectError(error.InvalidArgument, image(
        &ctx,
        types.Rect.init(0, 0, std.math.nan(f32), 10),
        img,
        .{},
    ));
}
