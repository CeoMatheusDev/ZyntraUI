//! ZyntraUI — contexto GUI (core/context).
//!
//! Ownership:
//! - O chamador fornece `allocator`; o `Context` apenas o retém
//!   (não assume ownership do alocador).
//! - `Context.deinit` libera buffers internos (eventos + draw).
//!   `allocator` continua do chamador.
//! Lifetime:
//! - `init` → `beginFrame`/`endFrame` (0..N) → `deinit`.
//! - `beginFrame` invalida eventos e comandos do frame anterior
//!   (retém capacidade). Slices obtidos via `events()`/`drawCommands()`
//!   valem apenas até o próximo `beginFrame`/`deinit`.
//! - Mover o `Context` por valor invalida ponteiros internos
//!   futuros; usar ponteiro estável após `init`.
//! Erros:
//! - `init` valida a config (`InvalidArgument`) e não aloca
//!   (listas iniciam vazias). `pushEvent`/`draw.*` podem retornar
//!   `OutOfMemory`; eventos/comandos inválidos retornam
//!   `InvalidEvent`/`InvalidCommand`.

const std = @import("std");
const types = @import("types.zig");
const id_mod = @import("id.zig");
const event_mod = @import("../event/event.zig");
const draw_mod = @import("../draw/commands.zig");
const dnd_mod = @import("../dnd/service.zig");

/// Erros públicos do contexto (M1+M2).
pub const ContextError = error{
    InvalidArgument,
    OutOfMemory,
    InvalidEvent,
    InvalidCommand,
};

/// Configuração de criação do contexto.
pub const ContextConfig = struct {
    /// Viewport inicial em pixels lógicos.
    viewport: types.Rect = .{},
    /// Capacidade inicial reservada para widgets (M2+; M1 apenas valida).
    /// Deve ser <= max_widget_capacity.
    initial_widget_capacity: u32 = 256,
    max_widget_capacity: u32 = 65536,
};

/// Estado do frame.
pub const FrameState = enum {
    idle,
    active,
};

/// Direção de avanço de foco (Tab / Shift+Tab).
pub const FocusDirection = enum {
    next,
    prev,
};

