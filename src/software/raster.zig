//! ZyntraUI — backend de referência em software (software/raster).
//!
//! Rasterizador CPU puro para VERIFICAÇÃO do contrato de desenho
//! (pixels reais, asserts exatos) e saída sem GPU. NÃO é um renderer
//! de produção: sem rasterização de glifos (runs de texto são pulados
//! E contados). Blending source-over com arredondamento (opaco e
//! transparente têm caminho rápido/idêntico ao legado).
//! - `SoftwareFramebuffer`: RGBA8 row-major, 1px = 1px lógico, origem
//!   no canto superior-esquerdo, amostra no centro do pixel.
//! - `render`: aplica `clip`, viewport e culling; retorna estatísticas.
//! - `encodePpm`: PPM binário (P6, RGB) em buffer do chamador, sem deps.
//! Ownership: fb detém `pixels` (alocador do chamador); comandos são
//! apenas lidos. Tudo determinístico e sem estado global.

const std = @import("std");
const types = @import("../core/types.zig");
const commands = @import("../draw/commands.zig");
const renderer = @import("../draw/renderer.zig");

pub const max_dimension: u32 = 8192;

/// RGBA8 row-major. Conteúdo inicial INDEFINIDO (lixo do alocador —
/// Debug preenche com 0xAA, Release zera): limpe com `clear` ou cubra
/// tudo antes de ler pixels.
pub const SoftwareFramebuffer = struct {
    w: u32,
    h: u32,
    pixels: []u8, // len == w*h*4, RGBA por pixel

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, w: u32, h: u32) !Self {
        if (w == 0 or h == 0 or w > max_dimension or h > max_dimension) {
            return error.InvalidArgument;
        }
        const n: u64 = @as(u64, w) * h * 4;
        const pixels = try gpa.alloc(u8, @intCast(n));
        return .{ .w = w, .h = h, .pixels = pixels };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        gpa.free(self.pixels);
        self.pixels = &.{};
        self.w = 0;
        self.h = 0;
    }

    pub fn get(self: *const Self, x: u32, y: u32) [4]u8 {
        std.debug.assert(x < self.w and y < self.h);
        const i = (@as(usize, y) * self.w + x) * 4;
        return self.pixels[i..][0..4].*;
    }

    fn set(self: *Self, x: u32, y: u32, c: types.Color) void {
        const i = (@as(usize, y) * self.w + x) * 4;
        if (c.a == 255) {
            // Caminho rápido: opaco sobrescreve (idêntico ao legado).
            self.pixels[i] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = c.a;
            return;
        }
        if (c.a == 0) return; // transparente: no-op
        const d0: u32 = self.pixels[i];
        const d1: u32 = self.pixels[i + 1];
        const d2: u32 = self.pixels[i + 2];
        const d3: u32 = self.pixels[i + 3];
        const sa: u32 = c.a;
        const ia: u32 = 255 - sa;
        // Source-over com arredondamento (+127 antes de /255).
        self.pixels[i] = @intCast((@as(u32, c.r) * sa + d0 * ia + 127) / 255);
        self.pixels[i + 1] = @intCast((@as(u32, c.g) * sa + d1 * ia + 127) / 255);
        self.pixels[i + 2] = @intCast((@as(u32, c.b) * sa + d2 * ia + 127) / 255);
        self.pixels[i + 3] = @intCast((sa * 255 + d3 * ia + 127) / 255);
    }

    pub fn clear(self: *Self, c: types.Color) void {
        var i: usize = 0;
        while (i < self.pixels.len) : (i += 4) {
            self.pixels[i] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = c.a;
        }
    }

    /// Preenche a interseção de `r` com `clip` (quando presente).
    /// Coordenadas: pixel (i,j) cobre [i,i+1)×[j,j+1).
    /// Entradas não-finitas saturam em no-op (conversão float→int
    /// travaria; `render` já rejeita, isto protege chamadas diretas).
    pub fn fillRect(self: *Self, r: types.Rect, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h)) return;
        var x0 = @as(i64, @intFromFloat(@floor(r.x)));
        var y0 = @as(i64, @intFromFloat(@floor(r.y)));
        var x1 = @as(i64, @intFromFloat(@ceil(r.x + r.w)));
        var y1 = @as(i64, @intFromFloat(@ceil(r.y + r.h)));
        x0 = @max(x0, 0);
        y0 = @max(y0, 0);
        x1 = @min(x1, self.w);
        y1 = @min(y1, self.h);
        if (clip) |cp| {
            x0 = @max(x0, @as(i64, @intFromFloat(@floor(cp.x))));
            y0 = @max(y0, @as(i64, @intFromFloat(@floor(cp.y))));
            x1 = @min(x1, @as(i64, @intFromFloat(@ceil(cp.x + cp.w))));
            y1 = @min(y1, @as(i64, @intFromFloat(@ceil(cp.y + cp.h))));
        }
        if (c.a == 0) return; // transparente: no-op
        if (c.a == 255) {
            // Caminho rápido opaco (sequencial puro, vetorizável).
            var y = y0;
            while (y < y1) : (y += 1) {
                var o = @as(usize, @intCast(y)) * @as(usize, self.w) * 4 + @as(usize, @intCast(x0)) * 4;
                var x = x0;
                while (x < x1) : (x += 1) {
                    self.pixels[o] = c.r;
                    self.pixels[o + 1] = c.g;
                    self.pixels[o + 2] = c.b;
                    self.pixels[o + 3] = c.a;
                    o += 4;
                }
            }
            return;
        }
        // Blending com base içada (mesma matemática de set()).
        const sa: u32 = c.a;
        const ia: u32 = 255 - sa;
        var y = y0;
        while (y < y1) : (y += 1) {
            var o = @as(usize, @intCast(y)) * @as(usize, self.w) * 4 + @as(usize, @intCast(x0)) * 4;
            var x = x0;
            while (x < x1) : (x += 1) {
                self.pixels[o] = @intCast((@as(u32, c.r) * sa + @as(u32, self.pixels[o]) * ia + 127) / 255);
                self.pixels[o + 1] = @intCast((@as(u32, c.g) * sa + @as(u32, self.pixels[o + 1]) * ia + 127) / 255);
                self.pixels[o + 2] = @intCast((@as(u32, c.b) * sa + @as(u32, self.pixels[o + 2]) * ia + 127) / 255);
                self.pixels[o + 3] = @intCast((sa * 255 + @as(u32, self.pixels[o + 3]) * ia + 127) / 255);
                o += 4;
            }
        }
    }

    fn distPointSeg(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) f32 {
        const dx = bx - ax;
        const dy = by - ay;
        const l2 = dx * dx + dy * dy;
        if (l2 == 0) {
            const ex = px - ax;
            const ey = py - ay;
            return @sqrt(ex * ex + ey * ey);
        }
        var t = ((px - ax) * dx + (py - ay) * dy) / l2;
        t = std.math.clamp(t, 0, 1);
        const ex = px - (ax + t * dx);
        const ey = py - (ay + t * dy);
        return @sqrt(ex * ex + ey * ey);
    }

    fn inClip(x: i64, y: i64, clip: ?types.Rect) bool {
        const cp = clip orelse return true;
        const fx: f32 = @floatFromInt(x);
        const fy: f32 = @floatFromInt(y);
        return fx + 1 > cp.x and fx < cp.x + cp.w and fy + 1 > cp.y and fy < cp.y + cp.h;
    }

    pub fn strokeLine(self: *Self, p0: types.Vec2, p1: types.Vec2, thickness: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(p0.x) or !std.math.isFinite(p0.y) or
            !std.math.isFinite(p1.x) or !std.math.isFinite(p1.y) or
            !std.math.isFinite(thickness) or thickness <= 0) return;
        const r = thickness / 2;
        const x0f = @min(p0.x, p1.x) - r - 1;
        const y0f = @min(p0.y, p1.y) - r - 1;
        const x1f = @max(p0.x, p1.x) + r + 1;
        const y1f = @max(p0.y, p1.y) + r + 1;
        var y = @max(0, @as(i64, @intFromFloat(@floor(y0f))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(y1f))));
        while (y < y_end) : (y += 1) {
            var x = @max(0, @as(i64, @intFromFloat(@floor(x0f))));
            const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(x1f))));
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const cx: f32 = @floatFromInt(x);
                const cy: f32 = @floatFromInt(y);
                if (distPointSeg(cx + 0.5, cy + 0.5, p0.x, p0.y, p1.x, p1.y) <= r) {
                    self.set(@intCast(x), @intCast(y), c);
                }
            }
        }
    }

    pub fn fillCircle(self: *Self, center: types.Vec2, radius: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(center.x) or !std.math.isFinite(center.y) or
            !std.math.isFinite(radius) or radius < 0) return;
        var y = @max(0, @as(i64, @intFromFloat(@floor(center.y - radius))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(center.y + radius))));
        while (y < y_end) : (y += 1) {
            var x = @max(0, @as(i64, @intFromFloat(@floor(center.x - radius))));
            const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(center.x + radius))));
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const cx: f32 = @floatFromInt(x);
                const cy: f32 = @floatFromInt(y);
                const dx = (cx + 0.5) - center.x;
                const dy = (cy + 0.5) - center.y;
                if (@sqrt(dx * dx + dy * dy) <= radius) {
                    self.set(@intCast(x), @intCast(y), c);
                }
            }
        }
    }

    /// Cobertura (0..1) do ponto (`px`,`py`) num retângulo de cantos
    /// arredondados: SDF clássico; `< 0` dentro, `0` na borda. A
    /// conversão em cobertura usa meia-largura de 1px (borda AA).
    fn roundRectCoverage(px: f32, py: f32, r: types.Rect, rad: f32) f32 {
        const hw = r.w / 2;
        const hh = r.h / 2;
        const qx = @abs(px - (r.x + hw)) - (hw - rad);
        const qy = @abs(py - (r.y + hh)) - (hh - rad);
        const ox = @max(qx, 0);
        const oy = @max(qy, 0);
        const d = @sqrt(ox * ox + oy * oy) + @min(@max(qx, qy), 0) - rad;
        return std.math.clamp(0.5 - d, 0, 1);
    }

    /// Retângulo de cantos arredondados via SDF: amostra o centro de
    /// cada pixel e mistura com o alfa ponderado pela cobertura (bordas
    /// anti-serrilhadas). `radius` clampado a `min(w,h)/2`; entradas
    /// não-finitas saturam em no-op.
    pub fn fillRoundRect(self: *Self, r: types.Rect, radius: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(radius) or radius < 0) return;
        if (r.w <= 0 or r.h <= 0 or c.a == 0) return;
        const rad = @min(radius, @min(r.w, r.h) / 2);
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(r.x))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(r.y))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(r.x + r.w))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(r.y + r.h))));
        const base_a: f32 = @floatFromInt(c.a);
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const cov = roundRectCoverage(fx + 0.5, fy + 0.5, r, rad);
                if (cov <= 0) continue;
                const fa: f32 = @round(cov * base_a);
                const ea: u8 = @intFromFloat(@min(fa, 255.0));
                if (ea == 0) continue;
                self.set(@intCast(x), @intCast(y), .{ .r = c.r, .g = c.g, .b = c.b, .a = ea });
            }
        }
    }

    /// Interpola um canal (0..255) por `tq` em 0..255 (arredondado).
    fn lerpChannel(a: u8, b: u8, tq: u32) u8 {
        return @intCast((@as(u32, a) * (255 - tq) + @as(u32, b) * tq + 127) / 255);
    }

    /// Gradiente linear dentro de `r`: `color0` em `from`, `color1` em
    /// `to`; o pixel é projetado no eixo e `t` é clampado a [0,1]
    /// (quantizado em 0..255 para resultados determinísticos). `from ==
    /// to` degenera em `color0` sólido; entradas não-finitas saturam em
    /// no-op.
    pub fn fillGradient(
        self: *Self,
        r: types.Rect,
        from: types.Vec2,
        to: types.Vec2,
        color0: types.Color,
        color1: types.Color,
        clip: ?types.Rect,
    ) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(from.x) or !std.math.isFinite(from.y) or
            !std.math.isFinite(to.x) or !std.math.isFinite(to.y)) return;
        if (r.w <= 0 or r.h <= 0) return;
        const dx = to.x - from.x;
        const dy = to.y - from.y;
        const den = dx * dx + dy * dy;
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(r.x))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(r.y))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(r.x + r.w))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(r.y + r.h))));
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const t: f32 = if (den <= 0) 0 else std.math.clamp(
                    ((fx + 0.5 - from.x) * dx + (fy + 0.5 - from.y) * dy) / den,
                    0,
                    1,
                );
                const tq: u32 = @intFromFloat(@round(t * 255.0));
                const c = types.Color{
                    .r = lerpChannel(color0.r, color1.r, tq),
                    .g = lerpChannel(color0.g, color1.g, tq),
                    .b = lerpChannel(color0.b, color1.b, tq),
                    .a = lerpChannel(color0.a, color1.a, tq),
                };
                self.set(@intCast(x), @intCast(y), c);
            }
        }
    }

    pub fn strokeRect(self: *Self, r: types.Rect, thickness: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(thickness) or thickness <= 0) return;
        const t = @max(1.0, thickness);
        // Barras superior/inferior (largura total) + laterais (entre elas).
        self.fillRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = @min(t, r.h) }, clip, c);
        self.fillRect(.{ .x = r.x, .y = r.y + r.h - @min(t, r.h), .w = r.w, .h = @min(t, r.h) }, clip, c);
        const mid_y = r.y + @min(t, r.h);
        const mid_h = @max(0, r.h - 2 * @min(t, r.h));
        if (mid_h > 0) {
            self.fillRect(.{ .x = r.x, .y = mid_y, .w = @min(t, r.w), .h = mid_h }, clip, c);
            self.fillRect(.{ .x = r.x + r.w - @min(t, r.w), .y = mid_y, .w = @min(t, r.w), .h = mid_h }, clip, c);
        }
    }
};

