//! ZyntraUI — registro de janelas (window/registry).
//!
//! Modelo M100 (multi-janela): a lista de janelas de uma aplicação —
//! identidade estável, geometria no espaço do desktop, ordem de
//! empilhamento (z-order) e janela ativa — **puro**: sem `Context`, sem
//! alocação e sem backend. O chamador é dono do registro
//! (`var reg: WindowRegistry = .{}`), como em `dock/layout`.
//!
//! Papel na arquitetura: uma janela do sistema operacional continua
//! sendo responsabilidade do host; o registro organiza as *superfícies*
//! de UI que o host apresenta. Cada janela normalmente tem um `Context`
//! próprio (um frame por janela), e o registro responde as perguntas de
//! política que o host faria:
//! - **foco**: qual janela recebe teclado (`activeId`/`activateAt`);
//! - **input**: qual janela está sob o cursor (`windowAt`), e como
//!   converter coordenadas desktop ⇄ locais (`toLocal`/`toDesktop`);
//! - **desenho**: em que ordem desenhar (`order`, base → topo).
//!
//! Convenções:
//! - `windows[0]` é a janela de BAIXO e `windows[len-1]` a de CIMA
//!   (última desenhada, vencedora do hit-test) — mesma regra do
//!   hit-test de `graph/view` (iteração reversa).
//! - `add` NÃO ativa: foco é decisão explícita do chamador
//!   (`activate`, `activateAt`).
//! - Visibilidade afeta hit-test e desenho, nunca o foco: esconder a
//!   janela ativa mantém o foco nela (o host decide reativar).
//! - Ids nulos ou ausentes são sempre tratados como "não existe"
//!   (nunca crasham); rect inválido (não-finito, `w`/`h` <= 0) é
//!   rejeitado.
//! - Sem desenho: combine com os widgets (`panel` etc.) e com o
//!   rasterizador para pintar cada janela no seu offset do desktop.

const std = @import("std");
const types = @import("../core/types.zig");
const id_mod = @import("../core/id.zig");

pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;
pub const Id = id_mod.Id;

/// Erros do registro de janelas.
pub const WindowError = error{
    /// Id nulo ou rect inválido (não-finito, `w`/`h` <= 0).
    InvalidArgument,
    /// Nenhuma janela com o id informado.
    NotFound,
    /// Já existe uma janela com o id informado.
    DuplicateId,
    /// `max_windows` atingido.
    TooManyWindows,
};

/// `true` para um rect de janela válido (finito e com área positiva).
fn isBoundsValid(bounds: Rect) bool {
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y)) return false;
    if (!std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h)) return false;
    return bounds.w > 0 and bounds.h > 0;
}

/// Janela registrada: identidade + geometria no espaço do desktop.
pub const Window = struct {
    /// Id estável da janela (nunca nulo numa janela registrada).
    id: Id,
    /// Posição + tamanho no espaço do desktop (pixels lógicos).
    bounds: Rect,
    /// Participa do hit-test (`windowAt`) e da ordem de desenho.
    visible: bool = true,

    pub fn isValid(self: Window) bool {
        return !self.id.isNull() and isBoundsValid(self.bounds);
    }

    /// Viewport local da janela (origem em 0,0) — o valor típico para o
    /// `Context.setViewport` do contexto desta janela.
    pub fn viewport(self: Window) Rect {
        return Rect.init(0, 0, self.bounds.w, self.bounds.h);
    }

    /// `true` se `p` (desktop) está dentro da janela.
    pub fn contains(self: Window, p: Vec2) bool {
        return self.bounds.contains(p);
    }
};