/// Contexto raiz da GUI. Um por aplicação/janela na M1.
pub const Context = struct {
    allocator: std.mem.Allocator,
    viewport: types.Rect,
    frame_index: u64,
    state: FrameState,
    events: event_mod.EventQueue,
    draw: draw_mod.DrawList,
    /// Última posição conhecida do mouse (retida entre frames).
    mouse_pos: ?types.Vec2 = null,
    /// Botão esquerdo atualmente pressionado (retido entre frames).
    mouse_down_left: bool = false,
    /// Id com captura de press ativa (release-to-activate, M7).
    /// Exclusivo: só o dono recebe o release. Limpo no release,
    /// em `clearPressCapture` ou `deinit`. Widgets inativos devem ser
    /// sondados todo frame — captura órfã bloqueia outros widgets.
    press_owner: ?id_mod.Id = null,
    /// Id com foco de teclado (M9, ex.: text-input). `null` = ninguém.
    /// Click em widget focável assume o foco; `Escape` ou
    /// `clearFocus` liberam. Retido entre frames como o mouse.
    focus_owner: ?id_mod.Id = null,
    /// Focáveis registrados no frame anterior, em ordem de registro
    /// (ordem de chamada dos widgets). Recontruído a cada frame.
    focusables: std.ArrayList(id_mod.Id),
    /// Avanço de foco pendente (Tab), aplicado no próximo `beginFrame`
    /// sobre o registro COMPLETO do frame anterior. Widgets nunca
    /// avançam direto (registro do frame atual ainda incompleto).
    pending_focus_advance: ?FocusDirection = null,
    /// Serviço de arrastar-e-soltar (M97): payload ativo, alvos
    /// registrados no frame e resultado do último solto. O `beginFrame`
    /// resolve o solto do frame anterior. Ver `dnd/service`.
    dnd: dnd_mod.State = .{},

    const Self = @This();

    /// Cria o contexto. Valida a config; listas iniciam vazias
    /// (sem alocação) para `init` nunca falhar por OOM.
    pub fn init(allocator: std.mem.Allocator, config: ContextConfig) ContextError!Self {
        if (!std.math.isFinite(config.viewport.x) or !std.math.isFinite(config.viewport.y) or
            !std.math.isFinite(config.viewport.w) or !std.math.isFinite(config.viewport.h))
        {
            return error.InvalidArgument;
        }
        if (config.viewport.w < 0 or config.viewport.h < 0) {
            return error.InvalidArgument;
        }
        if (config.initial_widget_capacity == 0) {
            return error.InvalidArgument;
        }
        if (config.initial_widget_capacity > config.max_widget_capacity) {
            return error.InvalidArgument;
        }
        return .{
            .allocator = allocator,
            .viewport = config.viewport,
            .frame_index = 0,
            .state = .idle,
            .events = event_mod.EventQueue.initEmpty(),
            .draw = draw_mod.DrawList.initEmpty(),
            .focusables = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit(self.allocator);
        self.draw.deinit(self.allocator);
        self.focusables.deinit(self.allocator);
        self.events = event_mod.EventQueue.initEmpty();
        self.draw = draw_mod.DrawList.initEmpty();
        self.focusables = .empty;
        self.state = .idle;
        self.frame_index = 0;
        self.mouse_pos = null;
        self.mouse_down_left = false;
        self.press_owner = null;
        self.focus_owner = null;
        self.pending_focus_advance = null;
        self.dnd = .{};
    }

    /// Inicia um novo frame: aplica avanço de foco pendente (sobre o
    /// registro do frame anterior) e limpa eventos/draw/focáveis do
    /// frame anterior (retendo capacidade). Deve ser pareado com `endFrame`.
    /// Precondição: nenhum frame ativo.
    pub fn beginFrame(self: *Self) void {
        std.debug.assert(self.state == .idle);
        self.state = .active;
        if (self.pending_focus_advance) |dir| {
            self.applyFocusAdvance(dir);
            self.pending_focus_advance = null;
        }
        self.dnd.beginFrame(self.mouse_down_left);
        self.events.clearRetainingCapacity();
        self.draw.clearRetainingCapacity();
        self.focusables.clearRetainingCapacity();
    }

    /// Encerra o frame atual e avança `frame_index` com wrap seguro.
    /// Precondição: frame ativo.
    pub fn endFrame(self: *Self) void {
        std.debug.assert(self.state == .active);
        self.state = .idle;
        self.frame_index +%= 1;
    }

    pub fn isFrameActive(self: *const Self) bool {
        return self.state == .active;
    }

    /// Enfileira um evento no frame atual. Aceita fora de frame
    /// (para adaptadores que coletam antes de `beginFrame`), mas o
    /// padrão é enfileirar entre `beginFrame`/`endFrame`.
    /// Atualiza `mouse_pos`/`mouse_down_left` (estado retido entre
    /// frames; `beginFrame` NÃO limpa — só a fila).
    pub fn pushEvent(self: *Self, ev: event_mod.Event) ContextError!void {
        self.events.push(self.allocator, ev) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidEvent => return error.InvalidEvent,
        };
        switch (ev) {
            .mouse_move => |m| self.mouse_pos = m.pos,
            .mouse_wheel => |w| self.mouse_pos = w.pos,
            .mouse_button => |b| {
                self.mouse_pos = b.pos;
                if (b.button == .left) self.mouse_down_left = b.pressed;
            },
            else => {},
        }
    }

    /// Libera captura de press órfã (ex.: widget sumiu, foco perdido).
    pub fn clearPressCapture(self: *Self) void {
        self.press_owner = null;
    }

    /// Libera o foco de teclado (ex.: click fora, troca de tela).
    pub fn clearFocus(self: *Self) void {
        self.focus_owner = null;
    }

    pub fn hasFocus(self: *const Self, id: id_mod.Id) bool {
        return self.focus_owner == id;
    }

    /// Registra um id focável na ordem de chamada (deduplicado, O(n)
    /// — n de focáveis por frame é pequeno). Widgets focáveis chamam
    /// todo frame, mesmo sem foco.
    pub fn registerFocusable(self: *Self, id: id_mod.Id) ContextError!void {
        if (id.isNull()) return error.InvalidArgument;
        for (self.focusables.items) |reg| {
            if (reg == id) return;
        }
        self.focusables.append(self.allocator, id) catch return error.OutOfMemory;
    }

    /// Agenda avanço de foco para o próximo `beginFrame`. Chamado por
    /// widgets ao ver Tab (nunca avançam direto).
    pub fn requestFocusAdvance(self: *Self, dir: FocusDirection) void {
        self.pending_focus_advance = dir;
    }

    fn applyFocusAdvance(self: *Self, dir: FocusDirection) void {
        const regs = self.focusables.items;
        if (regs.len == 0) return;
        var idx: ?usize = null;
        if (self.focus_owner) |cur| {
            for (regs, 0..) |reg, i| {
                if (reg == cur) {
                    idx = i;
                    break;
                }
            }
        }
        const next: usize = if (idx) |i| switch (dir) {
            .next => (i + 1) % regs.len,
            .prev => (i + regs.len - 1) % regs.len,
        } else switch (dir) {
            .next => 0,
            .prev => regs.len - 1,
        };
        self.focus_owner = regs[next];
    }

    pub fn pendingEvents(self: *const Self) []const event_mod.Event {
        return self.events.items();
    }

    pub fn drawCommands(self: *const Self) []const draw_mod.DrawCommand {
        return self.draw.items();
    }

    pub fn setViewport(self: *Self, viewport: types.Rect) ContextError!void {
        if (!std.math.isFinite(viewport.x) or !std.math.isFinite(viewport.y) or
            !std.math.isFinite(viewport.w) or !std.math.isFinite(viewport.h))
        {
            return error.InvalidArgument;
        }
        if (viewport.w < 0 or viewport.h < 0) return error.InvalidArgument;
        self.viewport = viewport;
    }
};