/// Estatísticas de uma submissão ao rasterizador.
pub const SoftwareStats = extern struct {
    submitted: u32 = 0,
    drawn: u32 = 0,
    culled: u32 = 0,
    skipped_text: u32 = 0,
};

/// Visibilidade via bounds canônicos (`draw/renderer.commandBounds`):
/// fonte única de verdade p/ culling (antes duplicada com fórmula
/// divergente p/ linhas). `null` = global (clear/clip-nulo).
fn boundsVisible(cmd: commands.DrawCommand, viewport: types.Rect) bool {
    const b = renderer.commandBounds(cmd) orelse return true;
    return overlaps(b, viewport);
}

fn overlaps(a: types.Rect, b: types.Rect) bool {
    if (a.w <= 0 or a.h <= 0 or b.w <= 0 or b.h <= 0) return false;
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h;
}

/// Executa comandos no framebuffer (1px = 1px lógico). Texto é pulado
/// E contado (sem fonte, sem glifos). Comandos inválidos retornam erro
/// sem efeito parcial garantido além do já desenhado.
pub fn render(fb: *SoftwareFramebuffer, cmds: []const commands.DrawCommand, viewport: types.Rect) !SoftwareStats {
    var out = SoftwareStats{ .submitted = @intCast(cmds.len) };
    var clip: ?types.Rect = null;
    const vp = types.Rect{
        .x = @max(0, viewport.x),
        .y = @max(0, viewport.y),
        .w = @max(0, @min(viewport.w, @as(f32, @floatFromInt(fb.w)))),
        .h = @max(0, @min(viewport.h, @as(f32, @floatFromInt(fb.h)))),
    };
    for (cmds) |cmd| {
        if (!cmd.isValid()) return error.InvalidCommand;
        switch (cmd) {
            .clear => |c| {
                fb.clear(c.color);
                out.drawn += 1;
            },
            .clip => |c| {
                clip = if (c.null_rect) null else c.rect;
                out.drawn += 1;
            },
            .text => {
                out.skipped_text += 1;
            },
            else => {
                if (!boundsVisible(cmd, viewport)) {
                    out.culled += 1;
                    continue;
                }
                switch (cmd) {
                    .rect_filled => |c| fb.fillRect(intersectClip(c.rect, clip, vp), null, c.color),
                    .rect_outline => |c| fb.strokeRect(c.rect, c.thickness, mergeClip(clip, vp), c.color),
                    .line => |c| fb.strokeLine(c.p0, c.p1, c.thickness, mergeClip(clip, vp), c.color),
                    .circle_filled => |c| fb.fillCircle(c.center, c.radius, mergeClip(clip, vp), c.color),
                    .rect_rounded => |c| fb.fillRoundRect(c.rect, c.radius, mergeClip(clip, vp), c.color),
                    .rect_gradient => |c| fb.fillGradient(c.rect, c.p0, c.p1, c.color0, c.color1, mergeClip(clip, vp)),
                    else => unreachable,
                }
                out.drawn += 1;
            },
        }
    }
    return out;
}

