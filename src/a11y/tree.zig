//! ZyntraUI — árvore de acessibilidade (a11y/tree).
//!
//! Escopo M164: a ÁRVORE DE ACESSIBILIDADE da UI — o que um leitor de
//! tela (ou qualquer ferramenta de AT) precisa saber sobre o que está
//! na tela.
//! - `Role`: o papel do nó (botão, campo de texto, slider, lista...).
//! - `State`: os estados (focado, desabilitado, marcado, expandido...).
//! - `Node`: um nó da árvore (id da UI, papel, rótulo, valor, caixa e
//!   estado).
//! - `Tree`: a lista de nós do frame (a `Context` a mantém e a zera a
//!   cada frame).
//!
//! O rótulo e o valor são EMPRESTADOS (o app é dono do texto) — valem
//! enquanto o texto do app valer (o frame).
//!
//! A hierarquia é rasa: os containers (painel, groupbox, aba) informam
//! o pai dos filhos; o app monta a árvore final a partir dos nós.

const std = @import("std");
const types = @import("../core/types.zig");

/// Papel de um nó da árvore de acessibilidade.
pub const Role = enum(u8) {
    /// Janela/área da aplicação.
    window = 0,
    /// Agrupamento (painel, groupbox).
    group = 1,
    /// Rótulo estático.
    label = 2,
    /// Botão.
    button = 3,
    /// Botão de dois estados (checkbox, switch).
    toggle_button = 4,
    /// Opção de um grupo (radio).
    radio = 5,
    /// Controle de valor contínuo (slider).
    slider = 6,
    /// Campo de texto de uma linha.
    textbox = 7,
    /// Campo de texto multilinha.
    multiline_textbox = 8,
    /// Imagem/ícone decorativo.
    image = 9,
    /// Barra de progresso.
    progressbar = 10,
    /// Lista de itens.
    listbox = 11,
    /// Item de lista.
    listitem = 12,
    /// Menu.
    menu = 13,
    /// Item de menu.
    menuitem = 14,
    /// Menu suspenso.
    menubar = 15,
    /// Lista de abas.
    tablist = 16,
    /// Aba.
    tab = 17,
    /// Árvore de itens.
    tree = 18,
    /// Item de árvore.
    treeitem = 19,
    /// Separador.
    separator = 20,
    /// Dica (tooltip).
    tooltip = 21,
    /// Superfície de desenho livre.
    canvas = 22,
    /// Lista suspensa (combo).
    combobox = 23,
    /// Papel próprio do app.
    custom = 24,
};

/// Estado de um nó (flags).
pub const State = packed struct(u32) {
    /// O nó tem o foco do teclado.
    focused: bool = false,
    /// O nó está desabilitado.
    disabled: bool = false,
    /// Marcado (checkbox/switch).
    checked: bool = false,
    /// Pressionado neste frame.
    pressed: bool = false,
    /// Expandido (árvore/menu).
    expanded: bool = false,
    /// Selecionado.
    selected: bool = false,
    /// Obrigatório (campo de texto).
    required: bool = false,
    /// Somente leitura.
    readonly: bool = false,
    /// Editável (campo de texto).
    editable: bool = false,
    /// Fora da árvore (não anunciado).
    hidden: bool = false,
    /// Campo multilinha.
    multiline: bool = false,
    _reserved: u21 = 0,

    /// true se nenhum estado está ativo.
    pub fn isEmpty(self: State) bool {
        return @as(u32, @bitCast(self)) == 0;
    }
};

/// Um nó da árvore de acessibilidade.
///
/// Não é `extern struct` (o rótulo e o valor são slices emprestados);
/// a fronteira C achata o nó (ponteiro + comprimento).
pub const Node = struct {
    /// Id do widget (o mesmo id da UI — 0 = id nulo).
    id: u64 = 0,
    /// Papel do nó.
    role: Role = .custom,
    /// Rótulo (EMPRESTADO: o texto do app).
    label: []const u8 = &.{},
    /// Valor (EMPRESTADO: o texto do app) — o texto atual de um campo,
    /// por exemplo.
    value: []const u8 = &.{},
    /// Caixa do nó em pixels lógicos.
    bounds: types.Rect = .{},
    /// Estados do nó.
    state: State = .{},
    /// Id do pai (0 = sem pai).
    parent: u64 = 0,
};

