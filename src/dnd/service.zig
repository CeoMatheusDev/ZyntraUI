//! ZyntraUI — arrastar-e-soltar (dnd/service).
//!
//! Serviço por janela que vive no `Context` (campo `dnd`), no mesmo
//! espírito de `press_owner`/`focus_owner`: estado compartilhado entre
//! widgets, sem alocação e independente de backend.
//!
//! Fluxo típico por frame:
//! 1. A ORIGEM, depois de capturar o press (`press_owner`) e mover além
//!    do próprio limiar, chama `begin` com o payload.
//! 2. Cada ALVO candidato chama `accept(ctx, id, bounds)` todo frame: o
//!    serviço registra o alvo sob o cursor (último registrado vence,
//!    isto é, o desenhado por cima) e devolve `.hover` para realce.
//! 3. No release, o `Context.beginFrame` seguinte resolve o solto contra
//!    o alvo registrado no frame anterior: `lastDrop` fica disponível por
//!    UM frame (com `target == null` quando não havia alvo) e o alvo
//!    escolhido recebe `.dropped` do seu `accept` nesse frame.
//! 4. `cancel` (tipicamente ligado ao Esc pela origem) encerra o arraste
//!    sem alvo, marcando `Drop.cancelled`.
//!
//! Ownership: `Payload` é EMPRESTADO — `kind`/`label` devem continuar
//! válidos enquanto o arraste durar (literais ou estado do chamador);
//! `data` nunca é dereferenciado pela biblioteca. Nada é copiado nem
//! alocado.
//!
//! Nota de ordem de desenho: `accept` precisa ser chamado em todos os
//! alvos do frame (mesmo sem arraste ativo, para receber `.dropped`).

const std = @import("std");
const types = @import("../core/types.zig");
const id_mod = @import("../core/id.zig");
const context_mod = @import("../core/context.zig");

const Id = id_mod.Id;
const Context = context_mod.Context;
const ContextError = context_mod.ContextError;

/// Dados carregados pelo arraste (emprestados).
pub const Payload = struct {
    /// Identificador do tipo (ex.: "node", "tab"): não vazio e UTF-8.
    /// É o contrato entre origem e alvo.
    kind: []const u8,
    /// Objeto do chamador (opaco; a lib nunca dereferencia).
    data: ?*const anyopaque = null,
    /// Rótulo do fantasma do arraste (vazio ⇒ usa `kind`).
    label: []const u8 = "",

    pub fn isValid(self: Payload) bool {
        if (self.kind.len == 0) return false;
        if (!std.unicode.utf8ValidateSlice(self.kind)) return false;
        if (self.label.len > 0 and !std.unicode.utf8ValidateSlice(self.label)) return false;
        return true;
    }

    /// Rótulo efetivo do arraste (`label` ou `kind`).
    pub fn displayLabel(self: Payload) []const u8 {
        return if (self.label.len > 0) self.label else self.kind;
    }
};

/// Resultado de um solto (válido por um frame em `lastDrop`).
pub const Drop = struct {
    /// Alvo que recebeu (`null` = solto fora de qualquer alvo).
    target: ?Id = null,
    /// Origem do arraste.
    source: ?Id = null,
    /// Payload arrastado.
    payload: Payload,
    /// `true` quando o arraste foi cancelado explicitamente (`cancel`).
    cancelled: bool = false,

    /// `true` quando o alvo `id` recebeu este solto.
    pub fn isFor(self: Drop, id: Id) bool {
        if (self.cancelled) return false;
        const t = self.target orelse return false;
        return t == id;
    }
};

/// Verdicto de um alvo no frame.
pub const AcceptResult = enum {
    /// Sem arraste sobre este alvo (ou sem arraste ativo).
    none,
    /// O arraste ativo está sobre `bounds`.
    hover,
    /// Este alvo recebeu o solto resolvido no frame.
    dropped,
};

