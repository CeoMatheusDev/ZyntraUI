//! ZyntraUI — roteamento de input entre janelas (window/input).
//!
//! Camada M101: liga o registro de janelas (`window/registry`, M100) aos
//! `Context`s que cada janela vincula (`Registry.bind`), entregando os
//! eventos no espaço LOCAL da janela certa. O registro continua sendo
//! quem sabe identidade, empilhamento (z-order) e janela ativa; aqui
//! ficam só a política de roteamento, a captura de press no nível de
//! janela e a troca de foco de janela.
//!
//! Convenção de coordenadas: TODAS as posições recebidas por estas
//! funções estão no espaço do DESKTOP (é o que o SO entrega ao host); os
//! eventos enfileirados no `Context` levam a posição LOCAL da janela.
//!
//! Regras de roteamento:
//! - Mouse sem press capturado: vai para a janela VISÍVEL do topo sob o
//!   cursor (`Registry.windowAt`) que tenha `Context` vinculado. A janela
//!   do topo MANDA: se ela não tem contexto, o evento é descartado (não
//!   "atravessa" para as de baixo).
//! - Mouse com press capturado: vai para a janela que recebeu o press,
//!   MESMO com o cursor fora dela — as coordenadas locais podem ficar
//!   negativas ou além do tamanho, e é isso que mantém um arraste de
//!   widget vivo ao sair dos bounds. A captura termina no release.
//! - Roda (`mouse_wheel`): segue o CURSOR, não a captura (como no SO).
//! - Teclado/texto: vai para a janela ATIVA (`Registry.activeId`) que
//!   tenha contexto — não há roteamento de teclado por posição.
//! - Release sem captura é descartado (nunca vai por hit-test): quem não
//!   recebeu o press não recebe o release. Captura órfã (janela removida
//!   ou desvinculada no meio do arraste) também descarta os eventos, e o
//!   release apenas encerra a captura — o host pode antecipar com
//!   `Router.clearCapture`.
//! - O roteador NÃO mexe em z-order nem na janela ativa: quem decide é o
//!   host (`Registry.raise`/`activateAt` ou `focusAt` daqui). Visibilidade
//!   afeta só o hit-test.
//! - Nenhum evento `focus`/`resize` é sintetizado (o modelo de eventos do
//!   núcleo não os consome). Trocar a janela ativa limpa o foco de WIDGET
//!   da janela que sai (`Context.clearFocus`), para um text-input não
//!   seguir "focado" sem receber teclado.
//!
//! Ownership: nada é alocado aqui. `Router` é estado do host (um por
//! desktop), por valor; os `Context` continuam sendo do chamador.

const std = @import("std");
const types = @import("../core/types.zig");
const id_mod = @import("../core/id.zig");
const context_mod = @import("../core/context.zig");
const event_mod = @import("../event/event.zig");
const registry_mod = @import("registry.zig");

pub const Vec2 = types.Vec2;
pub const Id = id_mod.Id;
pub const Context = context_mod.Context;
pub const ContextError = context_mod.ContextError;
pub const Registry = registry_mod.Registry;
pub const MouseButton = event_mod.MouseButton;
pub const Key = event_mod.Key;
pub const Modifiers = event_mod.Modifiers;

/// Destino de um evento de mouse: janela, contexto e posição local.
pub const Route = struct {
    /// Janela que recebeu (ou receberia) o evento.
    window: Id,
    /// `Context` vinculado dessa janela.
    ctx: *Context,
    /// Posição do cursor no espaço LOCAL da janela.
    pos: Vec2,
};

/// Estado de input do desktop (por valor, sem alocação).
pub const Router = struct {
    /// Janela que capturou o press atual (`null` = nenhum). Vira `null`
    /// no release entregue; use `clearCapture` para liberar antes (janela
    /// fechada, perda de foco do SO, Esc global).
    press_window: ?Id = null,

    /// `true` enquanto há press capturado.
    pub fn isCapturing(self: *const Router) bool {
        return self.press_window != null;
    }

    /// Libera a captura sem entregar release. Um widget que ficou
    /// esperando o release precisa ser zerado pelo host
    /// (`Context.clearPressCapture`), como em qualquer captura órfã.
    pub fn clearCapture(self: *Router) void {
        self.press_window = null;
    }
};