/// A árvore de nós de um frame.
///
/// A `Context` mantém uma árvore e a zera no começo de cada frame; o
/// app consulta depois do `endFrame` (ou durante, para desenhar).
pub const Tree = struct {
    nodes: std.ArrayList(Node) = .empty,

    /// Quantidade de nós.
    pub fn len(self: *const Tree) usize {
        return self.nodes.items.len;
    }

    /// O nó de um índice (null se fora da faixa).
    pub fn at(self: *const Tree, index: usize) ?Node {
        if (index >= self.nodes.items.len) return null;
        return self.nodes.items[index];
    }

    /// Todos os nós.
    pub fn items(self: *const Tree) []const Node {
        return self.nodes.items;
    }

    /// Esvazia a árvore (a capacidade é retida).
    pub fn clear(self: *Tree) void {
        self.nodes.clearRetainingCapacity();
    }

    /// Acrescenta um nó (cresce a lista se preciso).
    pub fn push(self: *Tree, gpa: std.mem.Allocator, node: Node) !void {
        try self.nodes.append(gpa, node);
    }

    /// O primeiro nó com um papel (null se não houver).
    pub fn firstWithRole(self: *const Tree, role: Role) ?Node {
        for (self.nodes.items) |n| {
            if (n.role == role) return n;
        }
        return null;
    }

    /// Os nós com um papel.
    pub fn withRole(self: *const Tree, role: Role, out: []Node) usize {
        var count: usize = 0;
        for (self.nodes.items) |n| {
            if (n.role != role) continue;
            if (count >= out.len) break;
            out[count] = n;
            count += 1;
        }
        return count;
    }
};

/// Uma mudança semântica na árvore (o que o leitor de tela precisa
/// saber entre dois frames).
///
/// As mudanças são calculadas por `diff`: os nós são comparados na
/// ORDEM (a ordem dos widgets é estável no modo imediato) e casados
/// pelo id (0 = nó sem id, casado pela posição).
pub const Change = union(enum) {
    /// Um nó novo (não existia no frame anterior).
    added: Node,
    /// Um nó que saiu (existia no frame anterior).
    removed: Node,
    /// Um nó que ficou, mas mudou (rótulo, valor, estado ou papel).
    updated: struct {
        /// O nó como era.
        before: Node,
        /// O nó como está.
        after: Node,
    },
    /// O foco mudou (de `before` para `after`; `null` = sem foco).
    focus: struct {
        /// O foco anterior (null = nenhum).
        before: ?u64,
        /// O foco novo (null = nenhum).
        after: ?u64,
    },
};

/// Um problema na hierarquia da árvore.
pub const Issue = enum {
    /// O pai declarado não existe na árvore.
    unknown_parent,
    /// O pai vem DEPOIS do filho (a hierarquia deve ser topológica).
    out_of_order_parent,
    /// O nó se declara pai de si mesmo.
    self_parent,
};

/// Valida a hierarquia da árvore (O(n²) no pior caso — a árvore é
/// pequena; use só quando precisar).
///
/// A hierarquia é rasa e explícita: o pai de um nó é o container que
/// estava aberto quando o nó foi registrado.
pub fn validate(tree: *const Tree, out: []Issue) usize {
    var count: usize = 0;
    for (tree.items(), 0..) |node, i| {
        if (node.parent == 0) continue;
        if (node.parent == node.id) {
            if (count >= out.len) return count;
            out[count] = .self_parent;
            count += 1;
            continue;
        }
        var found = false;
        var parent_index: usize = 0;
        for (tree.items(), 0..) |other, j| {
            if (other.id != node.parent) continue;
            found = true;
            parent_index = j;
            break;
        }
        if (!found) {
            if (count >= out.len) return count;
            out[count] = .unknown_parent;
            count += 1;
        } else if (parent_index > i) {
            if (count >= out.len) return count;
            out[count] = .out_of_order_parent;
            count += 1;
        }
    }
    return count;
}

/// Compara o conteúdo de dois nós (ignora a posição e o pai: o que
/// importa para o leitor de tela é o papel, o texto e o estado).
fn sameContent(a: Node, b: Node) bool {
    return a.role == b.role and
        std.mem.eql(u8, a.label, b.label) and
        std.mem.eql(u8, a.value, b.value) and
        @as(u32, @bitCast(a.state)) == @as(u32, @bitCast(b.state));
}

