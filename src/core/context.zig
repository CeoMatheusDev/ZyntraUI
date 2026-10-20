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
const scale_mod = @import("scale.zig");
const metrics_mod = @import("../text/metrics.zig");
const atlas_mod = @import("../text/atlas.zig");
const bitmap_mod = @import("../text/bitmap.zig");
const event_mod = @import("../event/event.zig");
const draw_mod = @import("../draw/commands.zig");
const stats_mod = @import("../draw/stats.zig");
const a11y_mod = @import("../a11y/tree.zig");
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
    /// Escala DPI da superfície (M125): pixels de dispositivo por pixel
    /// lógico. O viewport e os eventos continuam em pixels lógicos.
    scale: scale_mod.DpiScale = .{},
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

/// Widget "quente" registrado no frame (id + área ocupada).
pub const HotEntry = struct {
    id: id_mod.Id,
    bounds: types.Rect,
};

/// Contexto raiz da GUI. Um por aplicação/janela na M1.
pub const Context = struct {
    allocator: std.mem.Allocator,
    viewport: types.Rect,
    /// Escala DPI vigente (M125): o resto da biblioteca fala em pixels
    /// lógicos; o host converte entrada/saída com esta escala.
    scale: scale_mod.DpiScale = .{},
    /// Fonte de bitmap monoespaçada aplicada a TODOS os widgets (M142).
    /// `null` = sem fonte de bitmap (o texto vira comando `.text`).
    bitmap_font: ?bitmap_mod.BitmapFont = null,
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
    /// Chamadas de `mark_dirty` no frame corrente (observabilidade,
    /// M153). As regiões são unidas em `dirty_rect`; o contador é o
    /// número de marcações feitas.
    dirty_marks: u32 = 0,
    /// Região suja acumulada no frame corrente: união das áreas
    /// marcadas via `mark_dirty` (vazia = nada a repintar). Limpa em
    /// `beginFrame`. Consumida por `software.raster.renderRegion` para
    /// repintar só o que mudou. Widgets marcam pelo helper `mark_hot`
    /// (estado de interação) e o chamador marca direto via `mark_dirty`
    /// quando dados externos mudam a aparência.
    dirty_rect: types.Rect = types.Rect.init(0, 0, 0, 0),
    /// Widgets "quentes" no frame anterior (ver `mark_hot`): widgets que
    /// declararam interação e que, portanto, podem ter deixado pixels
    /// realçados para desfazer. Cada entrada guarda também a ÁREA
    /// ocupada, para que a saída do estado repinte exatamente onde o
    /// real ficou. Trocado com `hot_now` no `beginFrame`.
    hot_prev: std.ArrayList(HotEntry) = .empty,
    /// Widgets "quentes" do frame corrente, em ordem de declaração.
    /// Vira `hot_prev` no `beginFrame` seguinte.
    hot_now: std.ArrayList(HotEntry) = .empty,
    /// Árvore de acessibilidade do frame (M164): os widgets registram
    /// aqui o que um leitor de tela precisa saber. Zera a cada frame.
    a11y: a11y_mod.Tree = .{},
    /// Árvore do frame ANTERIOR (o diff é calculado no `endFrame`).
    a11y_prev: a11y_mod.Tree = .{},
    /// Mudanças semânticas do frame (M167): o que mudou desde o frame
    /// anterior (entrou, saiu, mudou ou o foco mudou). Zera a cada
    /// frame; o app consome depois do `endFrame`.
    a11y_changes: std.ArrayList(a11y_mod.Change) = .empty,
    /// O foco no frame anterior (para o diff de foco).
    a11y_prev_focus: ?u64 = null,
    /// Id do "pai" a11y atual (o container que começou por último):
    /// os nós registrados herdam esse pai.
    a11y_parent: u64 = 0,
    /// Pilha de pais a11y (aninhamento de containers).
    a11y_parents: [16]u64 = @splat(0),
    /// Profundidade da pilha de pais a11y.
    a11y_depth: u8 = 0,

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
        if (!config.scale.isValid()) return error.InvalidArgument;
        if (config.initial_widget_capacity == 0) {
            return error.InvalidArgument;
        }
        if (config.initial_widget_capacity > config.max_widget_capacity) {
            return error.InvalidArgument;
        }
        return .{
            .allocator = allocator,
            .viewport = config.viewport,
            .scale = config.scale,
            .frame_index = 0,
            .state = .idle,
            .events = event_mod.EventQueue.initEmpty(),
            .dirty_rect = types.Rect.init(0, 0, 0, 0),
            .draw = draw_mod.DrawList.initEmpty(),
            .focusables = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit(self.allocator);
        self.draw.deinit(self.allocator);
        self.focusables.deinit(self.allocator);
        self.hot_prev.deinit(self.allocator);
        self.hot_now.deinit(self.allocator);
        self.a11y.nodes.deinit(self.allocator);
        self.a11y_prev.nodes.deinit(self.allocator);
        self.a11y_changes.deinit(self.allocator);
        self.events = event_mod.EventQueue.initEmpty();
        self.draw = draw_mod.DrawList.initEmpty();
        self.focusables = .empty;
        self.hot_prev = .empty;
        self.hot_now = .empty;
        self.a11y = .{};
        self.a11y_prev = .{};
        self.a11y_changes = .empty;
        self.a11y_prev_focus = null;
        self.a11y_parent = 0;
        self.a11y_depth = 0;
        self.state = .idle;
        self.frame_index = 0;
        self.mouse_pos = null;
        self.mouse_down_left = false;
        self.press_owner = null;
        self.focus_owner = null;
        self.pending_focus_advance = null;
        self.dnd = .{};
        self.dirty_rect = types.Rect.init(0, 0, 0, 0);
        self.dirty_marks = 0;
    }

    /// Inicia um novo frame: aplica avanço de foco pendente (sobre o
    /// registro do frame anterior) e limpa eventos/draw/focáveis/região
    /// suja do frame anterior (retendo capacidade), promovendo o registro
    /// "quente" corrente a anterior. Deve ser pareado com `endFrame`.
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
        // A árvore a11y é do frame: a do frame anterior fica para o
        // diff (calculado no endFrame) e a de agora começa vazia.
        std.mem.swap(a11y_mod.Tree, &self.a11y, &self.a11y_prev);
        self.a11y.clear();
        self.a11y_changes.clearRetainingCapacity();
        self.a11y_parent = 0;
        self.a11y_depth = 0;
        // Fecha o ciclo de interação: o registro quente do frame que
        // terminou vira a base da detecção de saída em `mark_hot`.
        std.mem.swap(std.ArrayList(HotEntry), &self.hot_prev, &self.hot_now);
        self.hot_now.clearRetainingCapacity();
        self.clear_dirty();
    }

    /// Encerra o frame atual e avança `frame_index` com wrap seguro.
    /// Precondição: frame ativo.
    pub fn endFrame(self: *Self) void {
        std.debug.assert(self.state == .active);
        // O diff da árvore a11y (M167): o que mudou desde o frame
        // anterior (o app atualiza o leitor de tela com isto).
        self.computeA11yChanges();
        self.state = .idle;
        self.frame_index +%= 1;
    }

    /// Calcula as mudanças semânticas da árvore a11y (frame anterior →
    /// frame atual) e guarda em `a11y_changes`.
    fn computeA11yChanges(self: *Self) void {
        self.a11y_changes.clearRetainingCapacity();
        const cur_focus: ?u64 = if (self.focus_owner) |f| f.value() else null;
        var buf: [64]a11y_mod.Change = undefined;
        const n = a11y_mod.diff(
            &self.a11y_prev,
            &self.a11y,
            self.a11y_prev_focus,
            cur_focus,
            &buf,
        );
        self.a11y_changes.appendSlice(self.allocator, buf[0..n]) catch {
            // Sem memória: as mudanças ficam de fora (o app continua
            // funcionando; a árvore completa segue disponível).
            return;
        };
        self.a11y_prev_focus = cur_focus;
    }

    /// As mudanças semânticas do frame (M167): nós que entraram, saíram,
    /// mudaram e a mudança de foco. Válido depois do `endFrame`.
    pub fn a11yChanges(self: *const Self) []const a11y_mod.Change {
        return self.a11y_changes.items;
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

    /// Troca a escala DPI da superfície (M125). Fator precisa ser
    /// finito e > 0.
    pub fn setScale(self: *Self, scale: scale_mod.DpiScale) ContextError!void {
        if (!scale.isValid()) return error.InvalidArgument;
        self.scale = scale;
    }

    /// Enfileira um evento cujo estado veio em pixels de DISPOSITIVO:
    /// as posições do mouse e o tamanho do resize são convertidos para
    /// pixels lógicos antes de entrar no frame. Eventos sem coordenada
    /// (teclas, texto) passam direto.
    pub fn pushDeviceEvent(self: *Self, ev: event_mod.Event) ContextError!void {
        var converted = ev;
        switch (converted) {
            .mouse_move => |*m| m.pos = self.scale.vecToLogical(m.pos),
            .mouse_button => |*b| b.pos = self.scale.vecToLogical(b.pos),
            .mouse_wheel => |*w| w.pos = self.scale.vecToLogical(w.pos),
            .resize => |*r| r.size = self.scale.sizeToLogical(r.size),
            else => {},
        }
        return self.pushEvent(converted);
    }

    /// Define o viewport a partir de um rect em pixels de dispositivo
    /// (convertido para pixels lógicos).
    pub fn setDeviceViewport(self: *Self, device_rect: types.Rect) ContextError!void {
        return self.setViewport(self.scale.rectToLogical(device_rect));
    }

    /// Libera captura de press órfã (ex.: widget sumiu, foco perdido).
    pub fn clearPressCapture(self: *Self) void {
        self.press_owner = null;
    }

    /// Libera o foco de teclado (ex.: click fora, troca de tela).
    pub fn clearFocus(self: *Self) void {
        self.focus_owner = null;
    }

    /// Registra (ou remove, com `null`) a fonte de bitmap global (M142).
    /// O atlas é EMPRESTADO: precisa viver (junto com a sua imagem)
    /// enquanto estiver registrado — destruí-lo antes deixa um ponteiro
    /// pendurado.
    pub fn setBitmapFont(self: *Self, font: ?bitmap_mod.BitmapFont) void {
        self.bitmap_font = font;
    }

    /// Desenha texto com a fonte vigente: com a fonte de bitmap
    /// registrada (e de mesmo avanço que as métricas), o texto sai do
    /// atlas como blits; senão, vira o comando `.text` de sempre.
    ///
    /// Erros: os mesmos de `DrawList.pushText` (e o atlas inconsistente
    /// vira `InvalidCommand`).
    pub fn pushText(
        self: *Self,
        pos: types.Vec2,
        color: types.Color,
        font: metrics_mod.FontMetrics,
        text: []const u8,
    ) error{ OutOfMemory, InvalidCommand, InvalidUtf8, InvalidMetrics }!void {
        if (self.bitmap_font) |bf| {
            if (bf.matches(font)) {
                // A linha de base fica na ascente do atlas: o topo do
                // glifo alinha com o topo do texto.
                const baseline = types.Vec2.init(pos.x, pos.y + bf.atlas.ascent());
                atlas_mod.drawRun(&self.draw, self.allocator, bf.atlas, text, baseline, color) catch |err| return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidUtf8 => error.InvalidUtf8,
                    error.InvalidMetrics => error.InvalidMetrics,
                    error.InvalidGlyph,
                    error.DuplicateGlyph,
                    error.AtlasFull,
                    error.InvalidCommand,
                    => error.InvalidCommand,
                };
                return;
            }
        }
        self.draw.pushText(self.allocator, pos, color, font, text) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidCommand => error.InvalidCommand,
            error.InvalidUtf8 => error.InvalidUtf8,
            error.InvalidMetrics => error.InvalidMetrics,
        };
    }

    /// Define o alfa global dos comandos seguintes (0..1). É o gancho
    /// de animações (fade) sobre widgets: o que for desenhado depois
    /// sai atenuado até o próximo `pushAlpha` (ou o fim do frame).
    /// Registra um nó na árvore de acessibilidade do frame (M164).
    ///
    /// O nó herda o pai a11y atual (o container aberto). O rótulo e o
    /// valor são EMPRESTADOS (o app é dono do texto).
    pub fn pushA11y(self: *Self, node: a11y_mod.Node) ContextError!void {
        var n = node;
        if (n.parent == 0) n.parent = self.a11y_parent;
        self.a11y.push(self.allocator, n) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// Registra um nó a11y de um widget (atalho para o widget).
    ///
    /// O rótulo e o valor ficam vazios: quem sabe o texto do widget
    /// (o app) os preenche com `setA11yLabel`/`setA11yValue`.
    pub fn pushA11yWidget(
        self: *Self,
        id: id_mod.Id,
        role: a11y_mod.Role,
        bounds: types.Rect,
        state: a11y_mod.State,
    ) ContextError!void {
        if (id.isNull()) return;
        try self.pushA11y(.{
            .id = id.value(),
            .role = role,
            .bounds = bounds,
            .state = state,
        });
    }

    /// Define o RÓTULO do nó de um widget (o texto que o leitor de tela
    /// anuncia). Aplica ao ÚLTIMO nó registrado com esse id.
    pub fn setA11yLabel(self: *Self, id: id_mod.Id, label: []const u8) void {
        if (id.isNull()) return;
        var i = self.a11y.nodes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.a11y.nodes.items[i].id != id.value()) continue;
            self.a11y.nodes.items[i].label = label;
            return;
        }
    }

    /// Define o VALOR do nó de um widget (o texto atual de um campo,
    /// por exemplo).
    pub fn setA11yValue(self: *Self, id: id_mod.Id, value: []const u8) void {
        if (id.isNull()) return;
        var i = self.a11y.nodes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.a11y.nodes.items[i].id != id.value()) continue;
            self.a11y.nodes.items[i].value = value;
            return;
        }
    }

    /// Abre um container a11y: os nós registrados depois ficam como
    /// filhos de `id` (até o `endA11yGroup` correspondente).
    pub fn beginA11yGroup(self: *Self, id: u64) void {
        if (self.a11y_depth >= self.a11y_parents.len) return; // aninhamento demais: ignora
        self.a11y_parents[self.a11y_depth] = self.a11y_parent;
        self.a11y_depth += 1;
        self.a11y_parent = id;
    }

    /// Fecha o container a11y (volta ao pai anterior).
    pub fn endA11yGroup(self: *Self) void {
        if (self.a11y_depth == 0) return;
        self.a11y_depth -= 1;
        self.a11y_parent = self.a11y_parents[self.a11y_depth];
    }

    pub fn pushAlpha(self: *Self, factor: f32) ContextError!void {
        self.draw.pushAlpha(self.allocator, factor) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }

    /// Marca `rect` como sujo para este frame. Chamadas sucessivas
    /// acumulam por união (a região cresce para cobrir todas as áreas
    /// modificadas); marcar um rect vazio é no-op. O rect vale para o
    /// frame corrente: `beginFrame` limpa antes do próximo.
    pub fn mark_dirty(self: *Self, rect: types.Rect) void {
        self.dirty_marks += 1;
        self.dirty_rect = self.dirty_rect.unionWith(rect);
    }

    /// Limpa o rectângulo sujo (chamado no `beginFrame`).
    pub fn clear_dirty(self: *Self) void {
        self.dirty_rect = types.Rect.init(0, 0, 0, 0);
    }

    /// Reserva capacidade para os comandos (e bytes de texto) do frame
    /// seguinte (M153). Sem alocação quando a capacidade já basta.
    pub fn reserveDrawCommands(self: *Self, commands: usize, text_bytes: usize) ContextError!void {
        self.draw.reserve(self.allocator, commands, text_bytes, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// Reserva capacidade só para os bytes de texto (M153).
    pub fn reserveTextBytes(self: *Self, text_bytes: usize) ContextError!void {
        self.draw.reserve(self.allocator, 0, text_bytes, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// Métricas estendidas do frame (M153): contadores por tipo de
    /// comando, bytes de texto, glifos e crescimentos de buffer.
    /// Sem alocação (uso diagnóstico).
    pub fn frameMetrics(self: *const Self) stats_mod.FrameMetrics {
        var m = stats_mod.frameMetrics(&self.draw, self.viewport);
        m.dirty_rects = self.dirty_marks;
        m.buffer_growths = self.draw.growths;
        return m;
    }

    /// Declara o estado de interação do widget `id` neste frame e mantém o
    /// dirty rect coerente com a transição. Chame TODO frame, depois de
    /// conhecer o estado, com `hot` verdadeiro quando a aparência do
    /// widget pode diferir do desenho "frio": hover, press/drag capturado
    /// ou valor alterado (inclua foco se o widget desenhar realce de foco).
    ///
    /// - `hot`: `bounds` entra na região suja (o widget pode ter mudado);
    /// - `hot` falso com o id quente no frame ANTERIOR: `bounds` também
    ///   entra, para apagar o realce que ficou no framebuffer (é a razão
    ///   de o registro ser guardado entre frames).
    ///
    /// O mecanismo é conservador de propósito: enquanto quente, o widget
    /// é tratado como em mudança e o próprio rect é repintado a cada frame
    /// (os demais continuam pulados). Ao SAIR do estado quente, a área
    /// que o widget ocupava no frame anterior é repintada (é lá que o
    /// real ficou) — assim um widget que some não deixa pixels velhos.
    /// Widget que nunca foi declarado quente e some do nada continua
    /// desconhecido: quem some deve marcar o próprio rect via
    /// `mark_dirty`.
    pub fn mark_hot(self: *Self, id: id_mod.Id, bounds: types.Rect, hot: bool) ContextError!void {
        if (hot) {
            // Registra (ou atualiza) a entrada quente do frame corrente.
            if (hotEntryIndex(self.hot_now.items, id)) |i| {
                self.hot_now.items[i].bounds = bounds;
            } else {
                self.hot_now.append(self.allocator, .{ .id = id, .bounds = bounds }) catch return error.OutOfMemory;
            }
            self.mark_dirty(bounds);
            return;
        }
        // Saiu do estado quente: repinta a ÁREA que ele ocupava no
        // frame ANTERIOR.
        if (hotEntry(self.hot_prev.items, id)) |prev| {
            self.mark_dirty(prev.bounds);
        }
    }

    /// True se `id` foi declarado quente no frame anterior — isto é, pode
    /// ter pixels realçados pendentes de repintura.
    pub fn was_hot(self: *const Self, id: id_mod.Id) bool {
        return hotEntryIndex(self.hot_prev.items, id) != null;
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

/// Busca linear de `id` numa lista de ids (registros por frame são
/// pequenos e a ordem não importa). Ver `Context.mark_hot`.
fn hotEntryIndex(items: []const HotEntry, id: id_mod.Id) ?usize {
    for (items, 0..) |other, i| {
        if (other.id == id) return i;
    }
    return null;
}

fn hotEntry(items: []const HotEntry, id: id_mod.Id) ?HotEntry {
    const i = hotEntryIndex(items, id) orelse return null;
    return items[i];
}

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

test "Context M98: dirty rect acumula por união e limpa no beginFrame" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{ .viewport = types.Rect.init(0, 0, 200, 100) });
    defer ctx.deinit();

    // Antes de qualquer frame: vazio.
    try std.testing.expect(ctx.dirty_rect.isEmpty());

    ctx.beginFrame();
    try std.testing.expect(ctx.dirty_rect.isEmpty());
    // Marcação única: o rect vale por si.
    ctx.mark_dirty(types.Rect.init(10, 10, 20, 20));
    try std.testing.expectEqual(types.Rect.init(10, 10, 20, 20), ctx.dirty_rect);
    // União com um segundo rect (disjunto) cobre os dois.
    ctx.mark_dirty(types.Rect.init(60, 40, 30, 20));
    try std.testing.expectEqual(types.Rect.init(10, 10, 80, 50), ctx.dirty_rect);
    // Rect vazio é no-op (não apaga o acumulado).
    ctx.mark_dirty(types.Rect.init(0, 0, 0, 0));
    try std.testing.expectEqual(types.Rect.init(10, 10, 80, 50), ctx.dirty_rect);
    // Rect contido não cresce a região.
    ctx.mark_dirty(types.Rect.init(15, 15, 5, 5));
    try std.testing.expectEqual(types.Rect.init(10, 10, 80, 50), ctx.dirty_rect);
    ctx.endFrame();

    // O rect é por frame: `beginFrame` limpa o acumulado anterior.
    ctx.beginFrame();
    try std.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.mark_dirty(types.Rect.init(1, 2, 3, 4));
    try std.testing.expectEqual(types.Rect.init(1, 2, 3, 4), ctx.dirty_rect);
    ctx.endFrame();

    // `clear_dirty` explícito no meio do frame também zera.
    ctx.beginFrame();
    ctx.mark_dirty(types.Rect.init(5, 5, 5, 5));
    ctx.clear_dirty();
    try std.testing.expect(ctx.dirty_rect.isEmpty());
    // Marcar depois de limpar volta a funcionar (não fica "grudado").
    ctx.mark_dirty(types.Rect.init(7, 8, 9, 10));
    try std.testing.expectEqual(types.Rect.init(7, 8, 9, 10), ctx.dirty_rect);
    ctx.endFrame();
}

test "Context M98b: deinit zera o dirty rect" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    ctx.beginFrame();
    ctx.mark_dirty(types.Rect.init(3, 3, 4, 4));
    ctx.endFrame();
    ctx.deinit();
    try std.testing.expect(ctx.dirty_rect.isEmpty());
}

test "Context M99: mark_hot marca na entrada e na saída do estado" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{ .viewport = types.Rect.init(0, 0, 100, 100) });
    defer ctx.deinit();
    const a = id_mod.Id.fromString("hot:a");
    const ra = types.Rect.init(10, 10, 20, 20);

    // Frame 1: frio ⇒ nada sujo e ninguém quente no registro anterior.
    ctx.beginFrame();
    try ctx.mark_hot(a, ra, false);
    try std.testing.expect(ctx.dirty_rect.isEmpty());
    try std.testing.expect(!ctx.was_hot(a));
    ctx.endFrame();

    // Frame 2: entra quente ⇒ bounds sujo; ainda não conta como anterior.
    ctx.beginFrame();
    try ctx.mark_hot(a, ra, true);
    try std.testing.expectEqual(ra, ctx.dirty_rect);
    try std.testing.expect(!ctx.was_hot(a));
    ctx.endFrame();

    // Frame 3: sai do estado quente ⇒ bounds sujo de novo, para apagar o
    // realce deixado no framebuffer.
    ctx.beginFrame();
    try std.testing.expect(ctx.was_hot(a));
    try ctx.mark_hot(a, ra, false);
    try std.testing.expectEqual(ra, ctx.dirty_rect);
    ctx.endFrame();

    // Frame 4: já frio nos dois frames ⇒ nada sujo (frame ocioso).
    ctx.beginFrame();
    try std.testing.expect(!ctx.was_hot(a));
    try ctx.mark_hot(a, ra, false);
    try std.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();
}

