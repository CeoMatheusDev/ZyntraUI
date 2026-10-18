//! ZyntraUI — tipos C-ABI (c-abi/types).
//!
//! Representação definida para a fronteira C:
//! - Todos os structs são `extern` (layout C garantido).
//! - Tamanhos/alinhamentos travados por asserts de compilação —
//!   qualquer mudança que quebre a ABI falha o build, não o runtime.
//! - `ZyntraResult` tem tag `c_int` explícita; 0 sempre é sucesso.

const std = @import("std");
const raster_mod = @import("../software/raster.zig");
const metrics_mod = @import("../text/metrics.zig");
const style_mod = @import("../style/style.zig");

/// Código de retorno de toda função C-ABI. Sempre por valor, nunca
/// via error union (Zig) ou exceção.
pub const ZyntraResult = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    invalid_event = 3,
    invalid_command = 4,
    invalid_state = 5,
    /// Texto malformado (UTF-8 inválido em text-runs).
    invalid_text = 6,
};

pub const ZyntraVec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const ZyntraSize = extern struct {
    w: f32 = 0,
    h: f32 = 0,
};

pub const ZyntraRect = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const ZyntraColor = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,
};

/// Estatísticas da rasterização de software, devolvidas por
/// `zyntra_framebuffer_render*`. Reexporta o struct `extern` do backend de
/// referência (mesmos campos/ordem) para não haver duas definições; a trava
/// de layout abaixo falha o build se ele mudar.
pub const ZyntraRenderStats = raster_mod.SoftwareStats;

/// Id de widget na fronteira: o mesmo `u64` opaco da API Zig
/// (`Id.fromU64`/`value`). `0` é o id nulo e os widgets o rejeitam.
pub const ZyntraId = u64;

/// Tema embutido usado pelos getters de estilo (`zyntra_style_*`) e por
/// `zyntra_theme_colors`.
pub const ZyntraThemeKind = enum(c_int) {
    dark = 0,
    light = 1,
};

/// Cores base do tema (espelha `style.Theme`; só os cinco tons base).
pub const ZyntraThemeColors = extern struct {
    bg: ZyntraColor = .{},
    surface: ZyntraColor = .{},
    text: ZyntraColor = .{},
    accent: ZyntraColor = .{},
    border: ZyntraColor = .{},
};

/// Orientação de widgets lineares (separador hoje; outros no futuro).
pub const ZyntraOrientation = enum(c_int) {
    horizontal = 0,
    vertical = 1,
};

/// Métricas de texto (reexporta o `extern struct` da API Zig).
pub const ZyntraTextMetrics = metrics_mod.TextMetrics;

/// Fatia de texto emprestada (ptr + len, tamanho fixo): os bytes valem só
/// durante a chamada que a recebe (os widgets copiam para a `DrawList`).
/// `len == 0` aceita `ptr == NULL` (fatia vazia).
pub const ZyntraStr = extern struct {
    ptr: ?[*]const u8 = null,
    len: usize = 0,
};

/// Opções do painel (espelha `panel.PanelOptions`).
pub const ZyntraPanelOptions = extern struct {
    title: ZyntraStr = .{},
    /// Desenha o chevron e permite colapsar (mouse + teclado).
    collapsible: bool = true,
    /// Desenha o `×` e reporta `close_requested`.
    closable: bool = false,
};

/// Item de menu (espelha `menu.MenuItem`): rótulo e atalho emprestados só na
/// chamada; `has_checked == false` = item não marcável (`checked == null`).
pub const ZyntraMenuItem = extern struct {
    label: ZyntraStr = .{},
    shortcut: ZyntraStr = .{},
    enabled: bool = true,
    separator: bool = false,
    has_checked: bool = false,
    checked: bool = false,
};

/// Coluna da tabela (espelha `table.TableColumn`).
pub const ZyntraTableColumn = extern struct {
    title: ZyntraStr = .{},
    width: f32 = 0,
};

/// Linha da tabela (espelha `table.TableRow`): `cells` é o vetor de
/// `ZyntraStr` com um rótulo por coluna (emprestado só na chamada).
pub const ZyntraTableRow = extern struct {
    cells: ?[*]const ZyntraStr = null,
    cells_len: usize = 0,
};

