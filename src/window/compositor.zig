//! ZyntraUI — composição de repintura do desktop (window/compositor).
//!
//! Camada M102: fecha a parte de DESENHO do multi-janela ligando o registro
//! (M100) e o vínculo de `Context` por janela (M101) à repintura parcial do
//! rasterizador de referência (M98/M99). O compositor guarda uma fotografia
//! do desktop e deriva a danificação sozinho: geometria, visibilidade e
//! empilhamento que mudaram desde a última composição, mais as regiões que
//! cada janela marcou como sujas (`Context.dirty_rect`, alimentado pelos
//! widgets via `mark_hot`).
//!
//! Modelo de coordenadas: os comandos de cada janela são LOCAIS (é o que os
//! widgets enfileiram, com o viewport local de `Window.viewport()` e eventos
//! locais do `window/input`). `compose` desloca os comandos da janela pela
//! origem dos `bounds` dela (`DrawList.translateInto`) e executa
//! `software.raster.renderRegion` com viewport = `bounds` (espaço do
//! desktop), recortado pela região danificada. Mover uma janela não exige
//! re-layout nem redesenho do widget: só recomposição.
//!
//! Protocolo do host por frame:
//! 1. mutações do registro (mover/redimensionar/esconder/mostrar/subir/
//!    remover/adicionar) — o compositor deriva a danificação da fotografia;
//! 2. um frame por janela (`Context.beginFrame` + widgets + `endFrame`),
//!    que deixa `dirty_rect` preenchido (M98/M99);
//! 3. `compose(gpa, fb, &reg, style)` — repinta só o necessário, consome
//!    (zera) o `dirty_rect` das janelas que repintou e atualiza a
//!    fotografia.
//!
//! A janela é desenhada a partir dos comandos que ficaram no `Context`
//! dela (`beginFrame` limpa a lista), então quem compõe também pode pular o
//! frame de uma janela sem alterações: os comandos do último frame dela
//! continuam válidos e a recomposição (mover, subir, descobrir) sai deles.
//! Se rodar o frame, desenhe a janela inteira — uma janela desenhada pela
//! metade fica pela metade.
//!
//! Regras da fotografia (conservadoras, nunca menos do que o necessário):
//! - sem fotografia (primeira composição, ou depois de `reset`): o desktop
//!   INTEIRO é danificado (o conteúdo do framebuffer é desconhecido);
//! - adicionar/mostrar/mover/redimensionar: dano nos bounds NOVOS e nos
//!   antigos (o rastro precisa ser recomposto);
//! - esconder/remover: dano nos bounds antigos;
//! - empilhamento: para cada par visível cuja ordem relativa mudou, dano na
//!   interseção dos bounds atuais;
//! - janela invisível ou sem `Context` não é desenhada: a área fica com o
//!   fundo (`Style.background`) ou com o que já havia ali.
//!
//! Correção é do host quanto ao que ele desenha FORA das janelas: efeitos
//! que leem vizinhos (`.blur`, `.rect_shadow`) enxergam o framebuffer
//! preservado, então quem pinta o fundo/overlays precisa usar `invalidate`.
//!
//! Ownership: `Compositor` é um valor do host (guarda só um rascunho de
//! comandos e a fotografia — sem dono de janela/contexto/framebuffer).
//! `compose` recebe o alocador (estilo `DrawList`); `deinit` libera o
//! rascunho. Os `Context`, o `Registry` e o framebuffer continuam sendo do
//! chamador.

const std = @import("std");
const types = @import("../core/types.zig");
const id_mod = @import("../core/id.zig");
const context_mod = @import("../core/context.zig");
const draw_mod = @import("../draw/commands.zig");
const software = @import("../software/raster.zig");
const registry_mod = @import("registry.zig");

pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;
pub const Color = types.Color;
pub const Id = id_mod.Id;
pub const Registry = registry_mod.Registry;
pub const SoftwareFramebuffer = software.SoftwareFramebuffer;
pub const SoftwareStats = software.SoftwareStats;

/// Erros da composição: falha do rascunho (OOM) ou comando inválido vindo
/// de um `Context` (nunca de geometria do registro, que é validada).
pub const CompositorError = error{ OutOfMemory, InvalidCommand };

/// Parâmetros de composição.
pub const Style = struct {
    /// Cor de fundo do desktop: usada na área danificada que nenhuma
    /// janela cobre. `null` = não repinta o fundo (o host cuida dele, e
    /// deve chamar `invalidate` onde ele mudar).
    background: ?Color = null,
};

