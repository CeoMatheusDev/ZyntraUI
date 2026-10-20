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