/// Interseção de dois rects (vazio se disjuntos).
fn intersect(a: types.Rect, b: types.Rect) types.Rect {
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    return .{
        .x = x,
        .y = y,
        .w = @max(0, @min(a.x + a.w, b.x + b.w) - x),
        .h = @max(0, @min(a.y + a.h, b.y + b.h) - y),
    };
}

fn intersectClip(r: types.Rect, clip: ?types.Rect, vp: types.Rect) types.Rect {
    var out = intersect(r, vp);
    if (clip) |cp| out = intersect(out, cp);
    return out;
}

/// Combina clip de usuário + viewport num único rect-ou-nulo.
fn mergeClip(clip: ?types.Rect, vp: types.Rect) ?types.Rect {
    const cp = clip orelse return vp;
    return intersect(cp, vp);
}

/// PPM binário (P6) em `out`. Retorna bytes usados; `NoSpaceLeft` se
/// o buffer for curto. Alfa descartado (sem blending — documentado).
pub fn encodePpm(fb: *const SoftwareFramebuffer, out: []u8) !usize {
    const head = try std.fmt.bufPrint(out, "P6\n{d} {d}\n255\n", .{ fb.w, fb.h });
    const need = head.len + @as(usize, fb.w) * fb.h * 3;
    if (out.len < need) return error.NoSpaceLeft;
    var o = head.len;
    var i: usize = 0;
    while (i < fb.pixels.len) : (i += 4) {
        out[o] = fb.pixels[i];
        out[o + 1] = fb.pixels[i + 1];
        out[o + 2] = fb.pixels[i + 2];
        o += 3;
    }
    return o;
}