/// Janela visível do topo sob `p` (desktop) que tenha `Context`
/// vinculado. `null` = nada sob o ponto, ou a janela do topo não tem
/// contexto.
pub fn targetAt(reg: *const Registry, p: Vec2) ?Route {
    const wid = reg.windowAt(p) orelse return null;
    const ctx = reg.contextOf(wid) orelse return null;
    const local = reg.toLocal(wid, p) orelse return null;
    return .{ .window = wid, .ctx = ctx, .pos = local };
}

/// Destino efetivo de um evento de mouse em `p` (desktop): a captura, se
/// houver; senão a janela sob o cursor. `null` = descartar (inclusive
/// captura órfã).
pub fn routeAt(r: *const Router, reg: *const Registry, p: Vec2) ?Route {
    if (r.press_window) |wid| {
        const ctx = reg.contextOf(wid) orelse return null;
        const local = reg.toLocal(wid, p) orelse return null;
        return .{ .window = wid, .ctx = ctx, .pos = local };
    }
    return targetAt(reg, p);
}

/// Entrega um `mouse_move` em `p` (desktop): à captura, se houver; senão
/// à janela sob o cursor. `false` = descartado (nada enfileirado).
pub fn pushMouseMove(r: *const Router, reg: *const Registry, p: Vec2) ContextError!bool {
    const dst = routeAt(r, reg, p) orelse return false;
    try dst.ctx.pushEvent(.{ .mouse_move = .{ .pos = dst.pos } });
    return true;
}

/// Entrega um `mouse_button` em `p` (desktop). No press, a janela sob o
/// cursor (com contexto) passa a capturar — o press mais recente manda,
/// inclusive se já havia outra captura; press sem alvo não mexe na
/// captura. No release, entrega à captura e a encerra (qualquer que seja
/// o botão), e sem captura o evento é descartado. `false` = nada
/// enfileirado.
pub fn pushButton(
    r: *Router,
    reg: *const Registry,
    button: MouseButton,
    pressed: bool,
    p: Vec2,
) ContextError!bool {
    if (!pressed) {
        const wid = r.press_window orelse return false;
        r.press_window = null;
        const ctx = reg.contextOf(wid) orelse return false;
        const local = reg.toLocal(wid, p) orelse return false;
        try ctx.pushEvent(.{ .mouse_button = .{
            .button = button,
            .pressed = false,
            .pos = local,
        } });
        return true;
    }
    const dst = targetAt(reg, p) orelse return false;
    try dst.ctx.pushEvent(.{ .mouse_button = .{
        .button = button,
        .pressed = true,
        .pos = dst.pos,
    } });
    r.press_window = dst.window;
    return true;
}

/// Entrega um `mouse_wheel` em `p` (desktop). A roda segue o CURSOR (não
/// a captura). `false` = descartado.
pub fn pushWheel(reg: *const Registry, dx: f32, dy: f32, p: Vec2) ContextError!bool {
    const dst = targetAt(reg, p) orelse return false;
    try dst.ctx.pushEvent(.{ .mouse_wheel = .{ .dx = dx, .dy = dy, .pos = dst.pos } });
    return true;
}

/// `Context` da janela ATIVA que tenha vínculo (`null` = nenhuma janela
/// ativa ou sem contexto). Destino do teclado/texto.
pub fn focusedContext(reg: *const Registry) ?*Context {
    const wid = reg.activeId() orelse return null;
    return reg.contextOf(wid);
}

/// Entrega um `key` à janela ativa. `false` = descartado (sem janela
/// ativa com contexto).
pub fn pushKey(
    reg: *const Registry,
    key: Key,
    pressed: bool,
    modifiers: Modifiers,
) ContextError!bool {
    const ctx = focusedContext(reg) orelse return false;
    try ctx.pushEvent(.{ .key = .{ .key = key, .pressed = pressed, .modifiers = modifiers } });
    return true;
}

/// Entrega um `text` à janela ativa (o contexto valida o codepoint;
/// inválido ⇒ `error.InvalidEvent`). `false` = descartado.
pub fn pushText(reg: *const Registry, codepoint: u32) ContextError!bool {
    const ctx = focusedContext(reg) orelse return false;
    try ctx.pushEvent(.{ .text = .{ .codepoint = codepoint } });
    return true;
}

