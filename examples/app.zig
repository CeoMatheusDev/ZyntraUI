//! ZyntraUI — exemplo integrado (M69): mini-app de tarefas.
//!
//! Demonstra COMPOSIÇÃO real em frames compartilhados, usando só APIs
//! públicas: Toolbar (ações) + TabBar (filtro) + Table (linhas) +
//! StatusBar (resumo), com button/label/separator como peças. O estado
//! (tarefas, aba, seleção, scroll) é todo do CHAMADOR; os widgets só
//! reportam. Fluxo de eventos em 7 frames: adicionar via toolbar,
//! filtrar por aba, selecionar linha, alternar estado, esvaziar um
//! filtro (placeholder, sem chamar a tabela vazia) e voltar.
//! Sem renderer próprio: só conta comandos (como `minimal.zig`).

const std = @import("std");
const zyntra_ui = @import("zyntra_ui");

const toolbar_mod = zyntra_ui.widgets.toolbar;
const statusbar_mod = zyntra_ui.widgets.statusbar;
const tabbar_mod = zyntra_ui.widgets.tab_bar;
const table_mod = zyntra_ui.widgets.table;
const button_mod = zyntra_ui.widgets.button;
const label_mod = zyntra_ui.widgets.label;

const Task = struct {
    name: [24]u8 = undefined, // lido só em name[0..name_len]
    name_len: usize = 0,
    done: bool = false,

    fn text(self: *const Task) []const u8 {
        return self.name[0..self.name_len];
    }
};

const App = struct {
    tasks: [8]Task = undefined, // usado só em tasks[0..count]
    count: usize = 0,
    tab: usize = 0, // 0=Todas 1=Ativas 2=Prontas
    selected: usize = 0, // linha dentro do filtro atual
    scroll: f32 = 0,
    added: usize = 0,

    fn add(self: *App, name: []const u8) bool {
        if (self.count >= self.tasks.len) return false;
        const t = &self.tasks[self.count];
        const n = @min(name.len, t.name.len);
        @memcpy(t.name[0..n], name[0..n]);
        t.name_len = n;
        t.done = false;
        self.count += 1;
        return true;
    }

    fn visible(self: *App, out: *[8]usize) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const show = switch (self.tab) {
                1 => !self.tasks[i].done,
                2 => self.tasks[i].done,
                else => true,
            };
            if (show) {
                out[n] = i;
                n += 1;
            }
        }
        return n;
    }
};

const FrameActions = struct {
    add_clicked: bool = false,
    toggle_clicked: bool = false,
};