test "Context M99b: mark_hot une bounds de ids distintos sem duplicar" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();
    const a = id_mod.Id.fromString("hot:a2");
    const b = id_mod.Id.fromString("hot:b2");
    const ra = types.Rect.init(0, 0, 10, 10);
    const rb = types.Rect.init(40, 40, 10, 10);

    ctx.beginFrame();
    try ctx.mark_hot(a, ra, true);
    try ctx.mark_hot(b, rb, true);
    try ctx.mark_hot(a, ra, true); // repetido: mesma entrada, sem duplicar
    try std.testing.expectEqual(ra.unionWith(rb), ctx.dirty_rect);
    try std.testing.expectEqual(@as(usize, 2), ctx.hot_now.items.len);
    ctx.endFrame();

    // Um continua quente, o outro sai: o que sai repinta, o que fica também.
    ctx.beginFrame();
    try ctx.mark_hot(a, ra, true);
    try ctx.mark_hot(b, rb, false);
    try std.testing.expectEqual(ra.unionWith(rb), ctx.dirty_rect);
    try std.testing.expectEqual(@as(usize, 1), ctx.hot_now.items.len);
    ctx.endFrame();

    // Registro anterior é o do frame passado: `a` quente, `b` já frio.
    ctx.beginFrame();
    try std.testing.expect(ctx.was_hot(a));
    try std.testing.expect(!ctx.was_hot(b));
    ctx.endFrame();
}