/// Troca a janela ativa para `wid` e limpa o foco de WIDGET da janela que
/// sai (`Context.clearFocus`), quando muda de fato. `false` se `wid` não
/// existe (nada muda). Não mexe no empilhamento.
pub fn focusWindow(reg: *Registry, wid: Id) bool {
    const prev = reg.activeId();
    if (!reg.activate(wid)) return false;
    if (prev) |p| {
        if (p != wid) {
            if (reg.contextOf(p)) |c| c.clearFocus();
        }
    }
    return true;
}

/// Ativação típica do host ao clicar no desktop: sobe a janela visível
/// sob `p` e troca o foco (`focusWindow`). Devolve o id ativado (`null` =
/// nada sob `p`, sem mexer em ordem nem foco).
pub fn focusAt(reg: *Registry, p: Vec2) ?Id {
    const wid = reg.windowAt(p) orelse return null;
    _ = reg.raise(wid);
    _ = focusWindow(reg, wid);
    return wid;
}

// --- tests ---

const testing = std.testing;
const Rect = types.Rect;

fn winId(name: []const u8) Id {
    return Id.fromString(name);
}

/// Desktop de teste: A embaixo (0..120 x 0..60, com contexto), B em cima
/// (80..200 x 30..90, com contexto) e C sem contexto (200..250 x 0..50).
const Fixture = struct {
    ctx_a: Context = undefined,
    ctx_b: Context = undefined,
    reg: Registry = .{},
    router: Router = .{},
    a: Id = .null,
    b: Id = .null,
    c: Id = .null,

    fn setup(self: *Fixture, allocator: std.mem.Allocator) !void {
        self.ctx_a = try Context.init(allocator, .{ .viewport = Rect.init(0, 0, 120, 60) });
        self.ctx_b = try Context.init(allocator, .{ .viewport = Rect.init(0, 0, 120, 60) });
        self.reg = .{};
        self.router = .{};
        self.a = winId("wi:a");
        self.b = winId("wi:b");
        self.c = winId("wi:c");
        try self.reg.add(self.a, Rect.init(0, 0, 120, 60));
        try self.reg.add(self.b, Rect.init(80, 30, 120, 60));
        try self.reg.add(self.c, Rect.init(200, 0, 50, 50));
        _ = self.reg.bind(self.a, &self.ctx_a);
        _ = self.reg.bind(self.b, &self.ctx_b);
    }

    fn teardown(self: *Fixture) void {
        self.ctx_a.deinit();
        self.ctx_b.deinit();
    }
};

test "window/input: targetAt exige janela visível e com contexto" {
    var fx: Fixture = .{};
    try fx.setup(testing.allocator);
    defer fx.teardown();

    // Sobreposição A/B: vence a de cima (B), com posição LOCAL de B.
    const rb = targetAt(&fx.reg, Vec2.init(100, 40)).?;
    try testing.expectEqual(fx.b, rb.window);
    try testing.expect(rb.ctx == &fx.ctx_b);
    try testing.expectEqual(Vec2.init(20, 10), rb.pos);
    // Só A.
    const ra = targetAt(&fx.reg, Vec2.init(10, 10)).?;
    try testing.expectEqual(fx.a, ra.window);
    try testing.expect(ra.ctx == &fx.ctx_a);
    try testing.expectEqual(Vec2.init(10, 10), ra.pos);
    // C está sob o ponto, mas não tem contexto: nada é entregue (a janela
    // do topo manda; não atravessa para as de baixo).
    try testing.expect(targetAt(&fx.reg, Vec2.init(210, 10)) == null);
    // Fora de todas.
    try testing.expect(targetAt(&fx.reg, Vec2.init(500, 500)) == null);
    // Esconder B: A assume a sobreposição.
    try testing.expect(fx.reg.setVisible(fx.b, false));
    try testing.expectEqual(fx.a, targetAt(&fx.reg, Vec2.init(100, 40)).?.window);
    try testing.expect(fx.reg.setVisible(fx.b, true));
    // Desvincular A: o ponto exclusivo dela deixa de ter destino.
    try testing.expect(fx.reg.unbind(fx.a));
    try testing.expect(targetAt(&fx.reg, Vec2.init(10, 10)) == null);
    try testing.expect(fx.reg.bind(fx.a, &fx.ctx_a));
}