fn drawApp(ctx: *zyntra_ui.Context, app: *App, theme: zyntra_ui.Theme, font: zyntra_ui.FontMetrics) !FrameActions {
    var acts = FrameActions{};

    // Toolbar no topo: Adicionar | Alternar.
    var tb = try toolbar_mod.toolbar(&ctx.*, zyntra_ui.Rect.init(0, 0, 640, 40), theme.toolbarStyle());
    const r_add = tb.nextItem(110);
    const add = try button_mod.button(&ctx.*, zyntra_ui.Id.fromString("app:add"), r_add, theme.buttonStyle());
    if (add.clicked) acts.add_clicked = true;
    try toolbar_mod.toolbarSeparator(&ctx.*, &tb, theme.separatorStyle());
    const r_toggle = tb.nextItem(110);
    const toggle = try button_mod.button(&ctx.*, zyntra_ui.Id.fromString("app:toggle"), r_toggle, theme.buttonStyle());
    if (toggle.clicked) acts.toggle_clicked = true;
    // Rótulos sobre os botões (button desenha só o chrome).
    const la = try label_mod.measure("Adicionar", font);
    _ = try label_mod.label(&ctx.*, zyntra_ui.Id.fromString("app:add-lb"), .{
        .x = r_add.x + (r_add.w - la.width) * 0.5,
        .y = r_add.y + (r_add.h - font.lineHeight()) * 0.5,
        .w = la.width,
        .h = font.lineHeight(),
    }, "Adicionar", theme.text, font, false);
    const lt = try label_mod.measure("Alternar", font);
    _ = try label_mod.label(&ctx.*, zyntra_ui.Id.fromString("app:toggle-lb"), .{
        .x = r_toggle.x + (r_toggle.w - lt.width) * 0.5,
        .y = r_toggle.y + (r_toggle.h - font.lineHeight()) * 0.5,
        .w = lt.width,
        .h = font.lineHeight(),
    }, "Alternar", theme.text, font, false);

    // Abas filtram as linhas (click seleciona; estado no chamador).
    const tabs = [_][]const u8{ "Todas", "Ativas", "Prontas" };
    _ = try tabbar_mod.beginTabBar(&ctx.*, zyntra_ui.Id.fromString("app:tabs"), zyntra_ui.Rect.init(0, 40, 640, 30), &tabs, &app.tab, theme.tabBarStyle());
    tabbar_mod.endTabBar(&ctx.*);

    // Tabela com as linhas visíveis; filtro vazio vira placeholder
    // (a tabela exige >= 1 linha).
    var idx: [8]usize = undefined;
    const nvis = app.visible(&idx);
    if (app.selected >= nvis and nvis > 0) app.selected = nvis - 1;
    const cols = [_]table_mod.TableColumn{
        .{ .title = "Tarefa", .width = 380 },
        .{ .title = "Estado", .width = 220 },
    };
    if (nvis > 0) {
        var cells: [8][2][]const u8 = undefined;
        var rows: [8]table_mod.TableRow = undefined;
        var i: usize = 0;
        while (i < nvis) : (i += 1) {
            const t = &app.tasks[idx[i]];
            cells[i] = .{ t.text(), if (t.done) "pronta" else "ativa" };
            rows[i] = .{ .cells = &cells[i] };
        }
        _ = try table_mod.beginTable(&ctx.*, zyntra_ui.Id.fromString("app:table"), zyntra_ui.Rect.init(0, 70, 640, 302), &cols, rows[0..nvis], &app.selected, &app.scroll, theme.tableStyle());
        table_mod.endTable(&ctx.*);
    } else {
        _ = try label_mod.label(&ctx.*, zyntra_ui.Id.fromString("app:empty"), zyntra_ui.Rect.init(270, 200, 160, 20), "Nenhuma tarefa aqui", theme.text, font, false);
    }

    // StatusBar: resumo à esquerda, aba atual à direita.
    var sb = try statusbar_mod.statusBar(&ctx.*, zyntra_ui.Rect.init(0, 372, 640, 28), theme.statusBarStyle());
    var msg_buf: [48]u8 = undefined;
    const msg = try std.fmt.bufPrint(&msg_buf, "{d} de {d} tarefas", .{ nvis, app.count });
    _ = try statusbar_mod.statusBarText(&ctx.*, &sb, msg, font, theme.text);
    const right_txt = switch (app.tab) {
        1 => "aba: Ativas",
        2 => "aba: Prontas",
        else => "aba: Todas",
    };
    const rm = try label_mod.measure(right_txt, font);
    const rr = sb.nextRight(rm.width + 8);
    _ = try label_mod.label(&ctx.*, zyntra_ui.Id.fromString("app:tab-lb"), .{
        .x = rr.x + 4,
        .y = rr.y + (rr.h - font.lineHeight()) * 0.5,
        .w = rm.width,
        .h = font.lineHeight(),
    }, right_txt, theme.text, font, false);

    return acts;
}

fn pressAt(ctx: *zyntra_ui.Context, x: f32, y: f32) !void {
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(x, y) } });
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(x, y) } });
}