test "Context M125: escala DPI converte viewport e eventos de dispositivo" {
    const allocator = std.testing.allocator;
    const scale = scale_mod.DpiScale{ .factor = 2.0 };
    var ctx = try Context.init(allocator, .{ .scale = scale });
    defer ctx.deinit();
    try std.testing.expectEqual(scale, ctx.scale);

    // Viewport em pixels de dispositivo → lógico.
    try ctx.setDeviceViewport(types.Rect.init(0, 0, 1600, 900));
    try std.testing.expectEqual(types.Rect.init(0, 0, 800, 450), ctx.viewport);

    // Eventos de dispositivo → coordenadas lógicas.
    ctx.beginFrame();
    try ctx.pushDeviceEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(100, 50) } });
    try ctx.pushDeviceEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(20, 30),
    } });
    try ctx.pushDeviceEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -2, .pos = types.Vec2.init(10, 10) } });
    try ctx.pushDeviceEvent(.{ .resize = .{ .size = types.Size{ .w = 1200, .h = 800 } } });
    const evs = ctx.pendingEvents();
    try std.testing.expectEqual(@as(usize, 4), evs.len);
    try std.testing.expectEqual(types.Vec2.init(50, 25), evs[0].mouse_move.pos);
    try std.testing.expectEqual(types.Vec2.init(10, 15), evs[1].mouse_button.pos);
    try std.testing.expectEqual(types.Vec2.init(5, 5), evs[2].mouse_wheel.pos);
    try std.testing.expectEqual(types.Size{ .w = 600, .h = 400 }, evs[3].resize.size);
    // O estado retido do mouse também fica em pixels lógicos.
    try std.testing.expectEqual(types.Vec2.init(5, 5), ctx.mouse_pos.?);
    ctx.endFrame();

    // Troca de escala e escala inválida.
    try ctx.setScale(.{ .factor = 1.5 });
    try std.testing.expectEqual(@as(f32, 1.5), ctx.scale.factor);
    try std.testing.expectError(error.InvalidArgument, ctx.setScale(.{ .factor = 0 }));
    try std.testing.expectError(error.InvalidArgument, ctx.setScale(.{ .factor = std.math.nan(f32) }));
    try std.testing.expectEqual(@as(f32, 1.5), ctx.scale.factor);

    // Evento de dispositivo inválido é recusado como qualquer outro.
    ctx.beginFrame();
    try std.testing.expectError(error.InvalidEvent, ctx.pushDeviceEvent(.{ .mouse_move = .{
        .pos = types.Vec2.init(std.math.nan(f32), 0),
    } }));
    ctx.endFrame();
}