test "Context ciclo de vida mínimo" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();
    try std.testing.expect(!ctx.isFrameActive());
    try std.testing.expectEqual(@as(u64, 0), ctx.frame_index);
    ctx.beginFrame();
    try std.testing.expect(ctx.isFrameActive());
    ctx.endFrame();
    try std.testing.expect(!ctx.isFrameActive());
    try std.testing.expectEqual(@as(u64, 1), ctx.frame_index);
}

test "Context rejeita config inválida" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.InvalidArgument,
        Context.init(allocator, .{ .viewport = types.Rect.init(0, 0, -1, 600) }),
    );
    try std.testing.expectError(
        error.InvalidArgument,
        Context.init(allocator, .{ .initial_widget_capacity = 0 }),
    );
    try std.testing.expectError(
        error.InvalidArgument,
        Context.init(allocator, .{ .initial_widget_capacity = 10, .max_widget_capacity = 5 }),
    );
}

test "Context.setViewport valida" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();
    try ctx.setViewport(types.Rect.init(0, 0, 1280, 720));
    try std.testing.expectEqual(@as(f32, 1280), ctx.viewport.w);
    try std.testing.expectError(
        error.InvalidArgument,
        ctx.setViewport(types.Rect.init(0, 0, -10, 10)),
    );
}

test "Context M2: eventos + draw por frame" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(10, 20) } });
    try ctx.pushEvent(.quit);
    try std.testing.expectEqual(@as(usize, 2), ctx.pendingEvents().len);
    try ctx.draw.rectFilled(ctx.allocator, types.Rect.init(0, 0, 100, 20), types.Color.rgb(200, 0, 0));
    try std.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    ctx.endFrame();

    // Novo frame limpa e retém capacidade.
    const ev_cap = ctx.events.list.capacity;
    const draw_cap = ctx.draw.list.capacity;
    ctx.beginFrame();
    try std.testing.expectEqual(@as(usize, 0), ctx.pendingEvents().len);
    try std.testing.expectEqual(@as(usize, 0), ctx.drawCommands().len);
    try std.testing.expect(ctx.events.list.capacity >= ev_cap);
    try std.testing.expect(ctx.draw.list.capacity >= draw_cap);
    ctx.endFrame();

    // Evento inválido é rejeitado sem corromper a fila.
    ctx.beginFrame();
    try std.testing.expectError(error.InvalidEvent, ctx.pushEvent(.{
        .text = .{ .codepoint = 0x110000 },
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.pendingEvents().len);
    ctx.endFrame();
}

test "Context M7: mouse retido entre frames + captura" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();
    try std.testing.expect(ctx.mouse_pos == null);
    try std.testing.expect(!ctx.mouse_down_left);

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(7, 8) } });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(7, 8) },
    });
    ctx.endFrame();

    // Fila limpou, estado reteve.
    ctx.beginFrame();
    try std.testing.expectEqual(@as(usize, 0), ctx.pendingEvents().len);
    try std.testing.expectEqual(types.Vec2.init(7, 8), ctx.mouse_pos.?);
    try std.testing.expect(ctx.mouse_down_left);
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(7, 8) },
    });
    try std.testing.expect(!ctx.mouse_down_left);
    ctx.endFrame();

    ctx.press_owner = @import("id.zig").Id.fromString("x");
    ctx.clearPressCapture();
    try std.testing.expect(ctx.press_owner == null);
    ctx.focus_owner = @import("id.zig").Id.fromString("y");
    try std.testing.expect(ctx.hasFocus(@import("id.zig").Id.fromString("y")));
    try std.testing.expect(!ctx.hasFocus(@import("id.zig").Id.fromString("z")));
    ctx.clearFocus();
    try std.testing.expect(ctx.focus_owner == null);
}