/// Nó de árvore (espelha `tree_view.TreeItem`). `children` aponta para a
/// árvore **do chamador** (mutável) porque `expanded` é o único estado que o
/// widget altera e devolve escrito de volta na árvore; os rótulos são
/// emprestados só durante a chamada.
pub const ZyntraTreeItem = extern struct {
    label: ZyntraStr = .{},
    children: ?[*]ZyntraTreeItem = null,
    children_len: usize = 0,
    expanded: bool = false,
};

// Estilos: reexportados dos `extern struct` da API Zig — uma definição só,
// com a trava de layout abaixo falhando o build se o backend mudar.
pub const ZyntraButtonStyle = style_mod.ButtonStyle;
pub const ZyntraCheckboxStyle = style_mod.CheckboxStyle;
pub const ZyntraSwitchStyle = style_mod.SwitchStyle;
pub const ZyntraSliderStyle = style_mod.SliderStyle;
pub const ZyntraProgressStyle = style_mod.ProgressStyle;
pub const ZyntraSeparatorStyle = style_mod.SeparatorStyle;
pub const ZyntraRadioStyle = style_mod.RadioStyle;
pub const ZyntraTabBarStyle = style_mod.TabBarStyle;
pub const ZyntraListViewStyle = style_mod.ListViewStyle;
pub const ZyntraPanelStyle = style_mod.PanelStyle;
pub const ZyntraMenuStyle = style_mod.MenuStyle;
pub const ZyntraTableStyle = style_mod.TableStyle;
pub const ZyntraTreeViewStyle = style_mod.TreeViewStyle;

// Resultados: definidos aqui como `extern struct` (a API Zig usa structs
// comuns; a cópia campo a campo nos wrappers evita depender do layout deles).
pub const ZyntraLabelResult = extern struct {
    metrics: ZyntraTextMetrics = .{},
    truncated: bool = false,
};

pub const ZyntraButtonResult = extern struct {
    hovered: bool = false,
    pressed: bool = false,
    clicked: bool = false,
};

pub const ZyntraCheckboxResult = extern struct {
    hovered: bool = false,
    toggled: bool = false,
    checked: bool = false,
};

pub const ZyntraSwitchResult = extern struct {
    hovered: bool = false,
    toggled: bool = false,
    checked: bool = false,
    focused: bool = false,
};

pub const ZyntraSliderResult = extern struct {
    value: f32 = 0,
    changed: bool = false,
    hovered: bool = false,
    dragging: bool = false,
};

pub const ZyntraRadioResult = extern struct {
    changed: bool = false,
    hovered: bool = false,
    focused: bool = false,
};

/// Índices opcionais usam `i64` com `-1` = nenhum (evita um `bool` extra por
/// índice e casa com o `?usize` da API Zig).
pub const ZyntraTabBarResult = extern struct {
    changed: bool = false,
    focused: bool = false,
    hovered_index: i64 = -1,
    active: usize = 0,
};

pub const ZyntraListViewResult = extern struct {
    selected: usize = 0,
    hovered_index: i64 = -1,
    scroll_offset: f32 = 0,
    changed: bool = false,
};

pub const ZyntraPanelResult = extern struct {
    /// Área útil para o conteúdo (zerada quando colapsado).
    content: ZyntraRect = .{},
    collapsed: bool = false,
    toggled: bool = false,
    close_requested: bool = false,
    hovered: bool = false,
};

pub const ZyntraMenuResult = extern struct {
    /// Índice escolhido no press/Enter (-1 = nenhum; one-shot).
    chosen: i64 = -1,
    hovered_index: i64 = -1,
    dismissed: bool = false,
    hovered: bool = false,
    focus_parent: bool = false,
};

pub const ZyntraTableResult = extern struct {
    selected: usize = 0,
    hovered_index: i64 = -1,
    scroll_offset: f32 = 0,
    changed: bool = false,
};

pub const ZyntraTreeViewResult = extern struct {
    selected: usize = 0,
    hovered_index: i64 = -1,
    scroll_offset: f32 = 0,
    changed: bool = false,
    /// Nó cujo expansor foi clicado (-1 = nenhum).
    toggled_index: i64 = -1,
};