test "raster rect + clear pixel-exato" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 8, 8);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(7, 7));

    fb.fillRect(types.Rect.init(2, 2, 2, 2), null, types.Color.rgb(255, 0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(2, 2));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(3, 3));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 1));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(4, 4));

    // Clip restringe; fora da área nada muda.
    fb.fillRect(types.Rect.init(0, 0, 8, 8), types.Rect.init(0, 0, 1, 1), types.Color.rgb(0, 255, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 255, 0, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 0));

    try stdt.testing.expectError(error.InvalidArgument, SoftwareFramebuffer.init(gpa, 0, 8));
    try stdt.testing.expectError(error.InvalidArgument, SoftwareFramebuffer.init(gpa, 99999, 8));
}

test "raster linha diagonal e círculo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 10, 10);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));

    fb.strokeLine(.{ .x = 0, .y = 0 }, .{ .x = 3, .y = 3 }, 1.0, null, types.Color.rgb(0, 0, 255));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 255, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 255, 255 }, fb.get(2, 2));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 0)); // vizinho fora do raio 0.5
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(0, 1));

    fb.fillCircle(.{ .x = 7, .y = 7 }, 2.0, null, types.Color.rgb(255, 255, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 0, 255 }, fb.get(7, 7));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 0, 255 }, fb.get(8, 7)); // dist 1.5 <= 2
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(9, 9)); // dist ~3.5 > 2
}