/// Estado do serviço (por janela; vive no `Context`).
pub const State = struct {
    /// Payload do arraste ativo (`null` = sem arraste).
    payload: ?Payload = null,
    /// Id da origem do arraste.
    source: ?Id = null,
    /// Posição onde o arraste começou.
    origin: types.Vec2 = .{},
    /// Última posição conhecida do arraste.
    pos: types.Vec2 = .{},
    /// Alvo sob o cursor registrado neste frame (último vence).
    hover: ?Id = null,
    /// Solto resolvido no frame (`null` = nenhum).
    last_drop: ?Drop = null,
    /// Arrastes iniciados.
    started: u64 = 0,
    /// Arrastes concluídos (solto, com ou sem alvo, ou cancelamento).
    completed: u64 = 0,

    pub fn isDragging(self: State) bool {
        return self.payload != null;
    }

    /// Hook do `Context.beginFrame`: expira o resultado do frame anterior
    /// e resolve o solto do arraste ativo quando o botão já não está
    /// pressionado, contra o alvo registrado no frame anterior. Depois
    /// limpa o registro de alvos (reconstruído por `accept` no frame).
    pub fn beginFrame(self: *State, mouse_down: bool) void {
        self.last_drop = null;
        if (self.payload) |p| {
            if (!mouse_down) {
                self.last_drop = .{
                    .target = self.hover,
                    .source = self.source,
                    .payload = p,
                };
                self.completed += 1;
                self.payload = null;
                self.source = null;
            }
        }
        self.hover = null;
    }
};

/// `true` se há arraste ativo.
pub fn isDragging(ctx: *const Context) bool {
    return ctx.dnd.isDragging();
}

/// Payload do arraste ativo.
pub fn payload(ctx: *const Context) ?Payload {
    return ctx.dnd.payload;
}

/// Id da origem do arraste ativo.
pub fn dragSource(ctx: *const Context) ?Id {
    return ctx.dnd.source;
}

/// Posição de tela atual do arraste (cursor conhecido; senão a última).
pub fn dragPosition(ctx: *const Context) types.Vec2 {
    return ctx.mouse_pos orelse ctx.dnd.pos;
}

/// Posição onde o arraste começou.
pub fn dragOrigin(ctx: *const Context) types.Vec2 {
    return ctx.dnd.origin;
}

/// Distância percorrida desde o início do arraste (0 sem arraste).
pub fn dragDistance(ctx: *const Context) f32 {
    if (ctx.dnd.payload == null) return 0;
    const p = dragPosition(ctx);
    const dx = p.x - ctx.dnd.origin.x;
    const dy = p.y - ctx.dnd.origin.y;
    const d = std.math.sqrt(dx * dx + dy * dy);
    return if (std.math.isFinite(d)) d else 0;
}

/// `true` quando a distância percorrida excede `px`
/// (`px` não-finito ou negativo ⇒ `false`).
pub fn dragExceeds(ctx: *const Context, px: f32) bool {
    if (!std.math.isFinite(px) or px < 0) return false;
    return dragDistance(ctx) > px;
}

/// Inicia um arraste com `payload` a partir de `id` (a origem deve já
/// deter a captura de press). Erros: `id` nulo, payload inválido,
/// arraste já em andamento ou cursor desconhecido.
pub fn begin(ctx: *Context, id: Id, pay: Payload) ContextError!void {
    if (id.isNull() or !pay.isValid()) return error.InvalidArgument;
    if (ctx.dnd.payload != null) return error.InvalidArgument;
    const p = ctx.mouse_pos orelse return error.InvalidArgument;
    ctx.dnd.payload = pay;
    ctx.dnd.source = id;
    ctx.dnd.origin = p;
    ctx.dnd.pos = p;
    ctx.dnd.hover = null;
    ctx.dnd.last_drop = null;
    ctx.dnd.started += 1;
}

/// Cancela o arraste ativo (sem alvo). Sem arraste, não tem efeito
/// (o último resultado permanece até o próximo `beginFrame`).
pub fn cancel(ctx: *Context) void {
    if (ctx.dnd.payload) |p| {
        ctx.dnd.last_drop = .{
            .target = null,
            .source = ctx.dnd.source,
            .payload = p,
            .cancelled = true,
        };
        ctx.dnd.completed += 1;
    }
    ctx.dnd.payload = null;
    ctx.dnd.source = null;
    ctx.dnd.hover = null;
}

