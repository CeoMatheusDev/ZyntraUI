//! ZyntraUI — interação de janelas (window/interact).
//!
//! Camada M103: máquina de estados que transforma eventos de mouse em espaço
//! do DESKTOP em mutações do registro — mover pela barra de título,
//! redimensionar pela moldura, pedir fechar (`window/decorations` decide a
//! parte sob o cursor). Não desenha, não aloca e não conhece backend: o dano
//! da recomposição é derivado pelo `window/compositor` (M102), então mover ou
//! redimensionar já aparece no próximo `compose` sem o host calcular nada.
//!
//! Fluxo do host (o press decide quem consome):
//! ```zig
//! var mgr: zyntra_ui.WindowInteractor = .{};
//! const opts: zyntra_ui.WindowInteractOptions = .{ .bounds = desktop };
//!
//! // press no desktop:
//! switch (mgr.press(&reg, pos, deco_style, opts)) {
//!     .move, .resize, .close => {},          // consumido (não vai ao widget)
//!     .client => { _ = zyntra_ui.window.input.focusAt(&reg, pos); route(pos); },
//!     .none => {},                           // nenhuma janela sob o cursor
//! }
//! // move no desktop:
//! if (mgr.isDragging()) {
//!     try mgr.update(&reg, pos, opts);
//! } else route(pos);
//! // release:
//! if (mgr.release()) |_| {} else routeRelease(pos);
//! ```
//!
//! Política: um press na barra de título/molda/botão de fechar é CONSUMIDO
//! pelo gerenciador (o arrasto é dele — não precisa da captura do
//! `window/input`); um press no cliente é classificado (`.client`) e o host
//! roteia normalmente. Com `Options.activate`, título e moldura sobem a
//! janela (`Registry.raise`) e dão foco a ela antes de arrastar; o cliente só
//! recebe foco (o empilhamento fica com o host). `.close` não mexe no
//! registro: esconder/remover é decisão de política do host.
//!
//! Ownership: `Interactor` é um valor do host (um por desktop), sem alocação
//! e sem `deinit`. Os `Context`/`Registry` continuam sendo do chamador.

const std = @import("std");
const types = @import("../core/types.zig");
const id_mod = @import("../core/id.zig");
const registry_mod = @import("registry.zig");
const decorations = @import("decorations.zig");

pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;
pub const Size = types.Size;
pub const Id = id_mod.Id;
pub const Style = decorations.Style;
pub const ResizeEdge = decorations.ResizeEdge;
pub const Registry = registry_mod.Registry;

/// Erros do registro ao aplicar geometria (`Registry.setBounds`).
pub const InteractError = registry_mod.WindowError;

/// O que um press faz (e quem o consome).
pub const Action = enum {
    /// Nenhuma janela visível sob o ponto.
    none,
    /// Press na área do cliente: o host decide (normalmente roteia para o
    /// `Context` da janela e foca).
    client,
    /// Press na barra de título: arrasto de MOVER em andamento.
    move,
    /// Press na moldura: arrasto de REDIMENSIONAR em andamento.
    resize,
    /// Press no botão de fechar: o host decide (esconder, remover, ...).
    close,
};

/// Política do arrasto.
pub const Options = struct {
    /// Tamanho mínimo ao redimensionar.
    min: Size = .{ .w = 48, .h = 32 },
    /// Limite do desktop: a geometria resultante fica dentro dele. `null` =
    /// sem limite.
    bounds: ?Rect = null,
    /// Press na barra de título/moldura sobe a janela e dá foco a ela antes
    /// de arrastar; press no cliente só dá foco. `false` deixa empilhamento e
    /// foco por conta do host.
    activate: bool = true,
};