/// Registro de janelas: array fixo dentro do próprio valor (o chamador é
/// dono), ordem de empilhamento e foco. Sem alocação e sem `deinit`.
pub const Registry = struct {
    /// Janelas simultâneas no registro.
    pub const max_windows: usize = 16;

    /// Janelas em ordem de empilhamento: `windows[0..len]`, base → topo.
    /// Slots a partir de `len` são lixo e nunca são lidos.
    windows: [max_windows]Window = undefined,
    /// Janelas registradas (índices válidos: `0..len`).
    len: usize = 0,
    /// Janela com foco (`null` = ninguém). Sobrevive a reordenações e a
    /// remoções de outras janelas; zera quando a janela ativa sai ou no
    /// `clear`.
    active: ?Id = null,

    pub fn isEmpty(self: *const Registry) bool {
        return self.len == 0;
    }

    /// `true` quando não há espaço para mais janelas.
    pub fn isFull(self: *const Registry) bool {
        return self.len >= max_windows;
    }

    /// Quantidade de janelas registradas.
    pub fn count(self: *const Registry) usize {
        return self.len;
    }

    /// Id da janela ativa (`null` = nenhuma).
    pub fn activeId(self: *const Registry) ?Id {
        return self.active;
    }

    /// Janelas em ordem de empilhamento (`[0]` = base, fim = topo):
    /// desenhe nesta ordem. Fatia válida até a próxima mutação.
    pub fn order(self: *const Registry) []const Window {
        return self.windows[0..self.len];
    }

    /// Índice de `wid` na ordem de empilhamento (`null` = ausente; id
    /// nulo nunca existe).
    pub fn indexOf(self: *const Registry, wid: Id) ?usize {
        if (wid.isNull()) return null;
        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            if (self.windows[i].id == wid) return i;
        }
        return null;
    }

    /// Janela por id (`null` = ausente).
    pub fn get(self: *const Registry, wid: Id) ?Window {
        const i = self.indexOf(wid) orelse return null;
        return self.windows[i];
    }

    /// Janela por índice na ordem de empilhamento (`null` = fora de
    /// faixa).
    pub fn at(self: *const Registry, index: usize) ?Window {
        if (index >= self.len) return null;
        return self.windows[index];
    }

    /// Registra `wid` no TOPO do empilhamento (passa a ser a última
    /// desenhada). Não mexe no foco. Erros: id nulo ou rect inválido
    /// (`InvalidArgument`), id já registrado (`DuplicateId`), registro
    /// cheio (`TooManyWindows`).
    pub fn add(self: *Registry, wid: Id, bounds: Rect) WindowError!void {
        if (wid.isNull() or !isBoundsValid(bounds)) return error.InvalidArgument;
        if (self.indexOf(wid) != null) return error.DuplicateId;
        if (self.isFull()) return error.TooManyWindows;
        self.windows[self.len] = .{ .id = wid, .bounds = bounds };
        self.len += 1;
    }

    /// Remove `wid`, preservando a ordem relativa das demais. Devolve
    /// `false` se não existia (inclusive id nulo). Se era a janela
    /// ativa, o foco passa a ninguém (`activeId() == null`) — reativar
    /// é decisão do chamador.
    pub fn remove(self: *Registry, wid: Id) bool {
        const i = self.indexOf(wid) orelse return false;
        var j = i;
        while (j + 1 < self.len) : (j += 1) self.windows[j] = self.windows[j + 1];
        self.len -= 1;
        if (self.active) |cur| {
            if (cur == wid) self.active = null;
        }
        return true;
    }

    /// Sobe `wid` ao topo do empilhamento (vira a última desenhada).
    /// `false` se não existia; já estando no topo, nada muda.
    pub fn raise(self: *Registry, wid: Id) bool {
        const i = self.indexOf(wid) orelse return false;
        if (i + 1 >= self.len) return true;
        const w = self.windows[i];
        var j = i;
        while (j + 1 < self.len) : (j += 1) self.windows[j] = self.windows[j + 1];
        self.windows[self.len - 1] = w;
        return true;
    }

    /// Dá foco a `wid` sem mexer no empilhamento. `false` se ausente.
    /// Visibilidade não bloqueia o foco.
    pub fn activate(self: *Registry, wid: Id) bool {
        if (self.indexOf(wid) == null) return false;
        self.active = wid;
        return true;
    }

    /// Ativa a janela VISÍVEL do topo sob `p` e a traz para frente;
    /// devolve o id ativado (`null` = nenhuma janela visível sob o
    /// ponto, sem mexer em ordem nem foco).
    pub fn activateAt(self: *Registry, p: Vec2) ?Id {
        const wid = self.windowAt(p) orelse return null;
        _ = self.raise(wid);
        self.active = wid;
        return wid;
    }

    /// Move/redimensiona `wid` (o rect é o novo `bounds`). Erros: rect
    /// inválido (`InvalidArgument`), janela ausente (`NotFound`).
    pub fn setBounds(self: *Registry, wid: Id, bounds: Rect) WindowError!void {
        if (!isBoundsValid(bounds)) return error.InvalidArgument;
        const i = self.indexOf(wid) orelse return error.NotFound;
        self.windows[i].bounds = bounds;
    }

    /// Mostra/esconde `wid` (hit-test e desenho). `false` se ausente.
    /// Não altera o foco.
    pub fn setVisible(self: *Registry, wid: Id, visible: bool) bool {
        const i = self.indexOf(wid) orelse return false;
        self.windows[i].visible = visible;
        return true;
    }

    /// Id da janela VISÍVEL do topo que contém `p` (última desenhada
    /// vence). `null` = nenhuma.
    pub fn windowAt(self: *const Registry, p: Vec2) ?Id {
        var i = self.len;
        while (i > 0) {
            i -= 1;
            const w = self.windows[i];
            if (w.visible and w.bounds.contains(p)) return w.id;
        }
        return null;
    }

    /// Esvazia o registro (o foco volta a ninguém).
    pub fn clear(self: *Registry) void {
        self.len = 0;
        self.active = null;
    }

    /// Converte `p` (espaço do desktop) para o espaço local de `wid`.
    /// `null` se a janela não existe.
    pub fn toLocal(self: *const Registry, wid: Id, p: Vec2) ?Vec2 {
        const w = self.get(wid) orelse return null;
        return .{ .x = p.x - w.bounds.x, .y = p.y - w.bounds.y };
    }

    /// Converte `p` (espaço local de `wid`) para o espaço do desktop.
    /// `null` se a janela não existe.
    pub fn toDesktop(self: *const Registry, wid: Id, p: Vec2) ?Vec2 {
        const w = self.get(wid) orelse return null;
        return .{ .x = p.x + w.bounds.x, .y = p.y + w.bounds.y };
    }
};