/// Registra `id` como alvo candidato neste frame e devolve o verdicto.
/// `bounds` devem ser finitos (inválidos ⇒ `.none`); `id` nulo ⇒ `.none`.
/// Chamar todo frame, mesmo com o alvo invisível.
pub fn accept(ctx: *Context, id: Id, bounds: types.Rect) AcceptResult {
    if (id.isNull()) return .none;
    if (ctx.dnd.payload != null) {
        const p = ctx.mouse_pos orelse return .none;
        ctx.dnd.pos = p;
        if (bounds.contains(p)) {
            ctx.dnd.hover = id;
            return .hover;
        }
        return .none;
    }
    const d = ctx.dnd.last_drop orelse return .none;
    if (d.isFor(id)) return .dropped;
    return .none;
}

/// Solto resolvido neste frame (`null` = nenhum).
pub fn lastDrop(ctx: *const Context) ?Drop {
    return ctx.dnd.last_drop;
}

/// Payload recebido por `id` no solto resolvido neste frame.
pub fn droppedOn(ctx: *const Context, id: Id) ?Payload {
    const d = ctx.dnd.last_drop orelse return null;
    if (!d.isFor(id)) return null;
    return d.payload;
}

/// Alvo sob o cursor registrado neste frame (`null` = nenhum).
pub fn hoverTarget(ctx: *const Context) ?Id {
    return ctx.dnd.hover;
}

// --- tests ---

const testing = std.testing;

fn testContext() !Context {
    return try Context.init(testing.allocator, .{
        .viewport = types.Rect.init(0, 0, 200, 100),
    });
}

fn testPayload() Payload {
    return .{ .kind = "chip", .label = "chip" };
}

test "dnd: Payload valida tipo/rótulo e displayLabel" {
    try testing.expect(testPayload().isValid());
    try testing.expectEqualStrings("chip", testPayload().displayLabel());
    // Rótulo vazio cai no tipo.
    try testing.expectEqualStrings("node", (Payload{ .kind = "node" }).displayLabel());
    // Tipo vazio, tipos/rótulos não-UTF8 e rótulo vazio são tratados.
    try testing.expect(!(Payload{ .kind = "" }).isValid());
    try testing.expect(!(Payload{ .kind = &[_]u8{0xff} }).isValid());
    try testing.expect(!(Payload{ .kind = "n", .label = &[_]u8{ 0xc3, 0x28 } }).isValid());
    try testing.expect((Payload{ .kind = "nó", .label = "arrastável" }).isValid());
}

test "dnd: begin valida entradas e registra origem/payload" {
    var ctx = try testContext();
    defer ctx.deinit();
    const src = Id.fromString("dnd:src");
    const pay = testPayload();

    ctx.beginFrame();
    // Cursor desconhecido ⇒ sem arraste.
    try testing.expectError(error.InvalidArgument, begin(&ctx, src, pay));
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(10, 20) } });
    try testing.expectError(error.InvalidArgument, begin(&ctx, .null, pay));
    try testing.expectError(error.InvalidArgument, begin(&ctx, src, .{ .kind = "" }));
    try testing.expect(!isDragging(&ctx));
    try testing.expect(!ctx.dnd.isDragging());

    try begin(&ctx, src, pay);
    try testing.expect(isDragging(&ctx));
    try testing.expectEqual(src, dragSource(&ctx).?);
    try testing.expectEqual(pay, payload(&ctx).?);
    try testing.expectEqual(types.Vec2.init(10, 20), dragOrigin(&ctx));
    try testing.expectEqual(types.Vec2.init(10, 20), dragPosition(&ctx));
    try testing.expectEqual(@as(f32, 0), dragDistance(&ctx));
    try testing.expectEqual(@as(u64, 1), ctx.dnd.started);
    try testing.expectEqual(@as(u64, 0), ctx.dnd.completed);
    // Arraste já ativo ⇒ erro (sem sobrescrever o payload).
    try testing.expectError(error.InvalidArgument, begin(&ctx, src, .{ .kind = "other" }));
    try testing.expectEqual(pay, payload(&ctx).?);
    ctx.endFrame();
}