/// Gerenciador de arrasto de janelas. Ver o fluxo no cabeçalho do módulo.
pub const Interactor = struct {
    /// Janela sob arrasto (`null` = ocioso). Legível pelo host.
    target: ?Id = null,
    /// Geometria no início do arrasto — o ponto de restauração/cancelamento.
    /// Legível pelo host.
    origin: Rect = .{},
    /// Posição (desktop) onde o arrasto começou.
    start: Vec2 = .{},
    /// Última geometria aplicada (evita `setBounds` repetido).
    last: Rect = .{},
    /// `true` se o arrasto corrente já alterou a geometria (segue válido
    /// depois de `release`, até o próximo `press`).
    changed: bool = false,
    /// Bordas ativas e tipo do arrasto corrente.
    edge: ResizeEdge = .{},
    mode: Mode = .none,

    const Mode = enum { none, move, resize };

    /// Há um arrasto em andamento?
    pub fn isDragging(self: *const Interactor) bool {
        return self.mode != .none;
    }

    /// Janela do arrasto corrente (`null` = ocioso).
    pub fn dragging(self: *const Interactor) ?Id {
        return self.target;
    }

    /// Classifica um press em `pos` (desktop) e, quando for mover ou
    /// redimensionar, já inicia o arrasto. Não falha.
    pub fn press(
        self: *Interactor,
        reg: *Registry,
        pos: Vec2,
        style: Style,
        opts: Options,
    ) Action {
        const wid = reg.windowAt(pos) orelse return .none;
        const w = reg.get(wid) orelse return .none;
        switch (decorations.hit(w.bounds, style, pos)) {
            .outside, .client => {
                if (opts.activate) _ = reg.activate(wid);
                return .client;
            },
            .close => return .close,
            .title => {
                if (opts.activate) {
                    _ = reg.raise(wid);
                    _ = reg.activate(wid);
                }
                self.begin(wid, w.bounds, pos, .move, .{});
                return .move;
            },
            .resize => |edge| {
                if (opts.activate) {
                    _ = reg.raise(wid);
                    _ = reg.activate(wid);
                }
                self.begin(wid, w.bounds, pos, .resize, edge);
                return .resize;
            },
        }
    }

    /// Aplica o arrasto corrente em `pos` (desktop): a geometria é calculada
    /// a partir do rect do início do arrasto somado ao deslocamento total
    /// (não acumula erro de arredondamento). `true` se a geometria mudou
    /// nesta chamada. Fora de arrasto não faz nada.
    ///
    /// Erros do registro (`NotFound`/`InvalidArgument`) descartam o arrasto:
    /// o alvo deixou de existir ou a geometria ficou inválida.
    pub fn update(
        self: *Interactor,
        reg: *Registry,
        pos: Vec2,
        opts: Options,
    ) InteractError!bool {
        const wid = self.target orelse return false;
        const delta = Vec2.init(pos.x - self.start.x, pos.y - self.start.y);
        const next = switch (self.mode) {
            .none => return false,
            .move => decorations.moved(self.origin, delta, opts.bounds),
            .resize => decorations.resized(self.origin, self.edge, delta, opts.min, opts.bounds),
        };
        if (sameRect(next, self.last)) return false;
        reg.setBounds(wid, next) catch |err| {
            self.cancel();
            return err;
        };
        self.last = next;
        self.changed = true;
        return true;
    }

    /// Encerra o arrasto e devolve a janela arrastada (`null` se ocioso).
    /// A geometria já aplicada fica; `changed` segue legível.
    pub fn release(self: *Interactor) ?Id {
        const wid = self.target orelse return null;
        self.cancel();
        return wid;
    }

    /// Descarta o arrasto SEM tocar na geometria — o host pode restaurar a
    /// partir de `origin` (ex.: cancelar com Esc). Idempotente.
    pub fn cancel(self: *Interactor) void {
        self.target = null;
        self.start = .{};
        self.last = .{};
        self.edge = .{};
        self.mode = .none;
    }

    fn begin(
        self: *Interactor,
        wid: Id,
        bounds: Rect,
        pos: Vec2,
        mode: Mode,
        edge: ResizeEdge,
    ) void {
        self.target = wid;
        self.origin = bounds;
        self.start = pos;
        self.last = bounds;
        self.edge = edge;
        self.mode = mode;
        self.changed = false;
    }
};

fn sameRect(a: Rect, b: Rect) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

// --- tests ---

const testing = std.testing;
const context_mod = @import("../core/context.zig");

fn winId(name: []const u8) Id {
    return Id.fromString(name);
}

/// Registro com duas janelas sobrepostas: A embaixo em (10,10,100,80) e B no
/// topo em (60,50,100,60). A ativa começa nula (`add` não ativa).
fn fixture() Registry {
    var reg: Registry = .{};
    reg.add(winId("it:a"), Rect.init(10, 10, 100, 80)) catch unreachable;
    reg.add(winId("it:b"), Rect.init(60, 50, 100, 60)) catch unreachable;
    return reg;
}