// --- tests ---

const testing = std.testing;

fn winId(name: []const u8) Id {
    return Id.fromString(name);
}

test "window: add valida, empilha no topo e recusa duplicado" {
    var reg: Registry = .{};
    const a = winId("win:a");
    const b = winId("win:b");

    try testing.expect(reg.isEmpty());
    try testing.expectEqual(@as(usize, 0), reg.count());
    try testing.expect(reg.activeId() == null);

    // Entradas inválidas.
    try testing.expectError(error.InvalidArgument, reg.add(.null, Rect.init(0, 0, 10, 10)));
    try testing.expectError(error.InvalidArgument, reg.add(a, Rect.init(0, 0, 0, 10)));
    try testing.expectError(error.InvalidArgument, reg.add(a, Rect.init(0, 0, 10, -1)));
    try testing.expectError(error.InvalidArgument, reg.add(a, Rect.init(std.math.nan(f32), 0, 10, 10)));
    try testing.expectError(error.InvalidArgument, reg.add(a, Rect.init(0, 0, std.math.inf(f32), 10)));
    try testing.expect(reg.isEmpty());

    // Ordem de empilhamento: o último adicionado fica no topo.
    try reg.add(a, Rect.init(10, 10, 100, 80));
    try reg.add(b, Rect.init(60, 40, 100, 80));
    try testing.expectEqual(@as(usize, 2), reg.count());
    try testing.expect(!reg.isFull());
    try testing.expectEqual(a, reg.order()[0].id);
    try testing.expectEqual(b, reg.order()[1].id);
    try testing.expectEqual(@as(usize, 0), reg.indexOf(a).?);
    try testing.expectEqual(@as(usize, 1), reg.indexOf(b).?);
    try testing.expectEqual(@as(f32, 100), reg.get(a).?.bounds.w);
    try testing.expectEqual(b, reg.at(1).?.id);
    try testing.expect(reg.get(winId("win:missing")) == null);
    try testing.expect(reg.indexOf(.null) == null);
    try testing.expect(reg.at(2) == null);

    // `add` não ativa: foco continua sendo decisão explícita.
    try testing.expect(reg.activeId() == null);

    // Duplicado (mesmo parado, caso já exista).
    try testing.expectError(error.DuplicateId, reg.add(a, Rect.init(0, 0, 1, 1)));
}

test "window: windowAt devolve a do topo visível e ignora escondidas" {
    var reg: Registry = .{};
    const a = winId("win:at:a");
    const b = winId("win:at:b");
    try reg.add(a, Rect.init(10, 10, 100, 80)); // 10..110 x 10..90
    try reg.add(b, Rect.init(60, 40, 100, 80)); // 60..160 x 40..120

    // Sobreposição: vence a de cima (b).
    try testing.expectEqual(b, reg.windowAt(Vec2.init(70, 50)).?);
    // Só uma contém o ponto.
    try testing.expectEqual(a, reg.windowAt(Vec2.init(20, 20)).?);
    try testing.expectEqual(b, reg.windowAt(Vec2.init(150, 100)).?);
    // Bordas: direita/inferior exclusivas (x=110 sai de a, entra em b).
    try testing.expectEqual(b, reg.windowAt(Vec2.init(110, 50)).?);
    try testing.expectEqual(a, reg.windowAt(Vec2.init(20, 89.5)).?);
    try testing.expect(reg.windowAt(Vec2.init(20, 90)) == null);
    // Fora de todas.
    try testing.expect(reg.windowAt(Vec2.init(0, 0)) == null);

    // Esconder tira a janela do hit-test; a de baixo aparece.
    try testing.expect(reg.setVisible(b, false));
    try testing.expectEqual(a, reg.windowAt(Vec2.init(70, 50)).?);
    try testing.expect(reg.windowAt(Vec2.init(150, 100)) == null);
    try testing.expect(reg.setVisible(b, true));
    try testing.expectEqual(b, reg.windowAt(Vec2.init(70, 50)).?);

    // Ids ausentes nas mutações de visibilidade/geometria.
    try testing.expect(!reg.setVisible(winId("win:at:missing"), false));
}