/// Estatísticas de uma composição.
pub const Stats = struct {
    /// Regiões danificadas efetivas (depois da fusão dos rects).
    damaged: u32 = 0,
    /// Janelas repintadas (visíveis, com `Context`, tocando a danificação).
    windows: u32 = 0,
    /// Chamadas ao rasterizador (uma por janela × região danificada).
    regions: u32 = 0,
    /// Soma das estatísticas do rasterizador de referência.
    raster: SoftwareStats = .{},
};

/// Lista de rects danificados sem alocação: funde o que se sobrepõe e, se
/// estourar `max_rects`, colapsa tudo numa única união (mais grosso, ainda
/// correto). Rect vazio ou não-finito é ignorado.
pub const Damage = struct {
    /// Rects guardados antes de colapsar numa união.
    pub const max_rects: usize = 8;

    rects: [max_rects]Rect = undefined,
    len: usize = 0,

    pub fn isEmpty(self: *const Damage) bool {
        return self.len == 0;
    }

    pub fn count(self: *const Damage) usize {
        return self.len;
    }

    pub fn list(self: *const Damage) []const Rect {
        return self.rects[0..self.len];
    }

    pub fn clear(self: *Damage) void {
        self.len = 0;
    }

    /// Acrescenta `r`, fundindo com o que já se sobrepõe.
    pub fn add(self: *Damage, r: Rect) void {
        if (r.isEmpty()) return;
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y)) return;
        var merged = r;
        var i: usize = 0;
        while (i < self.len) {
            if (!overlaps(self.rects[i], merged)) {
                i += 1;
                continue;
            }
            merged = self.rects[i].unionWith(merged);
            self.len -= 1;
            self.rects[i] = self.rects[self.len];
            i = 0; // a união pode agora tocar outro rect: revarre
        }
        if (self.len == max_rects) {
            var all = merged;
            for (self.rects[0..self.len]) |r_| all = all.unionWith(r_);
            self.rects[0] = all;
            self.len = 1;
            return;
        }
        self.rects[self.len] = merged;
        self.len += 1;
    }
};

