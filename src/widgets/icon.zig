//! ZyntraUI — widget de ícone vetorial (widgets/icon).
//!
//! Escopo M162: desenha um ÍCONE (caminho vetorial) dentro de um rect,
//! com modo de ajuste e cor — sem imagem, sem fonte e sem dependência.
//! - `drawIcon`: desenha um caminho JÁ ACHATADO dentro do rect (o
//!   chamador tem a geometria).
//! - `Cache`: guarda o caminho achatado de um path SVG, indexado pelo
//!   texto (o app possui o cache; nada é analisado a cada frame).
//!
//! O ícone não é interativo: não registra foco nem estado quente. Quem
//! muda o ícone é responsável por marcar a região suja
//! (`ctx.mark_dirty`).
//!
//! Ownership: o `Cache` é do app (ele aloca e libera os caminhos); o
//! caminho devolvido por `Cache.get` é EMPRESTADO (válido até a próxima
//! modificação do cache).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const path_mod = @import("../draw/path.zig");
const svg_mod = @import("../draw/svg.zig");
const image_widget = @import("image.zig");

/// Modo de ajuste do ícone no rect (o mesmo da imagem).
pub const Fit = image_widget.Fit;

/// Opções do widget de ícone.
pub const IconOptions = struct {
    /// Modo de ajuste dentro do rect.
    fit: Fit = .contain,
    /// Cor do ícone (o caminho é desenhado com esta cor).
    color: types.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    /// Espessura do traço (0 = preenchimento; > 0 = contorno).
    thickness: f32 = 0,
};

/// Transformação uniforme aplicada ao caminho (escala + deslocamento).
pub const Transform = struct {
    /// Fator de escala (1 = sem escala).
    factor: f32 = 1,
    /// Deslocamento em X (pixels lógicos).
    dx: f32 = 0,
    /// Deslocamento em Y (pixels lógicos).
    dy: f32 = 0,
};

/// Calcula a transformação que leva a caixa do caminho para dentro de
/// `bounds` conforme o modo de ajuste.
///
/// `contain`/`cover` preservam a proporção; `stretch` preenche o rect
/// (a escala é a média das duas direções — o caminho fica "esticado" de
/// forma uniforme, sem distorcer as curvas); `none` mantém o tamanho.
pub fn fitTransform(bounds: types.Rect, path_bounds: types.Rect, fit: Fit) Transform {
    const bw = @max(0, bounds.w);
    const bh = @max(0, bounds.h);
    const pw = path_bounds.w;
    const ph = path_bounds.h;
    if (pw <= 0 or ph <= 0 or bw <= 0 or bh <= 0) return .{};
    const sx = bw / pw;
    const sy = bh / ph;
    const factor: f32 = switch (fit) {
        .stretch => @min(sx, sy),
        .contain => @min(sx, sy),
        .cover => @max(sx, sy),
        .none => 1,
    };
    const w = pw * factor;
    const h = ph * factor;
    return .{
        .factor = factor,
        .dx = bounds.x + (bw - w) / 2 - path_bounds.x * factor,
        .dy = bounds.y + (bh - h) / 2 - path_bounds.y * factor,
    };
}