test "window: raise reordena e activate dá foco sem mexer no empilhamento" {
    var reg: Registry = .{};
    const a = winId("win:raise:a");
    const b = winId("win:raise:b");
    const c = winId("win:raise:c");
    try reg.add(a, Rect.init(0, 0, 40, 40));
    try reg.add(b, Rect.init(0, 0, 40, 40));
    try reg.add(c, Rect.init(0, 0, 40, 40));

    // Sobe a base: [a,b,c] → [b,c,a].
    try testing.expect(reg.raise(a));
    try testing.expectEqual(b, reg.order()[0].id);
    try testing.expectEqual(c, reg.order()[1].id);
    try testing.expectEqual(a, reg.order()[2].id);
    try testing.expectEqual(@as(usize, 2), reg.indexOf(a).?);
    // Já no topo: nada muda, segue `true`.
    try testing.expect(reg.raise(a));
    try testing.expectEqual(a, reg.order()[2].id);
    // Ausente.
    try testing.expect(!reg.raise(winId("win:raise:missing")));

    // Foco não mexe na ordem.
    const before = reg.indexOf(c).?;
    try testing.expect(reg.activate(c));
    try testing.expectEqual(c, reg.activeId().?);
    try testing.expectEqual(before, reg.indexOf(c).?);
    try testing.expect(!reg.activate(winId("win:raise:missing")));
    try testing.expectEqual(c, reg.activeId().?);
}

test "window: activateAt sobe e foca a janela sob o ponto" {
    var reg: Registry = .{};
    const a = winId("win:click:a");
    const b = winId("win:click:b");
    const c = winId("win:click:c");
    try reg.add(a, Rect.init(10, 10, 100, 80)); // 10..110 x 10..90
    try reg.add(b, Rect.init(60, 40, 100, 80)); // 60..160 x 40..120
    try reg.add(c, Rect.init(0, 0, 30, 20)); // 0..30 x 0..20

    // Clique na sobreposição: ativa a de cima (b) e a traz para frente
    // (c já estava no topo, mas não contém o ponto).
    try testing.expectEqual(b, reg.activateAt(Vec2.init(70, 50)).?);
    try testing.expectEqual(b, reg.activeId().?);
    try testing.expectEqual(@as(usize, 2), reg.indexOf(b).?);

    // Clique em área exclusiva de c (que também é a de cima): permanece.
    try testing.expectEqual(c, reg.activateAt(Vec2.init(5, 5)).?);
    try testing.expectEqual(c, reg.activeId().?);
    try testing.expectEqual(@as(usize, 2), reg.indexOf(c).?);

    // Clique sem janela: não muda ordem nem foco.
    const top_before = reg.order()[2].id;
    const active_before = reg.activeId().?;
    try testing.expect(reg.activateAt(Vec2.init(300, 300)) == null);
    try testing.expectEqual(top_before, reg.order()[2].id);
    try testing.expectEqual(active_before, reg.activeId().?);

    // Janela escondida não é alvo de clique (e a de baixo assume).
    try testing.expect(reg.setVisible(b, false));
    try testing.expectEqual(a, reg.activateAt(Vec2.init(70, 50)).?);
    try testing.expectEqual(@as(usize, 2), reg.indexOf(a).?);
}