/// As mudanças entre duas árvores (frame anterior → frame atual).
///
/// Os nós são casados na ordem: um id diferente (e não-nulo) é uma
/// troca (remove + adiciona); o mesmo id com conteúdo diferente é uma
/// atualização. Devolve quantas mudanças foram escritas em `out`.
pub fn diff(
    prev: *const Tree,
    cur: *const Tree,
    prev_focus: ?u64,
    cur_focus: ?u64,
    out: []Change,
) usize {
    var count: usize = 0;
    const n = @max(prev.len(), cur.len());
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const before = prev.at(i);
        const after = cur.at(i);
        if (before == null and after == null) break;
        if (before) |b| {
            if (after) |a| {
                // Mesmo id (ou ambos sem id): compara o conteúdo.
                if (b.id == a.id or (b.id == 0 and a.id == 0)) {
                    if (!sameContent(b, a)) {
                        if (count >= out.len) return count;
                        out[count] = .{ .updated = .{ .before = b, .after = a } };
                        count += 1;
                    }
                } else {
                    // O id mudou: o nó saiu e outro entrou.
                    if (count >= out.len) return count;
                    out[count] = .{ .removed = b };
                    count += 1;
                    if (count >= out.len) return count;
                    out[count] = .{ .added = a };
                    count += 1;
                }
            } else {
                if (count >= out.len) return count;
                out[count] = .{ .removed = b };
                count += 1;
            }
        } else if (after) |a| {
            if (count >= out.len) return count;
            out[count] = .{ .added = a };
            count += 1;
        }
    }
    // O foco: só quando muda.
    if (prev_focus != cur_focus) {
        if (count >= out.len) return count;
        out[count] = .{ .focus = .{ .before = prev_focus, .after = cur_focus } };
        count += 1;
    }
    return count;
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test "a11y: a árvore guarda os nós do frame" {
    const gpa = std.testing.allocator;
    var tree = Tree{};
    defer tree.nodes.deinit(gpa);

    try tree.push(gpa, .{ .id = 1, .role = .button, .label = "OK" });
    try tree.push(gpa, .{ .id = 2, .role = .textbox, .label = "Nome", .value = "Zyg" });
    try std.testing.expectEqual(@as(usize, 2), tree.len());
    try std.testing.expectEqual(Role.button, tree.at(0).?.role);
    try std.testing.expectEqualStrings("OK", tree.at(0).?.label);
    try std.testing.expectEqualStrings("Zyg", tree.at(1).?.value);
    try std.testing.expect(tree.at(2) == null);
}

test "a11y: busca por papel" {
    const gpa = std.testing.allocator;
    var tree = Tree{};
    defer tree.nodes.deinit(gpa);
    try tree.push(gpa, .{ .id = 1, .role = .button });
    try tree.push(gpa, .{ .id = 2, .role = .slider });
    try tree.push(gpa, .{ .id = 3, .role = .button });
    try std.testing.expect(tree.firstWithRole(.slider) != null);
    try std.testing.expectEqual(@as(u64, 2), tree.firstWithRole(.slider).?.id);
    var buf: [4]Node = undefined;
    try std.testing.expectEqual(@as(usize, 2), tree.withRole(.button, &buf));
    try std.testing.expectEqual(@as(usize, 0), tree.withRole(.tree, &buf));
}

test "a11y: os estados são flags" {
    var st = State{};
    try std.testing.expect(st.isEmpty());
    st.focused = true;
    st.checked = true;
    try std.testing.expect(!st.isEmpty());
    try std.testing.expect(st.focused);
    try std.testing.expect(st.checked);
    try std.testing.expect(!st.disabled);
}