test "window/interact: título move, ergue e foca; release encerra" {
    var reg = fixture();
    const b = winId("it:b");
    var mgr: Interactor = .{};

    try testing.expectEqual(@as(?Id, null), reg.activeId());
    // (70,60) está na barra de título de B (50..74, faixa superior 4).
    const action = mgr.press(&reg, Vec2.init(70, 60), .{}, .{});
    try testing.expectEqual(Action.move, action);
    try testing.expect(mgr.isDragging());
    try testing.expectEqual(@as(?Id, b), mgr.dragging());
    try testing.expectEqual(@as(?Id, b), reg.activeId()); // foco dado
    try testing.expectEqual(@as(?Id, b), reg.order()[reg.count() - 1].id); // topo
    try testing.expect(!mgr.changed);

    // Arrasta (+30,+10) e aplica.
    try testing.expect(try mgr.update(&reg, Vec2.init(100, 70), .{}));
    try testing.expectEqual(Rect.init(90, 60, 100, 60), reg.get(b).?.bounds);
    try testing.expect(mgr.changed);
    // Mesmo ponto de novo: nada mudou, sem `setBounds`.
    try testing.expect(!try mgr.update(&reg, Vec2.init(100, 70), .{}));

    // A borda oposta não se mexe (tamanho preservado).
    try testing.expectEqual(@as(f32, 100), reg.get(b).?.bounds.w);
    try testing.expectEqual(@as(f32, 60), reg.get(b).?.bounds.h);

    try testing.expectEqual(@as(?Id, b), mgr.release());
    try testing.expect(!mgr.isDragging());
    try testing.expectEqual(@as(?Id, null), mgr.release()); // idempotente
    try testing.expect(mgr.changed); // segue legível depois do release

    // Fora de arrasto, `update` não faz nada.
    try testing.expect(!try mgr.update(&reg, Vec2.init(0, 0), .{}));
}

test "window/interact: cliente só foca (o host roteia); fechar não mexe no registro" {
    var reg = fixture();
    const a = winId("it:a");
    const b = winId("it:b");
    var mgr: Interactor = .{};

    // Zermos o cliente de B: B é (60,50,100,60) → cliente y 74..106, x 64..156.
    const action = mgr.press(&reg, Vec2.init(100, 90), .{}, .{});
    try testing.expectEqual(Action.client, action);
    try testing.expect(!mgr.isDragging());
    try testing.expectEqual(@as(?Id, b), reg.activeId());
    // Cliente NÃO ergue: A (embaixo) continua embaixo.
    try testing.expectEqual(@as(?Id, a), reg.order()[0].id);

    // Botão de fechar de B: canto direito da barra.
    const close = decorations.closeButton(reg.get(b).?.bounds, .{});
    try testing.expectEqual(Action.close, mgr.press(&reg, Vec2.init(close.x + 2, close.y + 2), .{}, .{}));
    try testing.expect(!mgr.isDragging());
    try testing.expect(reg.get(b) != null); // o host decide esconder/remover

    // Sem janela sob o ponto: `.none` (o press segue para o host).
    try testing.expectEqual(Action.none, mgr.press(&reg, Vec2.init(300, 300), .{}, .{}));
    try testing.expectEqual(@as(?Id, b), reg.activeId()); // não mexe no foco

    // Janela escondida não arrasta (hit-test ignora invisíveis).
    try testing.expect(reg.setVisible(b, false));
    const hidden = mgr.press(&reg, Vec2.init(100, 90), .{}, .{});
    try testing.expectEqual(Action.none, hidden);
}