// Trava de ABI: falhe o build se o layout mudar.
comptime {
    if (@sizeOf(ZyntraResult) != @sizeOf(c_int)) @compileError("ZyntraResult ABI drift");
    if (@sizeOf(ZyntraRenderStats) != 16 or @alignOf(ZyntraRenderStats) != 4) @compileError("ZyntraRenderStats ABI drift");
    if (@sizeOf(ZyntraId) != 8 or @alignOf(ZyntraId) != 8) @compileError("ZyntraId ABI drift");
    if (@sizeOf(ZyntraThemeColors) != 20 or @alignOf(ZyntraThemeColors) != 1) @compileError("ZyntraThemeColors ABI drift");
    if (@sizeOf(ZyntraTextMetrics) != 16 or @alignOf(ZyntraTextMetrics) != 4) @compileError("ZyntraTextMetrics ABI drift");
    if (@sizeOf(ZyntraButtonStyle) != 24 or @alignOf(ZyntraButtonStyle) != 4) @compileError("ZyntraButtonStyle ABI drift");
    if (@sizeOf(ZyntraCheckboxStyle) != 24 or @alignOf(ZyntraCheckboxStyle) != 4) @compileError("ZyntraCheckboxStyle ABI drift");
    if (@sizeOf(ZyntraSwitchStyle) != 28 or @alignOf(ZyntraSwitchStyle) != 4) @compileError("ZyntraSwitchStyle ABI drift");
    if (@sizeOf(ZyntraSliderStyle) != 32 or @alignOf(ZyntraSliderStyle) != 4) @compileError("ZyntraSliderStyle ABI drift");
    if (@sizeOf(ZyntraProgressStyle) != 16 or @alignOf(ZyntraProgressStyle) != 4) @compileError("ZyntraProgressStyle ABI drift");
    if (@sizeOf(ZyntraSeparatorStyle) != 12 or @alignOf(ZyntraSeparatorStyle) != 4) @compileError("ZyntraSeparatorStyle ABI drift");
    if (@sizeOf(ZyntraLabelResult) != 20 or @alignOf(ZyntraLabelResult) != 4) @compileError("ZyntraLabelResult ABI drift");
    if (@sizeOf(ZyntraButtonResult) != 3 or @alignOf(ZyntraButtonResult) != 1) @compileError("ZyntraButtonResult ABI drift");
    if (@sizeOf(ZyntraCheckboxResult) != 3 or @alignOf(ZyntraCheckboxResult) != 1) @compileError("ZyntraCheckboxResult ABI drift");
    if (@sizeOf(ZyntraSwitchResult) != 4 or @alignOf(ZyntraSwitchResult) != 1) @compileError("ZyntraSwitchResult ABI drift");
    if (@sizeOf(ZyntraSliderResult) != 8 or @alignOf(ZyntraSliderResult) != 4) @compileError("ZyntraSliderResult ABI drift");
    if (@sizeOf(ZyntraStr) != 16 or @alignOf(ZyntraStr) != 8) @compileError("ZyntraStr ABI drift");
    if (@sizeOf(ZyntraPanelOptions) != 24 or @alignOf(ZyntraPanelOptions) != 8) @compileError("ZyntraPanelOptions ABI drift");
    if (@sizeOf(ZyntraRadioStyle) != 20 or @alignOf(ZyntraRadioStyle) != 4) @compileError("ZyntraRadioStyle ABI drift");
    if (@sizeOf(ZyntraTabBarStyle) != 36 or @alignOf(ZyntraTabBarStyle) != 4) @compileError("ZyntraTabBarStyle ABI drift");
    if (@sizeOf(ZyntraListViewStyle) != 36 or @alignOf(ZyntraListViewStyle) != 4) @compileError("ZyntraListViewStyle ABI drift");
    if (@sizeOf(ZyntraPanelStyle) != 48 or @alignOf(ZyntraPanelStyle) != 4) @compileError("ZyntraPanelStyle ABI drift");
    if (@sizeOf(ZyntraRadioResult) != 3 or @alignOf(ZyntraRadioResult) != 1) @compileError("ZyntraRadioResult ABI drift");
    if (@sizeOf(ZyntraTabBarResult) != 24 or @alignOf(ZyntraTabBarResult) != 8) @compileError("ZyntraTabBarResult ABI drift");
    if (@sizeOf(ZyntraListViewResult) != 24 or @alignOf(ZyntraListViewResult) != 8) @compileError("ZyntraListViewResult ABI drift");
    if (@sizeOf(ZyntraPanelResult) != 20 or @alignOf(ZyntraPanelResult) != 4) @compileError("ZyntraPanelResult ABI drift");
    if (@sizeOf(ZyntraMenuItem) != 40 or @alignOf(ZyntraMenuItem) != 8) @compileError("ZyntraMenuItem ABI drift");
    if (@sizeOf(ZyntraTableColumn) != 24 or @alignOf(ZyntraTableColumn) != 8) @compileError("ZyntraTableColumn ABI drift");
    if (@sizeOf(ZyntraTableRow) != 16 or @alignOf(ZyntraTableRow) != 8) @compileError("ZyntraTableRow ABI drift");
    if (@sizeOf(ZyntraMenuStyle) != 24 or @alignOf(ZyntraMenuStyle) != 4) @compileError("ZyntraMenuStyle ABI drift");
    if (@sizeOf(ZyntraTableStyle) != 48 or @alignOf(ZyntraTableStyle) != 4) @compileError("ZyntraTableStyle ABI drift");
    if (@sizeOf(ZyntraMenuResult) != 24 or @alignOf(ZyntraMenuResult) != 8) @compileError("ZyntraMenuResult ABI drift");
    if (@sizeOf(ZyntraTableResult) != 24 or @alignOf(ZyntraTableResult) != 8) @compileError("ZyntraTableResult ABI drift");
    if (@sizeOf(ZyntraTreeItem) != 40 or @alignOf(ZyntraTreeItem) != 8) @compileError("ZyntraTreeItem ABI drift");
    if (@sizeOf(ZyntraTreeViewStyle) != 40 or @alignOf(ZyntraTreeViewStyle) != 4) @compileError("ZyntraTreeViewStyle ABI drift");
    if (@sizeOf(ZyntraTreeViewResult) != 32 or @alignOf(ZyntraTreeViewResult) != 8) @compileError("ZyntraTreeViewResult ABI drift");
    if (@sizeOf(ZyntraVec2) != 8 or @alignOf(ZyntraVec2) != 4) @compileError("ZyntraVec2 ABI drift");
    if (@sizeOf(ZyntraSize) != 8 or @alignOf(ZyntraSize) != 4) @compileError("ZyntraSize ABI drift");
    if (@sizeOf(ZyntraRect) != 16 or @alignOf(ZyntraRect) != 4) @compileError("ZyntraRect ABI drift");
    if (@sizeOf(ZyntraColor) != 4 or @alignOf(ZyntraColor) != 1) @compileError("ZyntraColor ABI drift");
    std.debug.assert(@backingInt(ZyntraResult.ok) == 0);
}