/// Compositor do desktop: fotografia do último frame + danificação.
pub const Compositor = struct {
    /// Rascunho dos comandos deslocados de cada janela (reusado entre
    /// frames, retém capacidade). Ver `DrawList.translateInto`.
    scratch: draw_mod.DrawList = draw_mod.DrawList.initEmpty(),
    /// Fotografia do desktop no último `compose` (ordem base → topo).
    /// Slots a partir de `snap_len` são lixo e nunca são lidos.
    snapshot: [Registry.max_windows]Snap = undefined,
    snap_len: usize = 0,
    /// Danificação extra pedida pelo host (cursor, fundo animado, ...),
    /// somada à próxima composição e então descartada.
    extra: Damage = .{},

    const Snap = struct {
        id: Id = .null,
        bounds: Rect = .{},
        visible: bool = false,
    };

    /// Compositor vazio: primeira composição repinta o desktop inteiro.
    pub fn initEmpty() Compositor {
        return .{};
    }

    pub fn deinit(self: *Compositor, gpa: std.mem.Allocator) void {
        self.scratch.deinit(gpa);
    }

    /// Pede danificação extra na próxima composição — para o que o registro
    /// não vê (cursor, fundo animado, overlays do host).
    pub fn invalidate(self: *Compositor, r: Rect) void {
        self.extra.add(r);
    }

    /// Esquece a fotografia e a danificação extra: a próxima composição
    /// repinta o desktop inteiro (troca de framebuffer/tela, resize).
    pub fn reset(self: *Compositor) void {
        self.snap_len = 0;
        self.extra = .{};
    }

    /// Repinta num framebuffer do desktop o que mudou desde a última
    /// composição. Ver as regras da fotografia no cabeçalho do módulo.
    pub fn compose(
        self: *Compositor,
        gpa: std.mem.Allocator,
        fb: *SoftwareFramebuffer,
        reg: *const Registry,
        style: Style,
    ) CompositorError!Stats {
        const order = reg.order();
        const desktop = Rect{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(fb.w),
            .h = @floatFromInt(fb.h),
        };

        // --- danificação -------------------------------------------------
        var damage = self.extra;
        // Sem fotografia (primeira composição, ou depois de `reset`) o
        // conteúdo do framebuffer é desconhecido: repinta o desktop todo.
        if (self.snap_len == 0) damage.add(desktop);
        // Geometria/visibilidade desde a fotografia (novos e antigos).
        for (order) |w| {
            const i = self.snapIndexOf(w.id) orelse {
                if (w.visible) damage.add(intersect(w.bounds, desktop));
                continue;
            };
            const old = self.snapshot[i];
            if (!old.visible and w.visible) {
                damage.add(intersect(w.bounds, desktop));
            } else if (old.visible and !w.visible) {
                damage.add(intersect(old.bounds, desktop));
            } else if (old.visible and w.visible and !eqlRect(old.bounds, w.bounds)) {
                damage.add(intersect(old.bounds, desktop));
                damage.add(intersect(w.bounds, desktop));
            }
        }
        // Janelas que sumiram.
        for (self.snapshot[0..self.snap_len]) |old| {
            if (old.visible and reg.get(old.id) == null) {
                damage.add(intersect(old.bounds, desktop));
            }
        }
        // Empilhamento: pares visíveis cuja ordem relativa mudou.
        for (order, 0..) |wi, i| {
            if (!wi.visible) continue;
            const oi = self.snapIndexOf(wi.id) orelse continue;
            for (order[i + 1 ..]) |wj| {
                if (!wj.visible) continue;
                const oj = self.snapIndexOf(wj.id) orelse continue;
                if (oi < oj) continue; // ordem relativa preservada
                damage.add(intersect(wi.bounds, wj.bounds));
            }
        }
        // Regiões sujas das janelas (M98/M99), locais → desktop.
        for (order) |w| {
            if (!w.visible) continue;
            const ctx = w.context orelse continue;
            if (ctx.dirty_rect.isEmpty()) continue;
            const desktop_dirty = Rect{
                .x = w.bounds.x + ctx.dirty_rect.x,
                .y = w.bounds.y + ctx.dirty_rect.y,
                .w = ctx.dirty_rect.w,
                .h = ctx.dirty_rect.h,
            };
            damage.add(intersect(intersect(desktop_dirty, w.bounds), desktop));
        }

        // --- repintura ---------------------------------------------------
        var st = Stats{ .damaged = @intCast(damage.count()) };
        const regions = damage.list();
        if (regions.len != 0) {
            if (style.background) |bg| {
                for (regions) |r| fb.fillRect(r, null, bg);
            }
            for (order) |w| {
                if (!w.visible) continue;
                const ctx = w.context orelse continue;
                var painted = false;
                var translated = false;
                for (regions) |r| {
                    const region = intersect(r, w.bounds);
                    if (region.isEmpty()) continue;
                    if (!translated) {
                        // Comandos LOCAIS da janela → espaço do desktop.
                        try ctx.draw.translateInto(
                            gpa,
                            &self.scratch,
                            w.bounds.x,
                            w.bounds.y,
                        );
                        translated = true;
                    }
                    const s = try software.renderRegion(fb, self.scratch.items(), w.bounds, region);
                    st.raster.submitted += s.submitted;
                    st.raster.drawn += s.drawn;
                    st.raster.culled += s.culled;
                    st.raster.skipped_text += s.skipped_text;
                    st.regions += 1;
                    painted = true;
                }
                if (painted) {
                    st.windows += 1;
                    ctx.clear_dirty(); // a danificação das janelas foi consumida
                }
            }
        }

        // --- fotografia ----------------------------------------------------
        self.snap_len = 0;
        for (order) |w| {
            if (self.snap_len == self.snapshot.len) break; // o registro limita
            self.snapshot[self.snap_len] = .{
                .id = w.id,
                .bounds = w.bounds,
                .visible = w.visible,
            };
            self.snap_len += 1;
        }
        self.extra = .{};
        return st;
    }

    fn snapIndexOf(self: *const Compositor, id: Id) ?usize {
        for (self.snapshot[0..self.snap_len], 0..) |s, i| {
            if (s.id == id) return i;
        }
        return null;
    }
};

/// Interseção de dois rects (vazio se disjuntos/esvaziados).
fn intersect(a: Rect, b: Rect) Rect {
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    return .{
        .x = x,
        .y = y,
        .w = @max(0, @min(a.x + a.w, b.x + b.w) - x),
        .h = @max(0, @min(a.y + a.h, b.y + b.h) - y),
    };
}

