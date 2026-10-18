//! ZyntraUI — decorações de janela (window/decorations).
//!
//! Camada M103: geometria PURA das decorações — barra de título, moldura de
//! redimensionar, botão de fechar — mais o hit-test que classifica um ponto
//! do DESKTOP numa parte da janela. Não desenha, não aloca e não guarda
//! estado: é o mesmo contrato que o host usa para desenhar as decorações e
//! para decidir o arrasto (`window/interact`).
//!
//! Layout (medido a partir dos `bounds` da janela):
//! - **moldura**: `border` px em cada lado = alça de redimensionar. A faixa é
//!   limitada a metade do lado, então esquerda/direita (e topo/base) nunca se
//!   sobrepõem; um canto marca DUAS bordas ao mesmo tempo;
//! - **barra de título**: `title_height` px no topo = alça de mover;
//! - **botão de fechar**: quadrado de `button_size` px no canto direito da
//!   barra, recuado `button_margin` das bordas — use `button_margin >= border`
//!   para o botão não cair na faixa de redimensionar;
//! - **cliente**: o resto (onde vivem os widgets da janela).
//!
//! Prioridade do hit-test: moldura → botão de fechar → barra de título →
//! cliente. Fora dos `bounds` = `.outside`.
//!
//! Estilo defensivo: os valores são normalizados (finitos, não-negativos e
//! limitados ao tamanho da janela) antes de qualquer conta, então um estilo
//! estranho degrada em geometria vazia em vez de produzir números absurdos.
//! `Style.isValid` existe para o host validar o que configurou.
//!
//! Ownership: tipos por valor, sem alocação. Nenhuma função falha.

const std = @import("std");
const types = @import("../core/types.zig");

pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;
pub const Size = types.Size;

/// Estilo das decorações (pixels lógicos).
pub const Style = struct {
    /// Altura da barra de título (0 = sem barra: a janela não tem alça de mover).
    title_height: f32 = 24,
    /// Largura da moldura usada como alça de redimensionar.
    border: f32 = 4,
    /// Lado do botão de fechar.
    button_size: f32 = 16,
    /// Recuo do botão de fechar em relação às bordas.
    button_margin: f32 = 6,

    pub fn isValid(self: Style) bool {
        if (!std.math.isFinite(self.title_height) or self.title_height <= 0) return false;
        if (!std.math.isFinite(self.border) or self.border < 0) return false;
        if (!std.math.isFinite(self.button_size) or self.button_size <= 0) return false;
        if (!std.math.isFinite(self.button_margin) or self.button_margin < 0) return false;
        return true;
    }
};

/// Bordas ativas num redimensionamento (um canto marca duas).
pub const ResizeEdge = struct {
    left: bool = false,
    right: bool = false,
    top: bool = false,
    bottom: bool = false,

    pub fn any(self: ResizeEdge) bool {
        return self.left or self.right or self.top or self.bottom;
    }
};

/// Parte da janela sob um ponto do desktop.
pub const Hit = union(enum) {
    /// Fora dos `bounds`.
    outside,
    /// Barra de título: arrasta para mover.
    title,
    /// Botão de fechar (dentro da barra de título).
    close,
    /// Moldura: arrasta para redimensionar pela(s) borda(s) indicada(s).
    resize: ResizeEdge,
    /// Área do cliente (widgets).
    client,
};

/// Rect da barra de título (largura total, `title_height` no topo).
pub fn titleBar(bounds: Rect, style: Style) Rect {
    const n = normalize(bounds, style);
    return Rect.init(bounds.x, bounds.y, n.w, n.title);
}

/// Rect do botão de fechar (quadrado centrado na barra de título).
pub fn closeButton(bounds: Rect, style: Style) Rect {
    const n = normalize(bounds, style);
    return Rect.init(
        bounds.x + @max(0, n.w - n.margin - n.button),
        bounds.y + @max(0, (n.title - n.button) * 0.5),
        n.button,
        n.button,
    );
}

/// Rect do cliente (abaixo da barra, dentro da moldura; pode ser vazio se a
/// janela for pequena demais).
pub fn client(bounds: Rect, style: Style) Rect {
    const n = normalize(bounds, style);
    return Rect.init(
        bounds.x + n.border,
        bounds.y + n.title,
        @max(0, n.w - 2 * n.border),
        @max(0, n.h - n.title - n.border),
    );
}