test "C-ABI tipos: tamanhos e ok==0" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(usize, 8), @sizeOf(ZyntraVec2));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraRect));
    try stdt.testing.expectEqual(@as(usize, 4), @sizeOf(ZyntraColor));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraRenderStats));
    try stdt.testing.expectEqual(@as(usize, 8), @sizeOf(ZyntraId));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraButtonStyle));
    try stdt.testing.expectEqual(@as(usize, 3), @sizeOf(ZyntraButtonResult));
    try stdt.testing.expectEqual(@as(usize, 20), @sizeOf(ZyntraLabelResult));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraStr));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraPanelOptions));
    try stdt.testing.expectEqual(@as(usize, 20), @sizeOf(ZyntraRadioStyle));
    try stdt.testing.expectEqual(@as(usize, 48), @sizeOf(ZyntraPanelStyle));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraTabBarResult));
    try stdt.testing.expectEqual(@as(usize, 40), @sizeOf(ZyntraMenuItem));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraTableColumn));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraTableRow));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraMenuStyle));
    try stdt.testing.expectEqual(@as(usize, 48), @sizeOf(ZyntraTableStyle));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraMenuResult));
    try stdt.testing.expectEqual(@as(usize, 40), @sizeOf(ZyntraTreeItem));
    try stdt.testing.expectEqual(@as(usize, 40), @sizeOf(ZyntraTreeViewStyle));
    try stdt.testing.expectEqual(@as(usize, 32), @sizeOf(ZyntraTreeViewResult));
    try stdt.testing.expectEqual(@as(c_int, 0), @backingInt(ZyntraResult.ok));
    try stdt.testing.expectEqual(@as(i32, 0), @backingInt(ZyntraThemeKind.dark));
    try stdt.testing.expectEqual(@as(i32, 1), @backingInt(ZyntraThemeKind.light));
}