fn releaseAt(ctx: *zyntra_ui.Context, x: f32, y: f32) !void {
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(x, y) } });
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(x, y) } });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 640, 400),
    });
    defer ctx.deinit();

    const theme = zyntra_ui.Theme.darkDefault();
    const font = zyntra_ui.FontMetrics.withSize(10);

    var app = App{};
    std.debug.assert(app.add("Ler docs"));
    std.debug.assert(app.add("Escrever teste"));
    app.tasks[2].name_len = ("Revisar API".len);
    @memcpy(app.tasks[2].name[0.."Revisar API".len], "Revisar API");
    app.tasks[2].done = true;
    app.count = 3;

    // Botão Adicionar: centro de (8,6,110,28).
    const add_xy = .{ 63.0, 20.0 };
    // Botão Alternar: após separador → x=131, centro (186,20).
    const toggle_xy = .{ 186.0, 20.0 };
    // Abas (fonte interna 10, pad 12): Todas 0..54, Ativas 54..114, Prontas 114..180.
    const tab_prontas = .{ 147.0, 55.0 };
    const tab_todas = .{ 27.0, 55.0 };
    // Corpo da tabela começa em y=96, linha 24px: linha 0 → y=108.
    const row0 = .{ 100.0, 108.0 };

    // f1: press em Adicionar.
    ctx.beginFrame();
    try pressAt(&ctx, add_xy[0], add_xy[1]);
    _ = try drawApp(&ctx, &app, theme, font);
    ctx.endFrame();
    // f2: release → adiciona "Nova tarefa 1".
    ctx.beginFrame();
    try releaseAt(&ctx, add_xy[0], add_xy[1]);
    const a2 = try drawApp(&ctx, &app, theme, font);
    if (a2.add_clicked) {
        var nb: [24]u8 = undefined;
        const name = try std.fmt.bufPrint(&nb, "Nova tarefa {d}", .{app.added + 1});
        if (app.add(name)) app.added += 1;
    }
    std.debug.print("app f2 tarefas={d} draws={d}\n", .{ app.count, ctx.drawCommands().len });
    ctx.endFrame();
    std.debug.assert(app.count == 4);

    // f3: aba Prontas (1 linha: Revisar API).
    ctx.beginFrame();
    try pressAt(&ctx, tab_prontas[0], tab_prontas[1]);
    _ = try drawApp(&ctx, &app, theme, font);
    std.debug.print("app f3 aba={d} draws={d}\n", .{ app.tab, ctx.drawCommands().len });
    ctx.endFrame();
    std.debug.assert(app.tab == 2);

    // f4: seleciona a linha 0.
    ctx.beginFrame();
    try pressAt(&ctx, row0[0], row0[1]);
    _ = try drawApp(&ctx, &app, theme, font);
    std.debug.print("app f4 selecionada={d}\n", .{app.selected});
    ctx.endFrame();
    std.debug.assert(app.selected == 0);

    // f5/f6: press+release em Alternar → Revisar API volta a ativa;
    // o filtro Prontas esvazia (placeholder, sem tabela vazia).
    ctx.beginFrame();
    try pressAt(&ctx, toggle_xy[0], toggle_xy[1]);
    _ = try drawApp(&ctx, &app, theme, font);
    ctx.endFrame();
    ctx.beginFrame();
    try releaseAt(&ctx, toggle_xy[0], toggle_xy[1]);
    const a6 = try drawApp(&ctx, &app, theme, font);
    if (a6.toggle_clicked) {
        var idx: [8]usize = undefined;
        const n = app.visible(&idx);
        if (app.selected < n) app.tasks[idx[app.selected]].done = !app.tasks[idx[app.selected]].done;
    }
    var idx6: [8]usize = undefined;
    std.debug.print("app f6 visiveis={d} draws={d}\n", .{ app.visible(&idx6), ctx.drawCommands().len });
    ctx.endFrame();
    {
        var idxc: [8]usize = undefined;
        std.debug.assert(app.visible(&idxc) == 0);
    }

    // f7: volta para Todas (4 linhas de novo).
    ctx.beginFrame();
    try pressAt(&ctx, tab_todas[0], tab_todas[1]);
    _ = try drawApp(&ctx, &app, theme, font);
    var idx7: [8]usize = undefined;
    std.debug.print("app f7 aba={d} visiveis={d} draws={d}\n", .{ app.tab, app.visible(&idx7), ctx.drawCommands().len });
    ctx.endFrame();
    std.debug.assert(app.tab == 0);
}