/// Classifica `p` (espaço do desktop) numa parte de `bounds`. Ver a
/// prioridade no cabeçalho do módulo.
pub fn hit(bounds: Rect, style: Style, p: Vec2) Hit {
    if (!bounds.contains(p)) return .outside;
    const n = normalize(bounds, style);
    const lx = p.x - bounds.x;
    const ly = p.y - bounds.y;

    // 1) moldura: faixas de `border` px nas bordas (cantos marcam duas).
    var edge: ResizeEdge = .{};
    if (n.border > 0) {
        if (lx < n.border) edge.left = true;
        if (lx >= n.w - n.border) edge.right = true;
        if (ly < n.border) edge.top = true;
        if (ly >= n.h - n.border) edge.bottom = true;
    }
    if (edge.any()) return .{ .resize = edge };

    // 2) botão de fechar (está dentro da barra de título).
    if (closeButton(bounds, style).contains(p)) return .close;

    // 3) barra de título.
    if (n.title > 0 and ly < n.title) return .title;

    return .client;
}

/// Aplica um arrasto de MOVER: `origin` deslocado por `delta`, mantido dentro
/// de `bounds` (quando dado) e com o tamanho preservado. Uma janela maior que
/// `bounds` encosta na borda superior/esquerda. `delta` não-finito é zero.
pub fn moved(origin: Rect, delta: Vec2, bounds: ?Rect) Rect {
    var out = origin;
    out.x = origin.x + finiteOr0(delta.x);
    out.y = origin.y + finiteOr0(delta.y);
    if (bounds) |b| {
        out.x = fitAxis(out.x, out.w, b.x, b.w);
        out.y = fitAxis(out.y, out.h, b.y, b.h);
    }
    return out;
}

/// Aplica um arrasto de REDIMENSIONAR pela(s) borda(s) `edge`: a borda oposta
/// fica fixa, `delta` move as bordas ativas, e o resultado respeita `min` e
/// fica dentro de `bounds` (quando a origem já estava dentro). Sem borda
/// ativa a geometria não muda. Precedência: `left` sobre `right` e `top`
/// sobre `bottom`; com `bounds` menor que `min`, `bounds` vence.
pub fn resized(origin: Rect, edge: ResizeEdge, delta: Vec2, min: Size, bounds: ?Rect) Rect {
    var out = origin;
    const dx = finiteOr0(delta.x);
    const dy = finiteOr0(delta.y);
    const min_w = if (std.math.isFinite(min.w) and min.w > 0) min.w else 0;
    const min_h = if (std.math.isFinite(min.h) and min.h > 0) min.h else 0;

    if (edge.left) {
        // Borda direita fixa: só `x`/`w` mudam, `x + w` constante.
        const right = origin.x + origin.w;
        var nx = origin.x + dx;
        nx = @min(nx, right - min_w); // largura mínima
        if (bounds) |b| {
            const hi = right - min_w;
            // `bounds` vence se a faixa dele for menor que `min`.
            nx = if (hi < b.x) b.x else clampf(nx, b.x, hi);
        }
        out.x = nx;
        out.w = right - nx;
    } else if (edge.right) {
        const right = if (bounds) |b| b.x + b.w else std.math.inf(f32);
        var nw = origin.w + dx;
        nw = @max(nw, min_w); // largura mínima
        nw = @min(nw, right - origin.x); // não passa de `bounds`
        nw = @max(nw, min_w); // `min` vence se `bounds` for menor
        out.w = nw;
    }

    if (edge.top) {
        // Borda de base fixa: só `y`/`h` mudam, `y + h` constante.
        const bottom = origin.y + origin.h;
        var ny = origin.y + dy;
        ny = @min(ny, bottom - min_h);
        if (bounds) |b| {
            const hi = bottom - min_h;
            ny = if (hi < b.y) b.y else clampf(ny, b.y, hi);
        }
        out.y = ny;
        out.h = bottom - ny;
    } else if (edge.bottom) {
        const bottom = if (bounds) |b| b.y + b.h else std.math.inf(f32);
        var nh = origin.h + dy;
        nh = @max(nh, min_h);
        nh = @min(nh, bottom - origin.y);
        nh = @max(nh, min_h);
        out.h = nh;
    }

    return out;
}