test "render pipeline: clear, clip, cull, texto pulado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 100, 100);
    defer fb.deinit(gpa);
    const vp = types.Rect.init(0, 0, 100, 100);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(10, 10, 10) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(10, 10, 20, 20), .color = types.Color.rgb(255, 0, 0) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(500, 500, 20, 20), .color = types.Color.rgb(0, 255, 0) } },
        .{ .clip = .{ .rect = types.Rect.init(0, 0, 15, 15), .null_rect = false } },
        .{ .rect_filled = .{ .rect = types.Rect.init(10, 10, 20, 20), .color = types.Color.rgb(0, 0, 255) } },
        .{ .text = .{ .pos = .{ .x = 0, .y = 0 }, .color = types.Color.rgb(255, 255, 255), .size = 16, .width = 10, .start = 0, .len = 0 } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 6), s.submitted);
    try stdt.testing.expectEqual(@as(u32, 4), s.drawn); // clear + rect + clip + rect(clippado)
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    try stdt.testing.expectEqual(@as(u32, 1), s.skipped_text);
    // Segundo rect (azul) só pintou a interseção com o clip [10,15):
    try stdt.testing.expectEqual([4]u8{ 0, 0, 255, 255 }, fb.get(12, 12));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(16, 16));
    try stdt.testing.expectEqual([4]u8{ 10, 10, 10, 255 }, fb.get(50, 50));

    const bad = [_]commands.DrawCommand{
        .{ .rect_filled = .{ .rect = types.Rect.init(0, 0, -1, 5), .color = types.Color.rgb(0, 0, 0) } },
    };
    try stdt.testing.expectError(error.InvalidCommand, render(&fb, &bad, vp));
}