test "window/input: pushButton captura a janela até o release" {
    var fx: Fixture = .{};
    try fx.setup(testing.allocator);
    defer fx.teardown();

    // Release sem captura: descartado (não vai por hit-test).
    try testing.expect(!try pushButton(&fx.router, &fx.reg, .left, false, Vec2.init(100, 40)));
    try testing.expect(!fx.router.isCapturing());

    // Press na sobreposição: vai para B (topo), em coordenadas locais, e
    // B passa a capturar.
    try testing.expect(try pushButton(&fx.router, &fx.reg, .left, true, Vec2.init(100, 40)));
    try testing.expect(fx.router.isCapturing());
    try testing.expectEqual(fx.b, fx.router.press_window.?);
    try testing.expectEqual(@as(usize, 1), fx.ctx_b.pendingEvents().len);
    try testing.expectEqual(Vec2.init(20, 10), fx.ctx_b.mouse_pos.?);
    try testing.expect(fx.ctx_b.mouse_down_left);
    try testing.expectEqual(@as(usize, 0), fx.ctx_a.pendingEvents().len);

    // Arrastar para FORA de B (região só de A): a captura manda — B
    // recebe locais negativos e A não vê nada.
    try testing.expect(try pushMouseMove(&fx.router, &fx.reg, Vec2.init(10, 10)));
    try testing.expectEqual(Vec2.init(-70, -20), fx.ctx_b.mouse_pos.?);
    try testing.expectEqual(@as(usize, 0), fx.ctx_a.pendingEvents().len);

    // Release fora de B: continua indo para a captura, que se encerra.
    try testing.expect(try pushButton(&fx.router, &fx.reg, .left, false, Vec2.init(10, 10)));
    try testing.expect(!fx.router.isCapturing());
    try testing.expect(!fx.ctx_b.mouse_down_left);
    try testing.expectEqual(@as(usize, 3), fx.ctx_b.pendingEvents().len);
    try testing.expectEqual(@as(usize, 0), fx.ctx_a.pendingEvents().len);
    // O release seguinte, sem captura, é descartado.
    try testing.expect(!try pushButton(&fx.router, &fx.reg, .left, false, Vec2.init(10, 10)));
    try testing.expectEqual(@as(usize, 3), fx.ctx_b.pendingEvents().len);
}

test "window/input: move e roda seguem o cursor; captura órfã descarta" {
    var fx: Fixture = .{};
    try fx.setup(testing.allocator);
    defer fx.teardown();

    // Sem captura: o move vai para a janela sob o cursor; sem janela com
    // contexto, é descartado sem mexer no estado retido.
    try testing.expect(try pushMouseMove(&fx.router, &fx.reg, Vec2.init(10, 10)));
    try testing.expectEqual(Vec2.init(10, 10), fx.ctx_a.mouse_pos.?);
    try testing.expect(!try pushMouseMove(&fx.router, &fx.reg, Vec2.init(500, 500)));
    try testing.expectEqual(Vec2.init(10, 10), fx.ctx_a.mouse_pos.?);

    // Press em A captura A; a roda segue o CURSOR e vai para B.
    try testing.expect(try pushButton(&fx.router, &fx.reg, .left, true, Vec2.init(10, 10)));
    try testing.expectEqual(fx.a, fx.router.press_window.?);
    try testing.expect(try pushWheel(&fx.reg, 0, 3, Vec2.init(100, 40)));
    try testing.expectEqual(Vec2.init(20, 10), fx.ctx_b.mouse_pos.?);
    try testing.expectEqual(fx.a, fx.router.press_window.?); // captura intacta
    try testing.expectEqual(@as(usize, 1), fx.ctx_b.pendingEvents().len);
    // Roda sem janela sob o cursor: descartada.
    try testing.expect(!try pushWheel(&fx.reg, 0, 3, Vec2.init(500, 500)));
    try testing.expectEqual(@as(usize, 1), fx.ctx_b.pendingEvents().len);

    // Captura órfã (janela removida no meio do arraste): os eventos são
    // descartados e o release apenas encerra a captura.
    try testing.expect(fx.reg.remove(fx.a));
    try testing.expect(!try pushMouseMove(&fx.router, &fx.reg, Vec2.init(100, 40)));
    try testing.expect(!try pushButton(&fx.router, &fx.reg, .left, false, Vec2.init(100, 40)));
    try testing.expect(!fx.router.isCapturing());

    // `clearCapture` libera sem entregar nada; o press seguinte recaptura.
    try testing.expect(try pushButton(&fx.router, &fx.reg, .left, true, Vec2.init(100, 40)));
    try testing.expect(fx.router.isCapturing());
    fx.router.clearCapture();
    try testing.expect(!fx.router.isCapturing());
}