/// Valores normalizados do estilo (nunca negativos nem maiores que a janela).
const Norm = struct {
    w: f32,
    h: f32,
    title: f32,
    border: f32,
    button: f32,
    margin: f32,
};

fn normalize(bounds: Rect, style: Style) Norm {
    const w = if (std.math.isFinite(bounds.w) and bounds.w > 0) bounds.w else 0;
    const h = if (std.math.isFinite(bounds.h) and bounds.h > 0) bounds.h else 0;
    var n: Norm = .{ .w = w, .h = h, .title = 0, .border = 0, .button = 0, .margin = 0 };
    if (w <= 0 or h <= 0) return n;
    const half_min = @min(w, h) * 0.5;
    n.border = clampf(positiveOr0(style.border), 0, half_min);
    n.title = clampf(positiveOr0(style.title_height), 0, h);
    n.button = clampf(positiveOr0(style.button_size), 0, half_min);
    n.margin = clampf(positiveOr0(style.button_margin), 0, w);
    return n;
}

fn clampf(v: f32, lo: f32, hi: f32) f32 {
    return @min(@max(v, lo), hi);
}

fn positiveOr0(v: f32) f32 {
    return if (std.math.isFinite(v) and v > 0) v else 0;
}

fn finiteOr0(v: f32) f32 {
    return if (std.math.isFinite(v)) v else 0;
}

/// Encaixa `pos` (tamanho `size`) dentro da faixa `lo .. lo + span`.
fn fitAxis(pos: f32, size: f32, lo: f32, span: f32) f32 {
    if (!std.math.isFinite(pos) or !std.math.isFinite(size) or
        !std.math.isFinite(lo) or !std.math.isFinite(span))
    {
        return pos;
    }
    if (span <= size) return lo; // maior que o limite: encosta na borda inicial
    return clampf(pos, lo, lo + span - size);
}

// --- tests ---

const testing = std.testing;

test "window/decorations: geometria de título, botão e cliente" {
    const bounds = Rect.init(10, 10, 100, 80);
    const style: Style = .{}; // título 24, moldura 4, botão 16, recuo 6

    try testing.expect(style.isValid());
    try testing.expectEqual(Rect.init(10, 10, 100, 24), titleBar(bounds, style));
    // botão: 100 - 6 - 16 = 78 a partir de x; centrado na barra (24-16)/2 = 4.
    try testing.expectEqual(Rect.init(88, 14, 16, 16), closeButton(bounds, style));
    // cliente: dentro da moldura, abaixo da barra.
    try testing.expectEqual(Rect.init(14, 34, 92, 52), client(bounds, style));

    // Janela pequena: o cliente colapsa, nada fica negativo.
    const small = Rect.init(0, 0, 6, 6);
    try testing.expectEqual(Rect.init(3, 6, 0, 0), client(small, .{}));
    try testing.expectEqual(@as(f32, 6), titleBar(small, .{}).w);

    // Estilo inválido degrada (sem NaN, sem negativo).
    const bad: Style = .{ .title_height = std.math.nan(f32), .border = -5, .button_size = 0 };
    try testing.expect(!bad.isValid());
    try testing.expectEqual(Rect.init(10, 10, 100, 0), titleBar(bounds, bad));
    try testing.expectEqual(@as(f32, 0), closeButton(bounds, bad).w);
}

test "window/decorations: hit-test por prioridade (moldura → botão → título → cliente)" {
    const bounds = Rect.init(10, 10, 100, 80);
    const style: Style = .{};

    try testing.expect(hit(bounds, style, Vec2.init(9, 10)) == .outside);
    try testing.expect(hit(bounds, style, Vec2.init(10, 90)) == .outside); // base exclusiva

    // cliente (meio da janela, longe das bordas).
    try testing.expect(hit(bounds, style, Vec2.init(60, 60)) == .client);

    // título (dentro da barra, fora da faixa superior da moldura).
    try testing.expect(hit(bounds, style, Vec2.init(40, 20)) == .title);

    // botão de fechar (vence o título).
    try testing.expect(hit(bounds, style, Vec2.init(96, 22)) == .close);

    // moldura vence o título (a faixa superior faz parte da alça).
    const top = hit(bounds, style, Vec2.init(40, 11));
    try testing.expect(top == .resize and top.resize.top and !top.resize.left);

    const left = hit(bounds, style, Vec2.init(11, 50));
    try testing.expect(left == .resize and left.resize.left and !left.resize.top);

    const right = hit(bounds, style, Vec2.init(108, 88));
    try testing.expect(right == .resize and right.resize.right and right.resize.bottom);

    const corner = hit(bounds, style, Vec2.init(109, 11));
    try testing.expect(corner == .resize and corner.resize.top and corner.resize.right);

    // Botão com recuo menor que a moldura cai na faixa de redimensionar: a
    // moldura vence (por isso `button_margin >= border`).
    const tight: Style = .{ .button_margin = 0 };
    const overlap = Vec2.init(108, 20); // dentro do botão E da moldura direita
    try testing.expect(closeButton(bounds, tight).contains(overlap));
    const band = hit(bounds, tight, overlap);
    try testing.expect(band == .resize and band.resize.right);
}