test "encodePpm cabeçalho e bytes exatos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 2, 1);
    defer fb.deinit(gpa);
    fb.set(0, 0, types.Color.rgb(255, 0, 0));
    fb.set(1, 0, types.Color.rgb(0, 255, 0));
    var out: [32]u8 = undefined;
    const n = try encodePpm(&fb, &out);
    try stdt.testing.expectEqualStrings("P6\n2 1\n255\n", out[0..11]);
    try stdt.testing.expectEqual(@as(usize, 17), n);
    try stdt.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 0, 255, 0 }, out[11..17]);
    var tiny: [5]u8 = undefined;
    try stdt.testing.expectError(error.NoSpaceLeft, encodePpm(&fb, &tiny));
}

test "raster entradas não-finitas saturam em no-op" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 8, 8);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(1, 2, 3));
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    const c = types.Color.rgb(9, 9, 9);

    // Nenhuma entrada degenerada pode travar/estourar; tudo vira no-op
    // e o buffer permanece intacto.
    fb.fillRect(types.Rect.init(nan, 0, 4, 4), null, c);
    fb.fillRect(types.Rect.init(0, 0, inf, 4), null, c);
    fb.strokeLine(.{ .x = nan, .y = 0 }, .{ .x = 1, .y = 1 }, 1, null, c);
    fb.strokeLine(.{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, nan, null, c);
    fb.fillCircle(.{ .x = nan, .y = nan }, 2, null, c);
    fb.fillCircle(.{ .x = 4, .y = 4 }, nan, null, c);
    fb.strokeRect(types.Rect.init(0, 0, inf, inf), 1, null, c);
    for (0..8) |y| {
        for (0..8) |x| {
            try stdt.testing.expectEqual([4]u8{ 1, 2, 3, 255 }, fb.get(@intCast(x), @intCast(y)));
        }
    }
}
test "fuzz primitivas: sem crash com bits arbitrários" {
    try std.testing.fuzz({}, fuzzRaster, .{});
}

fn fuzzRaster(_: void, smith: *std.testing.Smith) !void {
    var backing: [16 * 16 * 4]u8 = undefined;
    smith.bytes(&backing);
    var fb = SoftwareFramebuffer{ .w = 16, .h = 16, .pixels = &backing };

    var fb2: [16]u8 = undefined;
    smith.bytes(&fb2);
    const bits: [4]f32 = @bitCast(fb2);
    const r = types.Rect{ .x = bits[0], .y = bits[1], .w = bits[2], .h = bits[3] };
    const p0 = types.Vec2{ .x = bits[0], .y = bits[1] };
    const p1 = types.Vec2{ .x = bits[2], .y = bits[3] };
    const c = types.Color{ .r = 1, .g = 2, .b = 3, .a = 4 };

    // Nenhuma chamada pode travar/estourar: conversão insegura seria
    // panic no build com safety (o que o fuzz denunciaria).
    fb.fillRect(r, null, c);
    fb.fillRect(r, types.Rect.init(-100, -100, 1000, 1000), c);
    fb.strokeLine(p0, p1, @abs(bits[0]) + 1, null, c);
    fb.fillCircle(p0, @abs(bits[1]), null, c);
    fb.strokeRect(r, @abs(bits[2]) + 1, null, c);
    fb.fillRoundRect(r, @abs(bits[3]), null, c);
    fb.fillRoundRect(r, @abs(bits[3]), types.Rect.init(-100, -100, 1000, 1000), c);
    fb.fillGradient(r, p0, p1, c, c, null);
    fb.fillGradient(r, p0, p1, c, c, types.Rect.init(-100, -100, 1000, 1000));

    // Invariante estrutural: tamanho do buffer intacto.
    try std.testing.expectEqual(@as(usize, 16 * 16 * 4), fb.pixels.len);
}