test "window/input: teclado e texto vão para a janela ativa com contexto" {
    var fx: Fixture = .{};
    try fx.setup(testing.allocator);
    defer fx.teardown();

    // Sem janela ativa: descartado.
    try testing.expect(focusedContext(&fx.reg) == null);
    try testing.expect(!try pushKey(&fx.reg, .enter, true, .{}));
    try testing.expect(!try pushText(&fx.reg, 'a'));

    // Ativa C (sem contexto): teclado segue descartado.
    try testing.expect(fx.reg.activate(fx.c));
    try testing.expect(focusedContext(&fx.reg) == null);
    try testing.expect(!try pushKey(&fx.reg, .enter, true, .{}));

    // Ativa B: teclado/texto entram no contexto de B.
    try testing.expect(fx.reg.activate(fx.b));
    try testing.expect(focusedContext(&fx.reg).? == &fx.ctx_b);
    try testing.expect(try pushKey(&fx.reg, .tab, true, .{ .shift = true }));
    try testing.expect(try pushText(&fx.reg, 'Z'));
    try testing.expectEqual(@as(usize, 2), fx.ctx_b.pendingEvents().len);
    switch (fx.ctx_b.pendingEvents()[0]) {
        .key => |k| {
            try testing.expectEqual(Key.tab, k.key);
            try testing.expect(k.pressed);
            try testing.expect(k.modifiers.shift);
        },
        else => return error.TestUnexpectedResult,
    }
    switch (fx.ctx_b.pendingEvents()[1]) {
        .text => |t| try testing.expectEqual(@as(u32, 'Z'), t.codepoint),
        else => return error.TestUnexpectedResult,
    }
    // Codepoint inválido é rejeitado pelo contexto e não entra na fila.
    try testing.expectError(error.InvalidEvent, pushText(&fx.reg, 0xD800));
    try testing.expectEqual(@as(usize, 2), fx.ctx_b.pendingEvents().len);
    // Nenhum evento chegou ao contexto da outra janela.
    try testing.expectEqual(@as(usize, 0), fx.ctx_a.pendingEvents().len);
}

test "window/input: focusAt sobe, ativa e limpa o foco de widget da que sai" {
    var fx: Fixture = .{};
    try fx.setup(testing.allocator);
    defer fx.teardown();

    // Foco de widget pré-existente em A (como se um text-input tivesse
    // sido clicado) e A ativa.
    const widget = winId("wi:widget");
    fx.ctx_a.focus_owner = widget;
    try testing.expect(fx.ctx_a.hasFocus(widget));
    try testing.expect(fx.reg.activate(fx.a));

    // Clique na sobreposição: B sobe, fica ativa e A perde o foco de
    // widget (não segue "focada" sem receber teclado).
    try testing.expectEqual(fx.b, focusAt(&fx.reg, Vec2.init(100, 40)).?);
    try testing.expectEqual(fx.b, fx.reg.activeId().?);
    try testing.expect(!fx.ctx_a.hasFocus(widget));
    try testing.expectEqual(fx.b, fx.reg.order()[fx.reg.count() - 1].id);

    // Reativar a MESMA janela não limpa o foco de widget dela.
    fx.ctx_b.focus_owner = widget;
    try testing.expectEqual(fx.b, focusAt(&fx.reg, Vec2.init(100, 40)).?);
    try testing.expect(fx.ctx_b.hasFocus(widget));

    // Clique no vazio ou em janela inexistente: nada muda.
    try testing.expect(focusAt(&fx.reg, Vec2.init(500, 500)) == null);
    try testing.expectEqual(fx.b, fx.reg.activeId().?);
    try testing.expect(!focusWindow(&fx.reg, winId("wi:missing")));
    try testing.expectEqual(fx.b, fx.reg.activeId().?);

    // `focusWindow` em C (sem contexto) ativa sem evento algum e B perde
    // o foco de widget.
    try testing.expect(focusWindow(&fx.reg, fx.c));
    try testing.expectEqual(fx.c, fx.reg.activeId().?);
    try testing.expect(!fx.ctx_b.hasFocus(widget));
    try testing.expectEqual(@as(usize, 0), fx.ctx_a.pendingEvents().len);
    try testing.expectEqual(@as(usize, 0), fx.ctx_b.pendingEvents().len);
}