fn overlaps(a: Rect, b: Rect) bool {
    if (a.isEmpty() or b.isEmpty()) return false;
    return a.x < b.x + b.w and b.x < a.x + a.w and
        a.y < b.y + b.h and b.y < a.y + a.h;
}

fn eqlRect(a: Rect, b: Rect) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

// --- tests ---

const testing = std.testing;

fn winId(name: []const u8) Id {
    return Id.fromString(name);
}

/// Cor do pixel em (`x`,`y`) do framebuffer.
fn px(fb: *const SoftwareFramebuffer, x: u32, y: u32) Color {
    const p = fb.get(x, y);
    return .{ .r = p[0], .g = p[1], .b = p[2], .a = p[3] };
}

/// Enche a janela com `fill` (comando `.clear` local) a cada frame.
fn drawWindow(ctx: *context_mod.Context, gpa: std.mem.Allocator, fill: Color) !void {
    ctx.beginFrame();
    try ctx.draw.clear(gpa, fill);
    ctx.endFrame();
}

test "window/compositor: primeira composição pinta tudo; o sujo é parcial e consumido" {
    const gpa = testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 60, 20);
    defer fb.deinit(gpa);

    var ctx = try context_mod.Context.init(gpa, .{ .viewport = Rect.init(0, 0, 40, 20) });
    defer ctx.deinit();

    var reg: Registry = .{};
    const a = winId("co:a");
    try reg.add(a, Rect.init(0, 0, 40, 20));
    try testing.expect(reg.bind(a, &ctx));

    const bg_desktop = Color.rgb(9, 9, 9);
    const bg_win = Color.rgb(20, 30, 40);
    const block = Color.rgb(200, 10, 10);

    ctx.beginFrame();
    try ctx.draw.clear(gpa, bg_win);
    try ctx.draw.rectFilled(gpa, Rect.init(2, 2, 10, 10), block);
    ctx.endFrame();

    var comp: Compositor = .{};
    defer comp.deinit(gpa);

    // Primeira composição: nada na fotografia ⇒ janela inteira danificada.
    const st = try comp.compose(gpa, &fb, &reg, .{ .background = bg_desktop });
    try testing.expectEqual(@as(u32, 1), st.damaged);
    try testing.expectEqual(@as(u32, 1), st.windows);
    try testing.expectEqual(@as(u32, 1), st.regions);
    try testing.expectEqual(block, px(&fb, 5, 5));
    try testing.expectEqual(bg_win, px(&fb, 30, 15));
    try testing.expectEqual(bg_desktop, px(&fb, 55, 10)); // fora da janela

    // Nada mudou: idle não repinta nada.
    const idle = try comp.compose(gpa, &fb, &reg, .{ .background = bg_desktop });
    try testing.expectEqual(@as(u32, 0), idle.damaged);
    try testing.expectEqual(@as(u32, 0), idle.windows);
    try testing.expectEqual(@as(u32, 0), idle.regions);
    try testing.expectEqual(@as(u32, 0), idle.raster.drawn);

    // Região suja LOCAL (M98) → só ela é repintada; o resto da janela fica
    // como estava (sentinela intacta) e o `dirty_rect` é consumido.
    fb.fillRect(Rect.init(30, 15, 4, 4), null, Color.rgb(1, 2, 3));
    ctx.beginFrame();
    ctx.mark_dirty(Rect.init(2, 2, 10, 10));
    try ctx.draw.clear(gpa, bg_win);
    try ctx.draw.rectFilled(gpa, Rect.init(2, 2, 10, 10), block);
    ctx.endFrame();
    const part = try comp.compose(gpa, &fb, &reg, .{ .background = bg_desktop });
    try testing.expectEqual(@as(u32, 1), part.damaged);
    try testing.expectEqual(@as(u32, 1), part.windows);
    try testing.expectEqual(@as(u32, 1), part.regions);
    try testing.expect(ctx.dirty_rect.isEmpty());
    try testing.expectEqual(block, px(&fb, 5, 5));
    try testing.expectEqual(Color.rgb(1, 2, 3), px(&fb, 31, 16)); // preservado
}