test "raster blending source-over com arredondamento" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 4, 4);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));

    // Vermelho 50% sobre preto: (255*128+127)/255 = 128.
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, .{ .r = 255, .g = 0, .b = 0, .a = 128 });
    try stdt.testing.expectEqual([4]u8{ 128, 0, 0, 255 }, fb.get(0, 0));

    // Segunda demão: (255*128+128*127+127)/255 = 192.
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, .{ .r = 255, .g = 0, .b = 0, .a = 128 });
    try stdt.testing.expectEqual([4]u8{ 192, 0, 0, 255 }, fb.get(0, 0));

    // Transparente não toca; opaco sobrescreve exato (legado).
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
    try stdt.testing.expectEqual([4]u8{ 192, 0, 0, 255 }, fb.get(0, 0));
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, types.Color.rgb(1, 2, 3));
    try stdt.testing.expectEqual([4]u8{ 1, 2, 3, 255 }, fb.get(0, 0));
}

test "render e cull concordam na fronteira (bounds canônicos)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 100, 100);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    const vp = types.Rect.init(0, 0, 100, 100);
    // Linha em y=101, espessura 2: bounds canônicos [100,102) não
    // sobrepõem [0,100) (borda exclusiva) → cull. A fórmula antiga
    // ([99,103)) a considerava visível: divergência eliminada.
    const cmds = [_]commands.DrawCommand{
        .{ .rect_filled = .{ .rect = types.Rect.init(10, 10, 20, 20), .color = types.Color.rgb(255, 0, 0) } },
        .{ .line = .{
            .p0 = types.Vec2.init(0, 101),
            .p1 = types.Vec2.init(50, 101),
            .color = types.Color.rgb(0, 255, 0),
            .thickness = 2,
        } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 1), s.drawn);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    const c = renderer.cull(&cmds, vp);
    try stdt.testing.expectEqual(s.culled, c.culled);
    try stdt.testing.expectEqual(s.submitted, c.submitted);
    // E o pixel da linha inexistente confirma: nada desenhado fora.
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(10, 99));
}

test "raster retângulo arredondado: cantos, AA e clamp do raio" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Cantos cortados pelo arco; meio das arestas e miolo cheios.
    var fb = try SoftwareFramebuffer.init(gpa, 10, 10);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillRoundRect(types.Rect.init(0, 0, 10, 10), 3.0, null, types.Color.rgb(255, 0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(9, 9));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(5, 5));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(5, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(0, 5));

    // Borda AA: arestas em x=0.5 e x=3.5 → colunas 0 e 3 a 50%.
    var fb2 = try SoftwareFramebuffer.init(gpa, 4, 4);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.fillRoundRect(types.Rect.init(0.5, 0, 3, 4), 0, null, types.Color.rgb(255, 255, 255));
    try stdt.testing.expectEqual([4]u8{ 128, 128, 128, 255 }, fb2.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(2, 0));
    try stdt.testing.expectEqual([4]u8{ 128, 128, 128, 255 }, fb2.get(3, 0));

    // Raio clampado a min(w,h)/2: 10x10 com raio 100 vira o círculo inscrito.
    var fb3 = try SoftwareFramebuffer.init(gpa, 10, 10);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.fillRoundRect(types.Rect.init(0, 0, 10, 10), 100, null, types.Color.rgb(0, 255, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb3.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 255, 0, 255 }, fb3.get(5, 5));

    // Clip restringe; transparente/não-finito/vazio saturam em no-op.
    fb3.fillRoundRect(types.Rect.init(0, 0, 10, 10), 2, types.Rect.init(4, 4, 2, 2), types.Color.rgb(255, 0, 255));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 255, 255 }, fb3.get(4, 4));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb3.get(1, 0));
    const before = fb3.get(5, 5);
    fb3.fillRoundRect(types.Rect.init(0, 0, 10, 10), 2, null, .{ .r = 9, .g = 9, .b = 9, .a = 0 });
    fb3.fillRoundRect(types.Rect.init(std.math.nan(f32), 0, 4, 4), 2, null, types.Color.rgb(9, 9, 9));
    fb3.fillRoundRect(types.Rect.init(0, 0, 4, 4), std.math.nan(f32), null, types.Color.rgb(9, 9, 9));
    fb3.fillRoundRect(types.Rect.init(0, 0, 0, 4), 2, null, types.Color.rgb(9, 9, 9));
    try stdt.testing.expectEqual(before, fb3.get(5, 5));
}