test "Context M12: registro de focáveis + avanço com wrap" {
    const idz = @import("id.zig");
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();
    const a = idz.Id.fromString("a");
    const b = idz.Id.fromString("b");

    // Registro vazio: avanço é no-op (e o pendente é consumido).
    ctx.beginFrame();
    ctx.requestFocusAdvance(.next);
    ctx.endFrame();
    ctx.beginFrame();
    try std.testing.expect(ctx.focus_owner == null);
    try std.testing.expectError(error.InvalidArgument, ctx.registerFocusable(.null));
    ctx.endFrame();

    // Ciclo: no frame N registra + pede; beginFrame N+1 aplica.
    // F1: registra [a,b], pede next. F2 aplica → a (sem foco prévio).
    ctx.beginFrame();
    try ctx.registerFocusable(a);
    try ctx.registerFocusable(b);
    try ctx.registerFocusable(a); // dedupe
    try std.testing.expectEqual(@as(usize, 2), ctx.focusables.items.len);
    ctx.requestFocusAdvance(.next);
    ctx.endFrame();
    ctx.beginFrame();
    try std.testing.expect(ctx.focus_owner == a);
    try ctx.registerFocusable(a);
    try ctx.registerFocusable(b);
    ctx.requestFocusAdvance(.next);
    ctx.endFrame();
    ctx.beginFrame(); // → b
    try std.testing.expect(ctx.focus_owner == b);
    try ctx.registerFocusable(a);
    try ctx.registerFocusable(b);
    ctx.requestFocusAdvance(.next);
    ctx.endFrame();
    ctx.beginFrame(); // wrap → a
    try std.testing.expect(ctx.focus_owner == a);
    try ctx.registerFocusable(a);
    try ctx.registerFocusable(b);
    ctx.requestFocusAdvance(.prev); // Shift+Tab
    ctx.endFrame();
    ctx.beginFrame(); // → b
    try std.testing.expect(ctx.focus_owner == b);
    ctx.endFrame();
}

test "Context M12b: viewport não-finita, foco órfão e Tab único" {
    const idz = @import("id.zig");
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();
    const a = idz.Id.fromString("a");
    const b = idz.Id.fromString("b");

    // Viewport NaN: init e setViewport rejeitam sem efeito.
    try std.testing.expectError(
        error.InvalidArgument,
        Context.init(allocator, .{ .viewport = types.Rect.init(0, 0, std.math.nan(f32), 600) }),
    );
    try std.testing.expectError(
        error.InvalidArgument,
        ctx.setViewport(types.Rect.init(std.math.inf(f32), 0, 800, 600)),
    );
    try std.testing.expectEqual(types.Rect.init(0, 0, 0, 0), ctx.viewport);

    // Foco em id fora do registro: avanço cai no primeiro/último.
    ctx.focus_owner = idz.Id.fromString("sumiu");
    ctx.beginFrame();
    try ctx.registerFocusable(a);
    try ctx.registerFocusable(b);
    ctx.requestFocusAdvance(.next);
    ctx.endFrame();
    ctx.beginFrame();
    try std.testing.expect(ctx.focus_owner == a);
    try ctx.registerFocusable(a);
    try ctx.registerFocusable(b);
    ctx.focus_owner = idz.Id.fromString("sumiu");
    ctx.requestFocusAdvance(.prev);
    ctx.endFrame();
    ctx.beginFrame();
    try std.testing.expect(ctx.focus_owner == b);
    ctx.endFrame();

    // Slot único de avanço: último Tab do frame vence.
    ctx.beginFrame();
    try ctx.registerFocusable(a);
    try ctx.registerFocusable(b);
    ctx.requestFocusAdvance(.next);
    ctx.requestFocusAdvance(.prev);
    ctx.endFrame();
    ctx.beginFrame(); // foco era b → prev cai em a
    try std.testing.expect(ctx.focus_owner == a);
    ctx.endFrame();
}