test "a11y: o diff acusa a entrada, a saída e a mudança" {
    const gpa = std.testing.allocator;
    var prev = Tree{};
    defer prev.nodes.deinit(gpa);
    var cur = Tree{};
    defer cur.nodes.deinit(gpa);

    try prev.push(gpa, .{ .id = 1, .role = .button, .label = "OK" });
    try cur.push(gpa, .{ .id = 1, .role = .button, .label = "Enviar" });
    try cur.push(gpa, .{ .id = 2, .role = .textbox });

    var changes: [8]Change = undefined;
    const n = diff(&prev, &cur, null, null, &changes);
    // Uma atualização (o rótulo) e uma entrada (o novo campo).
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expect(changes[0] == .updated);
    try std.testing.expectEqualStrings("OK", changes[0].updated.before.label);
    try std.testing.expectEqualStrings("Enviar", changes[0].updated.after.label);
    try std.testing.expect(changes[1] == .added);
    try std.testing.expectEqual(@as(u64, 2), changes[1].added.id);

    // Sem mudanças: nada é reportado.
    const n2 = diff(&cur, &cur, null, null, &changes);
    try std.testing.expectEqual(@as(usize, 0), n2);
}

test "a11y: o diff acusa a remoção e a mudança de foco" {
    const gpa = std.testing.allocator;
    var prev = Tree{};
    defer prev.nodes.deinit(gpa);
    var cur = Tree{};
    defer cur.nodes.deinit(gpa);

    try prev.push(gpa, .{ .id = 7, .role = .button });
    var changes: [8]Change = undefined;
    const n = diff(&prev, &cur, 7, null, &changes);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expect(changes[0] == .removed);
    try std.testing.expect(changes[1] == .focus);
    try std.testing.expectEqual(@as(?u64, 7), changes[1].focus.before);
    try std.testing.expectEqual(@as(?u64, null), changes[1].focus.after);
}

test "a11y M167: o diff da Context acusa as mudanças do frame" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const ctx_mod = @import("../core/context.zig");
    const id_mod = @import("../core/id.zig");

    var ctx = try ctx_mod.Context.init(gpa, .{ .viewport = types.Rect.init(0, 0, 100, 100) });
    defer ctx.deinit();
    const id = id_mod.Id.fromString("a11y:btn");

    // Frame 1: o botão entra.
    ctx.beginFrame();
    try ctx.pushA11yWidget(id, .button, types.Rect.init(0, 0, 10, 10), .{});
    ctx.endFrame();
    var changes = ctx.a11yChanges();
    try stdt.testing.expectEqual(@as(usize, 1), changes.len);
    try stdt.testing.expect(changes[0] == .added);

    // Frame 2: nada muda (o nó é o mesmo) ⇒ nenhuma mudança.
    ctx.beginFrame();
    try ctx.pushA11yWidget(id, .button, types.Rect.init(0, 0, 10, 10), .{});
    ctx.endFrame();
    changes = ctx.a11yChanges();
    try stdt.testing.expectEqual(@as(usize, 0), changes.len);

    // Frame 3: o rótulo muda ⇒ uma atualização.
    ctx.beginFrame();
    try ctx.pushA11yWidget(id, .button, types.Rect.init(0, 0, 10, 10), .{});
    ctx.setA11yLabel(id, "Enviar");
    ctx.endFrame();
    changes = ctx.a11yChanges();
    try stdt.testing.expectEqual(@as(usize, 1), changes.len);
    try stdt.testing.expect(changes[0] == .updated);

    // Frame 4: o foco muda ⇒ uma mudança de foco (o rótulo segue).
    ctx.beginFrame();
    try ctx.pushA11yWidget(id, .button, types.Rect.init(0, 0, 10, 10), .{});
    ctx.setA11yLabel(id, "Enviar");
    ctx.focus_owner = id;
    ctx.endFrame();
    changes = ctx.a11yChanges();
    try stdt.testing.expectEqual(@as(usize, 1), changes.len);
    try stdt.testing.expect(changes[0] == .focus);

    // Frame 5: o nó sai ⇒ uma remoção (e o foco some).
    ctx.beginFrame();
    ctx.focus_owner = null;
    ctx.endFrame();
    changes = ctx.a11yChanges();
    try stdt.testing.expectEqual(@as(usize, 2), changes.len);
    try stdt.testing.expect(changes[0] == .removed);
    try stdt.testing.expect(changes[1] == .focus);
}