/// Desenha um ícone (caminho vetorial) dentro de `bounds`.
///
/// `flat` é o caminho achatado (ver `draw.path.flatten`): os pontos são
/// transformados (ajuste) e copiados para o comando de desenho.
pub fn drawIcon(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    flat: path_mod.Flat,
    opts: IconOptions,
) context_mod.ContextError!void {
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w < 0 or bounds.h < 0) return error.InvalidArgument;
    if (!std.math.isFinite(opts.thickness) or opts.thickness < 0) return error.InvalidArgument;
    if (flat.points.len == 0 or flat.contours.len == 0) return;

    const t = fitTransform(bounds, flat.bounds(), opts.fit);
    if (t.factor <= 0) return;
    ctx.draw.pathTransformed(
        ctx.allocator,
        flat,
        opts.color,
        opts.thickness,
        .nonzero,
        .round,
        .butt,
        t.factor,
        t.dx,
        t.dy,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

/// Cache de ícones: o path SVG (texto) vira caminho achatado uma vez.
///
/// O cache é do APP (ele o aloca e libera). O caminho devolvido por
/// `get` é emprestado: válido até a próxima chamada que modifique o
/// cache (ou o `deinit`).
pub const Cache = struct {
    gpa: std.mem.Allocator,
    entries: std.StringHashMapUnmanaged(Entry) = .empty,
    /// Quantidade de entradas (para diagnóstico).
    count: usize = 0,

    const Entry = struct {
        /// Segmentos do path (o resultado da análise).
        segments: []path_mod.Segment = &.{},
        /// Pontos achatados.
        points: []types.Vec2 = &.{},
        /// Contornos achatados.
        contours: []path_mod.ContourRange = &.{},
        /// O caminho achatado (aponta para `points`/`contours`).
        flat: path_mod.Flat = .{},
    };

    /// Cria um cache vazio.
    pub fn init(gpa: std.mem.Allocator) Cache {
        return .{ .gpa = gpa };
    }

    /// Libera todos os caminhos.
    pub fn deinit(self: *Cache) void {
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            self.gpa.free(kv.key_ptr.*);
            self.gpa.free(kv.value_ptr.segments);
            self.gpa.free(kv.value_ptr.points);
            self.gpa.free(kv.value_ptr.contours);
        }
        self.entries.deinit(self.gpa);
        self.count = 0;
    }

    /// O caminho achatado do path SVG `svg` (ou null se não couber).
    ///
    /// O texto é a chave: o mesmo SVG devolve sempre o mesmo caminho
    /// (sem reanálise). O caminho é EMPRESTADO.
    pub fn get(self: *Cache, svg: []const u8) !?path_mod.Flat {
        if (self.entries.get(svg)) |entry| return entry.flat;

        // Análise: os segmentos são uma estimativa (2 por caractere).
        const seg_cap = @max(16, svg.len * 2);
        const segments = try self.gpa.alloc(path_mod.Segment, seg_cap);
        errdefer self.gpa.free(segments);
        const builder = svg_mod.parsePath(svg, segments) catch {
            self.gpa.free(segments);
            return null;
        };

        // Achatamento: os buffers crescem até caber.
        var point_cap: usize = 64;
        var range_cap: usize = 16;
        var points = try self.gpa.alloc(types.Vec2, point_cap);
        errdefer self.gpa.free(points);
        var contours = try self.gpa.alloc(path_mod.ContourRange, range_cap);
        errdefer self.gpa.free(contours);
        var flat = path_mod.Flat{};
        while (true) {
            const res = path_mod.flatten(builder.segments(), 0.25, points, contours);
            if (res) |ok| {
                flat = ok;
                break;
            } else |err| switch (err) {
                error.InvalidArgument => return null,
                error.NoSpaceLeft => {
                    if (point_cap > 1 << 20 or range_cap > 1 << 16) return null;
                    point_cap *= 2;
                    range_cap *= 2;
                    const new_points = try self.gpa.alloc(types.Vec2, point_cap);
                    self.gpa.free(points);
                    points = new_points;
                    const new_contours = try self.gpa.alloc(path_mod.ContourRange, range_cap);
                    self.gpa.free(contours);
                    contours = new_contours;
                },
            }
        }

        // A chave é uma cópia do texto (o app pode liberar o original).
        const key = try self.gpa.dupe(u8, svg);
        errdefer self.gpa.free(key);
        try self.entries.put(self.gpa, key, .{
            .segments = segments,
            .points = points,
            .contours = contours,
            .flat = flat,
        });
        self.count = self.entries.count();
        return flat;
    }
};

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test "icon: o ajuste contain preserva a proporção" {
    const bb = types.Rect.init(0, 0, 10, 20);
    const t = fitTransform(types.Rect.init(0, 0, 100, 100), bb, .contain);
    // contain usa a MENOR escala (100/20 = 5) ⇒ o ícone fica 50x100,
    // centralizado no rect (x = 25).
    try std.testing.expectApproxEqAbs(@as(f32, 5), t.factor, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 25), t.dx, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.dy, 0.001);
}

test "icon: o ajuste none mantém o tamanho" {
    const bb = types.Rect.init(0, 0, 10, 20);
    const t = fitTransform(types.Rect.init(0, 0, 100, 100), bb, .none);
    try std.testing.expectApproxEqAbs(@as(f32, 1), t.factor, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 45), t.dx, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), t.dy, 0.001);
}

test "icon: o ajuste cover usa a maior escala" {
    const bb = types.Rect.init(0, 0, 10, 20);
    const t = fitTransform(types.Rect.init(0, 0, 100, 100), bb, .cover);
    try std.testing.expectApproxEqAbs(@as(f32, 10), t.factor, 0.001);
}

test "icon: o cache analisa o path SVG uma vez" {
    const gpa = std.testing.allocator;
    var cache = Cache.init(gpa);
    defer cache.deinit();

    const flat = (try cache.get("M 0 0 L 10 0 L 10 10 Z")).?;
    try std.testing.expectEqual(@as(usize, 1), flat.contourCount());
    try std.testing.expectEqual(@as(usize, 3), flat.pointCount());
    try std.testing.expectApproxEqAbs(@as(f32, 10), flat.bounds().w, 0.001);

    // A segunda vez devolve o mesmo caminho (sem reanálise).
    const again = (try cache.get("M 0 0 L 10 0 L 10 10 Z")).?;
    try std.testing.expectEqual(flat.points.ptr, again.points.ptr);
    try std.testing.expectEqual(@as(usize, 1), cache.count);

    // Um SVG diferente entra como outra entrada.
    const other = (try cache.get("M 0 0 L 5 5")).?;
    try std.testing.expectEqual(@as(usize, 2), cache.count);
    try std.testing.expect(other.points.ptr != flat.points.ptr);
}

test "icon: o cache rejeita um path inválido" {
    const gpa = std.testing.allocator;
    var cache = Cache.init(gpa);
    defer cache.deinit();
    try std.testing.expect((try cache.get("zzz")) == null);
}

test "icon: o desenho entra na lista de comandos" {
    const gpa = std.testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{ .viewport = types.Rect.init(0, 0, 64, 64) });
    defer ctx.deinit();
    ctx.beginFrame();

    var cache = Cache.init(gpa);
    defer cache.deinit();
    const flat = (try cache.get("M 0 0 L 10 0 L 10 10 Z")).?;

    try drawIcon(&ctx, types.Rect.init(0, 0, 32, 32), flat, .{ .fit = .contain });
    const cmds = ctx.drawCommands();
    try std.testing.expectEqual(@as(usize, 1), cmds.len);
    try std.testing.expect(cmds[0] == .path);
    // O caminho foi transformado (o destino é 32x32 ⇒ escala 3.2).
    const p = cmds[0].path;
    try std.testing.expect(p.point_count == 3);
    try std.testing.expectApproxEqAbs(@as(f32, 32), p.bounds.w, 0.01);
    ctx.endFrame();
}