test "window/decorations: mover com limites e delta inválido" {
    const origin = Rect.init(20, 20, 40, 30);
    const desktop = Rect.init(0, 0, 100, 100);

    // Deslocamento livre.
    try testing.expectEqual(
        Rect.init(30, 25, 40, 30),
        moved(origin, Vec2.init(10, 5), null),
    );
    // Limitado ao desktop (borda direita/base).
    try testing.expectEqual(
        Rect.init(60, 70, 40, 30),
        moved(origin, Vec2.init(999, 999), desktop),
    );
    // Limitado à esquerda/topo.
    try testing.expectEqual(
        Rect.init(0, 0, 40, 30),
        moved(origin, Vec2.init(-999, -999), desktop),
    );
    // Maior que o desktop: encosta no topo/esquerda (não fica passeando).
    try testing.expectEqual(
        Rect.init(0, 0, 140, 130),
        moved(Rect.init(50, 50, 140, 130), Vec2.init(10, 10), desktop),
    );
    // Delta não-finito não move.
    try testing.expectEqual(origin, moved(origin, Vec2.init(std.math.nan(f32), 0), null));
}

test "window/decorations: redimensionar respeita min e bounds" {
    const origin = Rect.init(20, 20, 40, 30);
    const desktop = Rect.init(0, 0, 100, 100);
    const min = Size.init(10, 10);

    // Sem borda ativa: nada muda.
    try testing.expectEqual(origin, resized(origin, .{}, Vec2.init(50, 50), min, null));

    // Direita: cresce e encolhe; a esquerda fica fixa.
    try testing.expectEqual(
        Rect.init(20, 20, 60, 30),
        resized(origin, .{ .right = true }, Vec2.init(20, 0), min, null),
    );
    try testing.expectEqual(
        Rect.init(20, 20, 10, 30),
        resized(origin, .{ .right = true }, Vec2.init(-999, 0), min, null),
    );
    // Direita limitada ao desktop (100 - 20 = 80).
    try testing.expectEqual(
        Rect.init(20, 20, 80, 30),
        resized(origin, .{ .right = true }, Vec2.init(999, 0), min, desktop),
    );

    // Esquerda: move x e mantém x + w (borda direita fixa).
    try testing.expectEqual(
        Rect.init(10, 20, 50, 30),
        resized(origin, .{ .left = true }, Vec2.init(-10, 0), min, null),
    );
    try testing.expectEqual(
        Rect.init(50, 20, 10, 30),
        resized(origin, .{ .left = true }, Vec2.init(999, 0), min, null),
    );
    try testing.expectEqual(
        Rect.init(0, 20, 60, 30),
        resized(origin, .{ .left = true }, Vec2.init(-999, 0), min, desktop),
    );

    // Base e topo (mesma lógica no eixo vertical).
    try testing.expectEqual(
        Rect.init(20, 20, 40, 60),
        resized(origin, .{ .bottom = true }, Vec2.init(0, 30), min, null),
    );
    try testing.expectEqual(
        Rect.init(20, 10, 40, 40),
        resized(origin, .{ .top = true }, Vec2.init(0, -10), min, null),
    );

    // Canto: aplica as duas bordas.
    try testing.expectEqual(
        Rect.init(10, 10, 50, 40),
        resized(origin, .{ .left = true, .top = true }, Vec2.init(-10, -10), min, desktop),
    );

    // Delta não-finito não redimensiona.
    try testing.expectEqual(
        origin,
        resized(origin, .{ .right = true }, Vec2.init(std.math.nan(f32), 0), min, null),
    );
}