test "window/compositor: mover, esconder e mostrar recompõem o rastro" {
    const gpa = testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 60, 20);
    defer fb.deinit(gpa);

    var ctx_a = try context_mod.Context.init(gpa, .{ .viewport = Rect.init(0, 0, 20, 20) });
    defer ctx_a.deinit();
    var ctx_b = try context_mod.Context.init(gpa, .{ .viewport = Rect.init(0, 0, 20, 20) });
    defer ctx_b.deinit();

    const red = Color.rgb(200, 0, 0);
    const blue = Color.rgb(0, 0, 200);
    const bg = Color.rgb(9, 9, 9);

    var reg: Registry = .{};
    const a = winId("co:mv:a");
    const b = winId("co:mv:b");
    try reg.add(a, Rect.init(0, 0, 20, 20));
    try reg.add(b, Rect.init(30, 0, 20, 20));
    try testing.expect(reg.bind(a, &ctx_a));
    try testing.expect(reg.bind(b, &ctx_b));

    var comp: Compositor = .{};
    defer comp.deinit(gpa);

    try drawWindow(&ctx_a, gpa, red);
    try drawWindow(&ctx_b, gpa, blue);
    _ = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(red, px(&fb, 10, 10));
    try testing.expectEqual(blue, px(&fb, 40, 10));
    try testing.expectEqual(bg, px(&fb, 25, 10));

    // Mover B: dano nos bounds antigos E novos (disjuntos ⇒ 2 regiões).
    try reg.setBounds(b, Rect.init(10, 0, 20, 20));
    try drawWindow(&ctx_a, gpa, red);
    try drawWindow(&ctx_b, gpa, blue);
    const moved = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 2), moved.damaged);
    try testing.expectEqual(@as(u32, 2), moved.windows);
    try testing.expectEqual(bg, px(&fb, 40, 10)); // rastro virou fundo
    try testing.expectEqual(blue, px(&fb, 15, 10)); // conteúdo no lugar novo
    try testing.expectEqual(red, px(&fb, 5, 10)); // área exclusiva de A intacta

    // Esconder B: o fundo volta E A é recomposta onde B cobria.
    try testing.expect(reg.setVisible(b, false));
    try drawWindow(&ctx_a, gpa, red);
    try drawWindow(&ctx_b, gpa, blue);
    const hidden = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 1), hidden.damaged);
    try testing.expectEqual(@as(u32, 1), hidden.windows); // só A (B invisível)
    try testing.expectEqual(red, px(&fb, 15, 10));
    try testing.expectEqual(bg, px(&fb, 25, 10));

    // Mostrar de novo.
    try testing.expect(reg.setVisible(b, true));
    try drawWindow(&ctx_a, gpa, red);
    try drawWindow(&ctx_b, gpa, blue);
    const shown = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 1), shown.damaged);
    try testing.expectEqual(@as(u32, 2), shown.windows);
    try testing.expectEqual(blue, px(&fb, 15, 10));
}

test "window/compositor: subir danifica só a interseção e a nova ordem vence" {
    const gpa = testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 60, 20);
    defer fb.deinit(gpa);

    var ctx_a = try context_mod.Context.init(gpa, .{ .viewport = Rect.init(0, 0, 20, 20) });
    defer ctx_a.deinit();
    var ctx_b = try context_mod.Context.init(gpa, .{ .viewport = Rect.init(0, 0, 20, 20) });
    defer ctx_b.deinit();

    const red = Color.rgb(200, 0, 0);
    const blue = Color.rgb(0, 0, 200);
    const bg = Color.rgb(9, 9, 9);

    var reg: Registry = .{};
    const a = winId("co:rz:a");
    const b = winId("co:rz:b");
    try reg.add(a, Rect.init(0, 0, 20, 20)); // A embaixo
    try reg.add(b, Rect.init(10, 0, 20, 20)); // B em cima
    try testing.expect(reg.bind(a, &ctx_a));
    try testing.expect(reg.bind(b, &ctx_b));

    var comp: Compositor = .{};
    defer comp.deinit(gpa);

    try drawWindow(&ctx_a, gpa, red);
    try drawWindow(&ctx_b, gpa, blue);
    _ = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(red, px(&fb, 5, 10));
    try testing.expectEqual(blue, px(&fb, 15, 10)); // sobreposição: B (topo)
    try testing.expectEqual(blue, px(&fb, 25, 10));

    try testing.expect(reg.raise(a)); // A passa a ser o topo
    try drawWindow(&ctx_a, gpa, red);
    try drawWindow(&ctx_b, gpa, blue);
    const raised = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 1), raised.damaged); // só a interseção
    try testing.expectEqual(@as(u32, 2), raised.regions); // A e B, uma região
    try testing.expectEqual(@as(u32, 2), raised.windows);
    try testing.expectEqual(red, px(&fb, 15, 10)); // nova ordem vence
    try testing.expectEqual(red, px(&fb, 5, 10));
    try testing.expectEqual(blue, px(&fb, 25, 10)); // área só de B intacta
}