test "render com retângulo arredondado (drawn + cull)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 40, 40);
    defer fb.deinit(gpa);
    const vp = types.Rect.init(0, 0, 40, 40);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } },
        .{ .rect_rounded = .{ .rect = types.Rect.init(4, 4, 16, 16), .radius = 4, .color = types.Color.rgb(255, 0, 0) } },
        .{ .rect_rounded = .{ .rect = types.Rect.init(500, 500, 16, 16), .radius = 4, .color = types.Color.rgb(0, 255, 0) } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 3), s.submitted);
    try stdt.testing.expectEqual(@as(u32, 2), s.drawn);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(4, 4)); // canto cortado
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(12, 12)); // miolo
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(20, 20)); // fora
}

test "raster gradiente linear: horizontal, vertical, degenerado e clip" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Horizontal preto→branco em 4 px: t = .125/.375/.625/.875.
    var fb = try SoftwareFramebuffer.init(gpa, 4, 2);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillGradient(
        types.Rect.init(0, 0, 4, 2),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 32, 32, 32, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 96, 96, 96, 255 }, fb.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 159, 159, 159, 255 }, fb.get(2, 0));
    try stdt.testing.expectEqual([4]u8{ 223, 223, 223, 255 }, fb.get(3, 0));
    try stdt.testing.expectEqual([4]u8{ 32, 32, 32, 255 }, fb.get(0, 1)); // eixo horizontal

    // Vertical: eixo (0,0)→(0,2), t = .25 e .75.
    var fb2 = try SoftwareFramebuffer.init(gpa, 2, 2);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.fillGradient(
        types.Rect.init(0, 0, 2, 2),
        types.Vec2.init(0, 0),
        types.Vec2.init(0, 2),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 64, 64, 64, 255 }, fb2.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 191, 191, 191, 255 }, fb2.get(0, 1));

    // Eixo degenerado (from == to) → color0 sólido.
    var fb3 = try SoftwareFramebuffer.init(gpa, 3, 1);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.fillGradient(
        types.Rect.init(0, 0, 3, 1),
        types.Vec2.init(1, 0),
        types.Vec2.init(1, 0),
        types.Color.rgb(10, 20, 30),
        types.Color.rgb(200, 200, 200),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 10, 20, 30, 255 }, fb3.get(1, 0));

    // Fora do eixo clampa em color0/color1.
    var fb4 = try SoftwareFramebuffer.init(gpa, 3, 1);
    defer fb4.deinit(gpa);
    fb4.clear(types.Color.rgb(0, 0, 0));
    fb4.fillGradient(
        types.Rect.init(0, 0, 3, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(1, 0),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 128, 128, 128, 255 }, fb4.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb4.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb4.get(2, 0));

    // Clip; alfa herdado; retângulo vazio/não-finito = no-op.
    var fb5 = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb5.deinit(gpa);
    fb5.clear(types.Color.rgb(0, 0, 0));
    fb5.fillGradient(
        types.Rect.init(0, 0, 4, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(255, 0, 0),
        types.Color.rgb(255, 0, 0),
        types.Rect.init(1, 0, 2, 1),
    );
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb5.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb5.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb5.get(3, 0));
    fb5.fillGradient(
        types.Rect.init(0, 0, 4, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        .{ .r = 255, .g = 0, .b = 0, .a = 128 },
        .{ .r = 255, .g = 0, .b = 0, .a = 128 },
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 128, 0, 0, 255 }, fb5.get(0, 0));
    const before = fb5.get(2, 0);
    fb5.fillGradient(
        types.Rect.init(0, 0, 0, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(1, 0),
        types.Color.rgb(9, 9, 9),
        types.Color.rgb(9, 9, 9),
        null,
    );
    fb5.fillGradient(
        types.Rect.init(0, 0, 4, 1),
        types.Vec2.init(std.math.nan(f32), 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(9, 9, 9),
        types.Color.rgb(9, 9, 9),
        null,
    );
    try stdt.testing.expectEqual(before, fb5.get(2, 0));
}