test "dnd: accept registra alvos sob o cursor (último desenhado vence)" {
    var ctx = try testContext();
    defer ctx.deinit();
    const src = Id.fromString("dnd:src");
    const pay = testPayload();
    const a = types.Rect.init(40, 10, 40, 20);
    const b = types.Rect.init(45, 15, 40, 20);
    const far = types.Rect.init(0, 0, 10, 10);
    const id_a = Id.fromString("dnd:a");
    const id_b = Id.fromString("dnd:b");
    const id_far = Id.fromString("dnd:far");

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(50, 20),
    } });
    try begin(&ctx, src, pay);
    // Sem arraste, o verdicto é `.none`.
    try testing.expectEqual(AcceptResult.none, accept(&ctx, id_far, far));
    // Alvo fora do cursor não registra e não mexe no hover.
    try testing.expectEqual(AcceptResult.none, accept(&ctx, id_far, far));
    try testing.expect(hoverTarget(&ctx) == null);
    // Sobrepostos: o último registrado vence.
    try testing.expectEqual(AcceptResult.hover, accept(&ctx, id_a, a));
    try testing.expectEqual(id_a, hoverTarget(&ctx).?);
    try testing.expectEqual(AcceptResult.hover, accept(&ctx, id_b, b));
    try testing.expectEqual(id_b, hoverTarget(&ctx).?);
    // Registro anterior permanece até outro alvo sob o cursor.
    try testing.expectEqual(AcceptResult.none, accept(&ctx, id_far, far));
    try testing.expectEqual(id_b, hoverTarget(&ctx).?);
    // Id nulo e bounds inválidos ⇒ `.none`.
    try testing.expectEqual(AcceptResult.none, accept(&ctx, .null, b));
    try testing.expectEqual(AcceptResult.none, accept(&ctx, id_a, types.Rect.init(
        0,
        0,
        std.math.nan(f32),
        10,
    )));
    ctx.endFrame();
}

test "dnd: solto resolve no beginFrame seguinte e dura um frame" {
    var ctx = try testContext();
    defer ctx.deinit();
    const src = Id.fromString("dnd:src");
    const target = Id.fromString("dnd:target");
    const other = Id.fromString("dnd:other");
    const pay = testPayload();
    const bounds = types.Rect.init(40, 10, 40, 20);

    // Frame 1: press, início do arraste e alvo sob o cursor.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(50, 20),
    } });
    try begin(&ctx, src, pay);
    try testing.expectEqual(AcceptResult.hover, accept(&ctx, target, bounds));
    try testing.expect(lastDrop(&ctx) == null);
    ctx.endFrame();

    // Frame 2: release; o alvo ainda registra hover (arraste vivo).
    ctx.beginFrame();
    try testing.expect(isDragging(&ctx));
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(50, 20),
    } });
    try testing.expectEqual(AcceptResult.hover, accept(&ctx, target, bounds));
    try testing.expect(lastDrop(&ctx) == null);
    ctx.endFrame();

    // Frame 3: resolução no beginFrame; o alvo recebe `.dropped`.
    ctx.beginFrame();
    try testing.expect(!isDragging(&ctx));
    const d = lastDrop(&ctx).?;
    try testing.expectEqual(target, d.target.?);
    try testing.expectEqual(src, d.source.?);
    try testing.expectEqual(pay, d.payload);
    try testing.expect(!d.cancelled);
    try testing.expect(d.isFor(target));
    try testing.expect(!d.isFor(other));
    try testing.expectEqual(@as(u64, 1), ctx.dnd.completed);
    try testing.expectEqual(AcceptResult.dropped, accept(&ctx, target, bounds));
    try testing.expectEqual(pay, droppedOn(&ctx, target).?);
    try testing.expect(droppedOn(&ctx, other) == null);
    try testing.expectEqual(AcceptResult.none, accept(&ctx, other, bounds));
    ctx.endFrame();

    // Frame 4: o resultado expira.
    ctx.beginFrame();
    try testing.expect(lastDrop(&ctx) == null);
    try testing.expect(droppedOn(&ctx, target) == null);
    try testing.expectEqual(AcceptResult.none, accept(&ctx, target, bounds));
    ctx.endFrame();
}