test "window/compositor: janela sem contexto deixa o fundo; invalidate força dano" {
    const gpa = testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 60, 20);
    defer fb.deinit(gpa);

    var ctx = try context_mod.Context.init(gpa, .{ .viewport = Rect.init(0, 0, 20, 20) });
    defer ctx.deinit();

    const red = Color.rgb(200, 0, 0);
    const bg = Color.rgb(9, 9, 9);

    var reg: Registry = .{};
    const a = winId("co:noctx:a");
    const c = winId("co:noctx:c");
    try reg.add(a, Rect.init(0, 0, 20, 20));
    try reg.add(c, Rect.init(30, 0, 10, 10)); // sem `Context` vinculado
    try testing.expect(reg.bind(a, &ctx));

    var comp: Compositor = .{};
    defer comp.deinit(gpa);

    try drawWindow(&ctx, gpa, red);
    const st = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 1), st.damaged); // sem fotografia: desktop
    try testing.expectEqual(@as(u32, 1), st.windows); // a sem contexto não desenha
    try testing.expectEqual(red, px(&fb, 10, 10));
    try testing.expectEqual(bg, px(&fb, 35, 5));

    // Idle: zero.
    try testing.expectEqual(
        @as(u32, 0),
        (try comp.compose(gpa, &fb, &reg, .{ .background = bg })).damaged,
    );

    // `invalidate` entra na próxima composição e é consumido.
    comp.invalidate(Rect.init(2, 2, 4, 4));
    const forced = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 1), forced.damaged);
    try testing.expectEqual(@as(u32, 1), forced.windows);
    try testing.expectEqual(@as(u32, 1), forced.regions);
    try testing.expectEqual(
        @as(u32, 0),
        (try comp.compose(gpa, &fb, &reg, .{ .background = bg })).damaged,
    );

    // `reset` esquece a fotografia: repinta o desktop inteiro de novo.
    comp.reset();
    const after_reset = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 1), after_reset.damaged);

    // Remover a janela danifica os bounds antigos (volta ao fundo).
    try testing.expect(reg.remove(a));
    try drawWindow(&ctx, gpa, red);
    const removed = try comp.compose(gpa, &fb, &reg, .{ .background = bg });
    try testing.expectEqual(@as(u32, 1), removed.damaged);
    try testing.expectEqual(@as(u32, 0), removed.windows);
    try testing.expectEqual(bg, px(&fb, 10, 10));
}

test "window/compositor: Damage funde sobreposições, colapsa no limite e ignora lixo" {
    var d: Damage = .{};
    try testing.expect(d.isEmpty());

    d.add(Rect.init(0, 0, 10, 10));
    d.add(Rect.init(30, 0, 10, 10)); // disjunto
    try testing.expectEqual(@as(usize, 2), d.count());

    // Ponte que sobrepõe os dois: a fusão revarre e sobra um rect só.
    d.add(Rect.init(5, 0, 30, 10));
    try testing.expectEqual(@as(usize, 1), d.count());
    try testing.expectEqual(Rect.init(0, 0, 40, 10), d.list()[0]);

    // Vazio e não-finito são ignorados.
    d.add(Rect.init(0, 0, 0, 0));
    d.add(Rect.init(0, 0, 10, -3));
    d.add(Rect.init(std.math.nan(f32), 0, 5, 5));
    try testing.expectEqual(@as(usize, 1), d.count());

    // Estouro de `max_rects`: colapsa tudo numa única união (conservador).
    d.clear();
    try testing.expect(d.isEmpty());
    var i: usize = 0;
    while (i < Damage.max_rects) : (i += 1) {
        d.add(Rect.init(@floatFromInt(i * 100), 0, 10, 10));
    }
    try testing.expectEqual(Damage.max_rects, d.count());
    d.add(Rect.init(0, 500, 10, 10));
    try testing.expectEqual(@as(usize, 1), d.count());
    const all = d.list()[0];
    try testing.expectEqual(@as(f32, 0), all.x);
    try testing.expectEqual(@as(f32, 0), all.y);
    try testing.expectEqual(@as(f32, 710), all.w);
    try testing.expectEqual(@as(f32, 510), all.h);

    d.clear();
    try testing.expect(d.isEmpty());
}