test "a11y: a validação da hierarquia" {
    const gpa = std.testing.allocator;
    var tree = Tree{};
    defer tree.nodes.deinit(gpa);

    // Sem pai: nada a reclamar.
    try tree.push(gpa, .{ .id = 1, .role = .button });
    var issues: [4]Issue = undefined;
    try std.testing.expectEqual(@as(usize, 0), validate(&tree, &issues));

    // Pai que existe e vem antes: ok.
    try tree.push(gpa, .{ .id = 2, .role = .group });
    try tree.push(gpa, .{ .id = 3, .role = .button, .parent = 2 });
    try std.testing.expectEqual(@as(usize, 0), validate(&tree, &issues));

    // Pai desconhecido.
    try tree.push(gpa, .{ .id = 4, .role = .button, .parent = 99 });
    const n = validate(&tree, &issues);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(Issue.unknown_parent, issues[0]);

    // Pai depois do filho (ordem errada).
    var tree2 = Tree{};
    defer tree2.nodes.deinit(gpa);
    try tree2.push(gpa, .{ .id = 10, .role = .button, .parent = 11 });
    try tree2.push(gpa, .{ .id = 11, .role = .group });
    try std.testing.expectEqual(@as(usize, 1), validate(&tree2, &issues));
    try std.testing.expectEqual(Issue.out_of_order_parent, issues[0]);
}

test "a11y: Context publica mais de 64 mudanças e retém capacidade" {
    const ctx_mod = @import("../core/context.zig");
    const id_mod = @import("../core/id.zig");
    var ctx = try ctx_mod.Context.init(std.testing.allocator, .{});
    defer ctx.deinit();

    ctx.beginFrame();
    for (1..131) |i| {
        try ctx.pushA11y(.{ .id = @intCast(i), .role = .button });
    }
    ctx.focus_owner = id_mod.Id.fromString("focus");
    ctx.endFrame();
    try std.testing.expectEqual(@as(usize, 131), ctx.a11yChanges().len);
    try std.testing.expectEqual(@as(u64, 130), ctx.a11yChanges()[129].added.id);
    try std.testing.expect(ctx.a11yChanges()[130] == .focus);

    // Substituição completa: até duas mudanças por posição, mais foco.
    ctx.beginFrame();
    for (131..261) |i| {
        try ctx.pushA11y(.{ .id = @intCast(i), .role = .button });
    }
    ctx.focus_owner = null;
    ctx.endFrame();
    const changes = ctx.a11yChanges();
    try std.testing.expectEqual(@as(usize, 261), changes.len);
    try std.testing.expectEqual(@as(u64, 130), changes[258].removed.id);
    try std.testing.expectEqual(@as(u64, 260), changes[259].added.id);
    try std.testing.expect(changes[260] == .focus);
    const capacity = ctx.a11y_changes.capacity;
    const ptr = ctx.a11y_changes.items.ptr;

    // Repetir a árvore não gera mudanças e reutiliza o armazenamento.
    ctx.beginFrame();
    for (131..261) |i| {
        try ctx.pushA11y(.{ .id = @intCast(i), .role = .button });
    }
    ctx.endFrame();
    try std.testing.expectEqual(@as(usize, 0), ctx.a11yChanges().len);
    try std.testing.expectEqual(capacity, ctx.a11y_changes.capacity);
    try std.testing.expectEqual(ptr, ctx.a11y_changes.items.ptr);

    ctx.beginFrame();
    ctx.endFrame();
    try std.testing.expectEqual(@as(usize, 130), ctx.a11yChanges().len);
    try std.testing.expectEqual(@as(u64, 260), ctx.a11yChanges()[129].removed.id);
}

test "a11y: falha de reserva não publica diff parcial nem mantém foco obsoleto" {
    const ctx_mod = @import("../core/context.zig");
    const id_mod = @import("../core/id.zig");
    const gpa = std.testing.allocator;
    var ctx = try ctx_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    ctx.beginFrame();
    try ctx.pushA11y(.{ .id = 1, .role = .button });
    const focus = id_mod.Id.fromString("focus");
    ctx.focus_owner = focus;
    var failing = std.testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    ctx.allocator = failing.allocator();
    ctx.endFrame();
    ctx.allocator = gpa;
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), ctx.a11yChanges().len);
    try std.testing.expectEqual(@as(usize, 1), ctx.a11y.len());
    try std.testing.expectEqual(@as(?u64, focus.value()), ctx.a11y_prev_focus);

    ctx.beginFrame();
    try ctx.pushA11y(.{ .id = 1, .role = .button });
    ctx.endFrame();
    try std.testing.expectEqual(@as(usize, 0), ctx.a11yChanges().len);
}