test "dnd: solto fora de qualquer alvo resolve com target nulo" {
    var ctx = try testContext();
    defer ctx.deinit();
    const src = Id.fromString("dnd:src");
    const target = Id.fromString("dnd:target");
    const pay = testPayload();
    const bounds = types.Rect.init(40, 10, 40, 20);

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(5, 5),
    } });
    try begin(&ctx, src, pay);
    try testing.expectEqual(AcceptResult.none, accept(&ctx, target, bounds));
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(5, 5),
    } });
    try testing.expectEqual(AcceptResult.none, accept(&ctx, target, bounds));
    ctx.endFrame();

    ctx.beginFrame();
    const d = lastDrop(&ctx).?;
    try testing.expect(d.target == null);
    try testing.expectEqual(src, d.source.?);
    try testing.expect(!d.cancelled);
    try testing.expect(!d.isFor(target));
    try testing.expectEqual(@as(u64, 1), ctx.dnd.completed);
    try testing.expectEqual(AcceptResult.none, accept(&ctx, target, bounds));
    ctx.endFrame();
}

test "dnd: cancel encerra sem alvo e marca cancelled" {
    var ctx = try testContext();
    defer ctx.deinit();
    const src = Id.fromString("dnd:src");
    const target = Id.fromString("dnd:target");
    const pay = testPayload();
    const bounds = types.Rect.init(40, 10, 40, 20);

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(50, 20),
    } });
    try begin(&ctx, src, pay);
    try testing.expectEqual(AcceptResult.hover, accept(&ctx, target, bounds));
    ctx.endFrame();

    ctx.beginFrame();
    cancel(&ctx);
    try testing.expect(!isDragging(&ctx));
    const d = lastDrop(&ctx).?;
    try testing.expect(d.cancelled);
    try testing.expect(d.target == null);
    try testing.expectEqual(src, d.source.?);
    try testing.expectEqual(pay, d.payload);
    try testing.expect(!d.isFor(target));
    try testing.expectEqual(@as(u64, 1), ctx.dnd.completed);
    // Cancelado nunca entrega payload.
    try testing.expectEqual(AcceptResult.none, accept(&ctx, target, bounds));
    try testing.expect(droppedOn(&ctx, target) == null);
    // Cancelar de novo não tem efeito.
    cancel(&ctx);
    try testing.expect(lastDrop(&ctx).?.cancelled);
    try testing.expectEqual(@as(u64, 1), ctx.dnd.completed);
    ctx.endFrame();

    ctx.beginFrame();
    try testing.expect(lastDrop(&ctx) == null);
    ctx.endFrame();
}

test "dnd: distância percorrida e limiar" {
    var ctx = try testContext();
    defer ctx.deinit();
    const src = Id.fromString("dnd:src");
    const pay = testPayload();

    ctx.beginFrame();
    // Sem arraste: distância 0 e limiar nunca excedido.
    try testing.expectEqual(@as(f32, 0), dragDistance(&ctx));
    try testing.expect(!dragExceeds(&ctx, 0));
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(10, 10),
    } });
    try begin(&ctx, src, pay);
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(13, 14) } });
    try testing.expectEqual(@as(f32, 5), dragDistance(&ctx));
    try testing.expectEqual(types.Vec2.init(13, 14), dragPosition(&ctx));
    try testing.expect(dragExceeds(&ctx, 4));
    try testing.expect(!dragExceeds(&ctx, 5));
    try testing.expect(!dragExceeds(&ctx, std.math.nan(f32)));
    try testing.expect(!dragExceeds(&ctx, -1));
    ctx.endFrame();
}