test "window/interact: moldura redimensiona com min e limits; activate=false" {
    var reg = fixture();
    const b = winId("it:b");
    var mgr: Interactor = .{};
    const opts: Options = .{ .min = .{ .w = 40, .h = 30 }, .bounds = Rect.init(0, 0, 200, 150) };

    // Borda direita de B (60,50,100,60): x 156..160, y fora das faixas.
    const start = Vec2.init(158, 80);
    try testing.expectEqual(Action.resize, mgr.press(&reg, start, .{}, opts));
    try testing.expect(mgr.isDragging());
    try testing.expectEqual(@as(?Id, b), reg.activeId());

    // Cresce e encolhe; a esquerda (60) fica fixa.
    try testing.expect(try mgr.update(&reg, Vec2.init(198, 80), opts));
    try testing.expectEqual(@as(f32, 140), reg.get(b).?.bounds.w);
    // Estoura o desktop: 200 - 60 = 140 (já no teto).
    try testing.expect(!try mgr.update(&reg, Vec2.init(400, 80), opts));
    try testing.expectEqual(@as(f32, 140), reg.get(b).?.bounds.w);
    // Encolhe muito: para no mínimo.
    try testing.expect(try mgr.update(&reg, Vec2.init(-500, 80), opts));
    const shrunk = reg.get(b).?;
    try testing.expectEqual(@as(f32, 40), shrunk.bounds.w);
    try testing.expectEqual(@as(f32, 60), shrunk.bounds.x);

    // Borda inferior: cresce até o limite do desktop (150 - 50 = 100).
    _ = mgr.release();
    const bottom = Vec2.init(80, 108); // B = (60,50,40,60): faixa y 106..110
    try testing.expectEqual(Action.resize, mgr.press(&reg, bottom, .{}, opts));
    try testing.expect(try mgr.update(&reg, Vec2.init(80, 300), opts));
    try testing.expectEqual(@as(f32, 100), reg.get(b).?.bounds.h);
    const grown = reg.get(b).?;
    try testing.expectEqual(@as(f32, 50), grown.bounds.y);
    _ = mgr.release();

    // Canto superior esquerdo: move x/y e mantém a borda oposta fixa.
    const corner = Vec2.init(62, 52);
    try testing.expectEqual(Action.resize, mgr.press(&reg, corner, .{}, opts));
    try testing.expect(try mgr.update(&reg, Vec2.init(52, 42), opts));
    const after = reg.get(b).?.bounds;
    try testing.expectEqual(@as(f32, 50), after.x);
    try testing.expectEqual(@as(f32, 40), after.y);
    try testing.expectEqual(@as(f32, 50), after.w); // direita fixa em 100
    try testing.expectEqual(@as(f32, 110), after.h); // base fixa em 150
    _ = mgr.release();

    // Sem ativação: o arrasto acontece, o foco não muda.
    reg.clear();
    try reg.add(b, Rect.init(10, 10, 100, 80));
    var mgr2: Interactor = .{};
    try testing.expectEqual(Action.move, mgr2.press(&reg, Vec2.init(20, 20), .{}, .{ .activate = false }));
    try testing.expectEqual(@as(?Id, null), reg.activeId());
    try testing.expect(mgr2.isDragging());
    _ = mgr2.release();
}

test "window/interact: cancelar restaura pelo `origin` e update descarta alvo removido" {
    var reg = fixture();
    const b = winId("it:b");
    var mgr: Interactor = .{};

    _ = mgr.press(&reg, Vec2.init(70, 60), .{}, .{});
    const origin = mgr.origin;
    try testing.expect(try mgr.update(&reg, Vec2.init(120, 60), .{}));
    try testing.expect(reg.get(b).?.bounds.x != origin.x);

    // Cancelar não toca na geometria — o host restaura de `origin`.
    mgr.cancel();
    try testing.expect(!mgr.isDragging());
    reg.setBounds(b, origin) catch unreachable;
    const restored = reg.get(b).?;
    try testing.expectEqual(origin, restored.bounds);

    // Alvo removido no meio do arrasto: `update` devolve `NotFound` e
    // descarta o arrasto.
    _ = mgr.press(&reg, Vec2.init(70, 60), .{}, .{});
    try testing.expect(reg.remove(b));
    try testing.expectError(error.NotFound, mgr.update(&reg, Vec2.init(90, 60), .{}));
    try testing.expect(!mgr.isDragging());
}

test "window/interact: arrasto com janelas de contexto e ordem intactos" {
    const gpa = testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{ .viewport = Rect.init(0, 0, 100, 60) });
    defer ctx.deinit();

    var reg = fixture();
    const b = winId("it:b");
    try testing.expect(reg.bind(b, &ctx));

    var mgr: Interactor = .{};
    _ = mgr.press(&reg, Vec2.init(70, 60), .{}, .{});
    try testing.expect(try mgr.update(&reg, Vec2.init(80, 60), .{}));
    _ = mgr.release();

    // O gerenciador não toca no vínculo nem no contexto.
    try testing.expectEqual(@as(?*context_mod.Context, &ctx), reg.contextOf(b));
    try testing.expectEqual(Rect.init(0, 0, 100, 60), ctx.viewport);
}