test "Context M125: config com escala inválida é recusada" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidArgument, Context.init(allocator, .{
        .scale = .{ .factor = 0 },
    }));
    try std.testing.expectError(error.InvalidArgument, Context.init(allocator, .{
        .scale = .{ .factor = std.math.inf(f32) },
    }));
}

test "Context M142: fonte de bitmap global desenha o texto dos widgets (M142)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    // Atlas monoespaçado de 2 glifos com avanço 6 (igual ao das métricas
    // de fallback com size 10).
    var b = atlas_mod.Builder.init(32, 32, 1);
    defer b.deinit(gpa);
    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 6, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, 'B', 4, 8, .{ .advance = 6, .bearing_y = -8, .height = 8 });
    var bytes: [32 * 32 * 4]u8 = undefined;
    for (&bytes, 0..) |*p, i| p.* = @truncate(i);
    const img = try @import("../draw/image.zig").Image.init(32, 32, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);
    const font = try bitmap_mod.BitmapFont.init(&atlas);

    var ctx = try Context.init(gpa, .{});
    defer ctx.deinit();
    const metrics = @import("../text/metrics.zig").FontMetrics.withSize(10); // advance 6

    // Sem a fonte: o texto vira comando `.text`.
    ctx.beginFrame();
    try ctx.pushText(types.Vec2.init(1, 2), types.Color.rgb(255, 255, 255), metrics, "AB");
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    try stdt.testing.expect(ctx.drawCommands()[0] == .text);
    ctx.endFrame();

    // Com a fonte: o texto vira um run de glifos (um comando).
    ctx.setBitmapFont(font);
    ctx.beginFrame();
    try ctx.pushText(types.Vec2.init(1, 2), types.Color.rgb(255, 255, 255), metrics, "AB");
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    try stdt.testing.expect(ctx.drawCommands()[0] == .glyph_run);
    const refs = ctx.draw.glyphsOf(ctx.drawCommands()[0]);
    try stdt.testing.expectEqual(@as(usize, 2), refs.len);
    // O segundo glifo avança 6 px (o avanço da fonte), relativo ao run.
    try stdt.testing.expectEqual(@as(f32, 6), refs[1].dx);
    ctx.endFrame();

    // Métricas de outro avanço => fallback (medida e desenho seguem a
    // fonte dos widgets).
    const other = @import("../text/metrics.zig").FontMetrics.withSize(16);
    ctx.beginFrame();
    try ctx.pushText(types.Vec2.init(0, 0), types.Color.rgb(255, 255, 255), other, "AB");
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    try stdt.testing.expect(ctx.drawCommands()[0] == .text);
    ctx.endFrame();

    // Removendo a fonte, volta o fallback.
    ctx.setBitmapFont(null);
    ctx.beginFrame();
    try ctx.pushText(types.Vec2.init(0, 0), types.Color.rgb(255, 255, 255), metrics, "AB");
    try stdt.testing.expect(ctx.drawCommands()[0] == .text);
    ctx.endFrame();
}