test "window: setBounds valida, move e preserva o foco ao esconder" {
    var reg: Registry = .{};
    const a = winId("win:bounds:a");
    const b = winId("win:bounds:b");
    try reg.add(a, Rect.init(10, 20, 100, 80));
    try reg.add(b, Rect.init(0, 0, 50, 50));

    // Rect inválido não altera a geometria.
    try testing.expectError(error.InvalidArgument, reg.setBounds(a, Rect.init(0, 0, 10, 0)));
    try testing.expectEqual(Rect.init(10, 20, 100, 80), reg.get(a).?.bounds);
    // Janela ausente.
    try testing.expectError(error.NotFound, reg.setBounds(winId("win:bounds:missing"), Rect.init(0, 0, 5, 5)));

    try reg.setBounds(a, Rect.init(30, 40, 120, 90));
    try testing.expectEqual(Rect.init(30, 40, 120, 90), reg.get(a).?.bounds);
    try testing.expectEqual(Vec2.init(40, 60), reg.toLocal(a, Vec2.init(70, 100)).?);

    // Foco sobrevive a esconder/mostrar (visibilidade != foco).
    try testing.expect(reg.activate(a));
    try testing.expect(reg.setVisible(a, false));
    try testing.expectEqual(a, reg.activeId().?);
    try testing.expect(reg.setVisible(a, true));
    try testing.expectEqual(a, reg.activeId().?);

    // Geometria local: viewport na origem + contains.
    const w = reg.get(a).?;
    try testing.expect(w.isValid());
    try testing.expectEqual(Rect.init(0, 0, 120, 90), w.viewport());
    try testing.expect(w.contains(Vec2.init(100, 90)));
    try testing.expect(!w.contains(Vec2.init(100, 130)));
}

test "window: toLocal/toDesktop transladam e id ausente é null" {
    var reg: Registry = .{};
    const a = winId("win:tr:a");
    try reg.add(a, Rect.init(10, 20, 100, 80));
    try testing.expectEqual(Vec2.init(20, 15), reg.toLocal(a, Vec2.init(30, 35)).?);
    try testing.expectEqual(Vec2.init(30, 35), reg.toDesktop(a, Vec2.init(20, 15)).?);
    // Roundtrip ida e volta.
    try testing.expectEqual(Vec2.init(7, 9), reg.toLocal(a, reg.toDesktop(a, Vec2.init(7, 9)).?).?);
    // Ausente / nulo.
    try testing.expect(reg.toLocal(winId("win:tr:missing"), Vec2.init(0, 0)) == null);
    try testing.expect(reg.toDesktop(.null, Vec2.init(0, 0)) == null);
}

test "window: remove preserva ordem, zera foco só da ativa e é idempotente" {
    var reg: Registry = .{};
    const a = winId("win:rm:a");
    const b = winId("win:rm:b");
    const c = winId("win:rm:c");
    try reg.add(a, Rect.init(0, 0, 10, 10));
    try reg.add(b, Rect.init(20, 0, 10, 10));
    try reg.add(c, Rect.init(40, 0, 10, 10));
    try testing.expect(reg.activate(b));

    // Remover a de baixo mantém a ordem relativa e o foco intacto.
    try testing.expect(reg.remove(a));
    try testing.expectEqual(@as(usize, 2), reg.count());
    try testing.expectEqual(b, reg.order()[0].id);
    try testing.expectEqual(c, reg.order()[1].id);
    try testing.expectEqual(b, reg.activeId().?);

    // Remover a ativa zera o foco.
    try testing.expect(reg.remove(b));
    try testing.expect(reg.activeId() == null);
    try testing.expectEqual(c, reg.order()[0].id);

    // Idempotente e id nulo nunca existe.
    try testing.expect(!reg.remove(b));
    try testing.expect(!reg.remove(.null));

    // `clear` esvazia tudo.
    try testing.expect(reg.activate(c));
    reg.clear();
    try testing.expect(reg.isEmpty());
    try testing.expectEqual(@as(usize, 0), reg.count());
    try testing.expect(reg.activeId() == null);
    try testing.expect(reg.order().len == 0);
}

test "window: limite de janelas e reuso após clear" {
    var reg: Registry = .{};
    var i: u32 = 0;
    while (i < Registry.max_windows) : (i += 1) {
        try reg.add(Id.fromU64(i + 1), Rect.init(0, 0, 10, 10));
    }
    try testing.expect(reg.isFull());
    try testing.expectEqual(Registry.max_windows, reg.count());
    try testing.expectError(
        error.TooManyWindows,
        reg.add(Id.fromU64(1000), Rect.init(0, 0, 10, 10)),
    );
    // Rejeitado por cheio não entra (nem no hit-test).
    try testing.expect(reg.indexOf(Id.fromU64(1000)) == null);
    try testing.expectEqual(Id.fromU64(Registry.max_windows), reg.windowAt(Vec2.init(5, 5)).?);

    reg.clear();
    try testing.expect(!reg.isFull());
    try reg.add(Id.fromU64(1000), Rect.init(0, 0, 10, 10));
    try testing.expectEqual(Id.fromU64(1000), reg.windowAt(Vec2.init(5, 5)).?);
}