test "Context M153: métricas do frame e reserva de capacidade" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var ctx = try Context.init(gpa, .{});
    defer ctx.deinit();

    // Reserva: a capacidade cobre o frame inteiro.
    try ctx.reserveDrawCommands(16, 64);
    const cap = ctx.draw.list.capacity;
    try stdt.testing.expect(cap >= 16);
    try ctx.reserveTextBytes(64);
    try stdt.testing.expect(ctx.draw.text_bytes.capacity >= 64);

    ctx.beginFrame();
    try ctx.draw.rectFilled(ctx.allocator, types.Rect.init(0, 0, 10, 10), types.Color.rgb(1, 2, 3));
    try ctx.draw.pushText(ctx.allocator, types.Vec2.init(0, 0), types.Color.rgb(1, 2, 3), metrics_mod.FontMetrics.withSize(10), "ab");
    ctx.mark_dirty(types.Rect.init(0, 0, 5, 5));
    ctx.mark_dirty(types.Rect.init(0, 0, 8, 8));

    const m = ctx.frameMetrics();
    try stdt.testing.expectEqual(@as(u32, 2), m.commands_total);
    try stdt.testing.expectEqual(@as(u32, 1), m.rects);
    try stdt.testing.expectEqual(@as(u32, 1), m.texts);
    try stdt.testing.expectEqual(@as(u32, 2), m.text_bytes);
    try stdt.testing.expectEqual(@as(u32, 2), m.dirty_rects);
    // A reserva evitou qualquer crescimento.
    try stdt.testing.expectEqual(@as(u32, 0), m.buffer_growths);
    ctx.endFrame();

    // Sem reserva, o crescimento é contabilizado.
    ctx.beginFrame();
    var i: usize = 0;
    while (i < cap + 4) : (i += 1) {
        try ctx.draw.rectFilled(ctx.allocator, types.Rect.init(0, 0, 1, 1), types.Color.rgb(1, 2, 3));
    }
    try stdt.testing.expect(ctx.frameMetrics().buffer_growths > 0);
    ctx.endFrame();
}

test "Context M143: ao sair do estado quente, a área ANTERIOR é repintada" {
    const stdt = @import("std");
    const allocator = stdt.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("hot:move");

    // Frame 1: o widget é quente em (0,0,10,10).
    ctx.beginFrame();
    try ctx.mark_hot(id, types.Rect.init(0, 0, 10, 10), true);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 10, 10), ctx.dirty_rect);
    ctx.endFrame();

    // Frame 2: o widget mudou de lugar e saiu do estado quente ⇒ a
    // área ANTIGA (onde o real ficou) é repintada.
    ctx.beginFrame();
    try ctx.mark_hot(id, types.Rect.init(50, 50, 10, 10), false);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 10, 10), ctx.dirty_rect);
    ctx.endFrame();

    // Frame 3: sem estado quente nem registro ⇒ nada é repintado.
    ctx.beginFrame();
    try ctx.mark_hot(id, types.Rect.init(50, 50, 10, 10), false);
    try stdt.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();
}
