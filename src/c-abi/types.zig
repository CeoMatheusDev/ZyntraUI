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
const event_mod = @import("../event/event.zig");
const dock_layout_mod = @import("../dock/layout.zig");

/// Teclas normalizadas na fronteira C (espelha `event.Key`): os valores são
/// os mesmos da API Zig e estáveis — teclas novas entram depois das atuais.
pub const ZyntraKey = enum(c_int) {
    unknown = 0,
    escape = 1,
    enter = 2,
    tab = 3,
    space = 4,
    backspace = 5,
    left = 6,
    right = 7,
    up = 8,
    down = 9,
    a = 10,
    c = 11,
    v = 12,
    x = 13,
    z = 14,
    delete = 15,
    home = 16,
    end = 17,
    y = 18,
    page_up = 19,
    page_down = 20,
};

/// Máscaras de modificadores de `zyntra_context_push_key` (bit 0 = shift,
/// 1 = ctrl, 2 = alt, 3 = super); bits reservados ⇒ argumento inválido.
pub const key_modifiers_mask: u8 = 0x0F;

comptime {
    // Trava: toda tecla da fronteira C tem o mesmo nome e valor em `event.Key`.
    @setEvalBranchQuota(50_000);
    const einfo = @typeInfo(ZyntraKey).@"enum";
    for (einfo.field_names, einfo.field_values) |name, value| {
        const zig_key = std.meta.stringToEnum(event_mod.Key, name) orelse
            @compileError("ZyntraKey sem par em event.Key: " ++ name);
        if (@backingInt(zig_key) != value) {
            @compileError("ZyntraKey com valor divergente de event.Key: " ++ name);
        }
    }
    // Trava: toda zona da fronteira C tem o mesmo nome e valor em `DockZone`.
    @setEvalBranchQuota(50_000);
    const dinfo = @typeInfo(ZyntraDockZone).@"enum";
    for (dinfo.field_names, dinfo.field_values) |name, value| {
        const zig_zone = std.meta.stringToEnum(dock_layout_mod.DockZone, name) orelse
            @compileError("ZyntraDockZone sem par em DockZone: " ++ name);
        if (@backingInt(zig_zone) != value) {
            @compileError("ZyntraDockZone com valor divergente de DockZone: " ++ name);
        }
    }
    // Trava: as máscaras documentadas coincidem com os bits de `Modifiers`.
    if (@as(u8, @bitCast(event_mod.Modifiers{})) != 0) @compileError("Modifiers: base não-zero");
    if (@as(u8, @bitCast(event_mod.Modifiers{ .shift = true })) != 0x01) @compileError("Modifiers: shift != bit 0");
    if (@as(u8, @bitCast(event_mod.Modifiers{ .ctrl = true })) != 0x02) @compileError("Modifiers: ctrl != bit 1");
    if (@as(u8, @bitCast(event_mod.Modifiers{ .alt = true })) != 0x04) @compileError("Modifiers: alt != bit 2");
    if (@as(u8, @bitCast(event_mod.Modifiers{ .super = true })) != 0x08) @compileError("Modifiers: super != bit 3");
}

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
/// Mesmo estilo para o campo de texto e a área de texto (como na API Zig).
pub const ZyntraTextInputStyle = style_mod.TextInputStyle;
/// Estilos dos widgets de composição/exibição (M115): splitter, spinner,
/// groupbox e tooltip. O combo reusa `ZyntraButtonStyle`/`ZyntraMenuStyle`.
pub const ZyntraSplitterStyle = style_mod.SplitterStyle;
pub const ZyntraSpinnerStyle = style_mod.SpinnerStyle;
pub const ZyntraGroupBoxStyle = style_mod.GroupBoxStyle;
pub const ZyntraTooltipStyle = style_mod.TooltipStyle;

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

/// Resultado do campo de texto. `undone`/`redone` são sempre `false` nas
/// variantes expostas aqui: undo/redo exigem o histórico comptime das
/// variantes Zig `textInputHistory`/`textInputClipboard`.
pub const ZyntraTextInputResult = extern struct {
    focused: bool = false,
    changed: bool = false,
    submitted: bool = false,
    overflowed: bool = false,
    selected: bool = false,
    undone: bool = false,
    redone: bool = false,
    len: usize = 0,
};

/// Resultado da área de texto multilinha (mesma ressalva de undo/redo;
/// sem `submitted`, que é do campo de linha única).
pub const ZyntraTextAreaResult = extern struct {
    focused: bool = false,
    changed: bool = false,
    overflowed: bool = false,
    selected: bool = false,
    undone: bool = false,
    redone: bool = false,
    len: usize = 0,
};

/// Resultado do combo (M115): `changed` quando a escolha mudou de índice
/// e `open` o estado do dropdown depois do frame.
pub const ZyntraComboResult = extern struct {
    changed: bool = false,
    open: bool = false,
};

/// Resultado do splitter (M115): `pos` é a posição (clampada) da divisória.
pub const ZyntraSplitterResult = extern struct {
    pos: f32 = 0,
    changed: bool = false,
    hovered: bool = false,
    dragging: bool = false,
};

/// Estado retido do tooltip (M115), do chamador — um por tooltip.
pub const ZyntraTooltipState = extern struct {
    hover_frames: u32 = 0,
};

/// Resultado do tooltip (M115).
pub const ZyntraTooltipResult = extern struct {
    visible: bool = false,
    hovered: bool = false,
};

/// Zona de acoplamento de um drop (espelha `dock.DockZone`; mesmos valores).
pub const ZyntraDockZone = enum(c_int) {
    left = 0,
    right = 1,
    top = 2,
    bottom = 3,
    center = 4,
};

/// Grupo de painéis acoplados como abas (espelha `dock.DockGroup`):
/// `panes[0..count]` em ordem e `active` é o índice da aba visível.
pub const ZyntraDockGroup = extern struct {
    panes: [dock_layout_mod.DockGroup.max_tabs]u16 = .{ 0, 0, 0, 0 },
    count: u8 = 0,
    active: u8 = 0,
};

/// Grupo da folha `node` + rect onde o chamador desenha o corpo/abas
/// (espelha `dock.DockPaneInfo`).
pub const ZyntraDockPaneInfo = extern struct {
    /// Índice do nó da folha (aceito por `zyntra_dock_group`/
    /// `zyntra_dock_set_active_tab`).
    node: u8 = 0,
    group: ZyntraDockGroup = .{},
    rect: ZyntraRect = .{},
};

/// Divisória de um split (espelha `dock.DockSplitInfo`). `orientation` usa
/// os valores de `ZYNTRA_HORIZONTAL`/`ZYNTRA_VERTICAL` (1 byte, como no
/// layout interno).
pub const ZyntraDockSplitInfo = extern struct {
    node: u8 = 0,
    orientation: u8 = 0,
    ratio: f32 = 0,
    rect: ZyntraRect = .{},
    divider: ZyntraRect = .{},
};

/// Prévia/aplicação de um drop de painel: `pane` arrastado sobre `target`
/// na `zone`, com o rect do realce.
pub const ZyntraDockDrop = extern struct {
    pane: u16 = 0,
    target: u16 = 0,
    zone: ZyntraDockZone = .center,
    rect: ZyntraRect = .{},
};

/// Resultado do frame de `zyntra_widget_dock_view`. Índices opcionais são
/// `i64` com `-1` = nenhum; `drop`/`dropped` valem só com `has_drop`/
/// `has_dropped` verdadeiros.
pub const ZyntraDockViewResult = extern struct {
    /// Grupos escritos no buffer de panes do chamador.
    pane_count: usize = 0,
    /// Divisórias do layout (uma por split).
    split_count: usize = 0,
    /// A geometria mudou neste frame (arraste/teclado/drop).
    changed: bool = false,
    has_drop: bool = false,
    has_dropped: bool = false,
    /// Índice (ordem de `zyntra_dock_splits`) da divisória sob o mouse.
    hovered: i64 = -1,
    /// Índice da divisória em arraste.
    dragging: i64 = -1,
    /// Zona de acoplamento sob o cursor (prévia), se houver.
    drop: ZyntraDockDrop = .{},
    /// Drop aplicado neste frame (o chamador limpa o estado de arraste).
    dropped: ZyntraDockDrop = .{},
};

/// Estilo do docking (mesmo `DockStyle` do tema embutido).
pub const ZyntraDockStyle = style_mod.DockStyle;

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
    if (@sizeOf(ZyntraTextInputStyle) != 32 or @alignOf(ZyntraTextInputStyle) != 4) @compileError("ZyntraTextInputStyle ABI drift");
    if (@sizeOf(ZyntraTextInputResult) != 16 or @alignOf(ZyntraTextInputResult) != 8) @compileError("ZyntraTextInputResult ABI drift");
    if (@sizeOf(ZyntraTextAreaResult) != 16 or @alignOf(ZyntraTextAreaResult) != 8) @compileError("ZyntraTextAreaResult ABI drift");
    if (@sizeOf(ZyntraSplitterStyle) != 20 or @alignOf(ZyntraSplitterStyle) != 4) @compileError("ZyntraSplitterStyle ABI drift");
    if (@sizeOf(ZyntraSpinnerStyle) != 20 or @alignOf(ZyntraSpinnerStyle) != 4) @compileError("ZyntraSpinnerStyle ABI drift");
    if (@sizeOf(ZyntraGroupBoxStyle) != 24 or @alignOf(ZyntraGroupBoxStyle) != 4) @compileError("ZyntraGroupBoxStyle ABI drift");
    if (@sizeOf(ZyntraTooltipStyle) != 20 or @alignOf(ZyntraTooltipStyle) != 4) @compileError("ZyntraTooltipStyle ABI drift");
    if (@sizeOf(ZyntraComboResult) != 2 or @alignOf(ZyntraComboResult) != 1) @compileError("ZyntraComboResult ABI drift");
    if (@sizeOf(ZyntraSplitterResult) != 8 or @alignOf(ZyntraSplitterResult) != 4) @compileError("ZyntraSplitterResult ABI drift");
    if (@sizeOf(ZyntraTooltipState) != 4 or @alignOf(ZyntraTooltipState) != 4) @compileError("ZyntraTooltipState ABI drift");
    if (@sizeOf(ZyntraTooltipResult) != 2 or @alignOf(ZyntraTooltipResult) != 1) @compileError("ZyntraTooltipResult ABI drift");
    if (@sizeOf(ZyntraDockGroup) != @sizeOf(dock_layout_mod.DockGroup) or
        @alignOf(ZyntraDockGroup) != @alignOf(dock_layout_mod.DockGroup))
    {
        @compileError("ZyntraDockGroup ABI drift");
    }
    if (@sizeOf(ZyntraDockPaneInfo) != 28 or @alignOf(ZyntraDockPaneInfo) != 4) @compileError("ZyntraDockPaneInfo ABI drift");
    if (@sizeOf(ZyntraDockSplitInfo) != 40 or @alignOf(ZyntraDockSplitInfo) != 4) @compileError("ZyntraDockSplitInfo ABI drift");
    if (@sizeOf(ZyntraDockDrop) != 24 or @alignOf(ZyntraDockDrop) != 4) @compileError("ZyntraDockDrop ABI drift");
    if (@sizeOf(ZyntraDockViewResult) != 88 or @alignOf(ZyntraDockViewResult) != 8) @compileError("ZyntraDockViewResult ABI drift");
    if (@sizeOf(ZyntraDockStyle) != 36 or @alignOf(ZyntraDockStyle) != 4) @compileError("ZyntraDockStyle ABI drift");
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
    try stdt.testing.expectEqual(@as(usize, 32), @sizeOf(ZyntraTextInputStyle));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraTextInputResult));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraTextAreaResult));
    // Widgets M115: estilos e resultados (composição/exibição).
    try stdt.testing.expectEqual(@as(usize, 20), @sizeOf(ZyntraSplitterStyle));
    try stdt.testing.expectEqual(@as(usize, 20), @sizeOf(ZyntraSpinnerStyle));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraGroupBoxStyle));
    try stdt.testing.expectEqual(@as(usize, 20), @sizeOf(ZyntraTooltipStyle));
    try stdt.testing.expectEqual(@as(usize, 2), @sizeOf(ZyntraComboResult));
    try stdt.testing.expectEqual(@as(usize, 8), @sizeOf(ZyntraSplitterResult));
    try stdt.testing.expectEqual(@as(usize, 4), @sizeOf(ZyntraTooltipState));
    try stdt.testing.expectEqual(@as(usize, 2), @sizeOf(ZyntraTooltipResult));
    // Docking: espelhos do modelo e do resultado da área interativa.
    try stdt.testing.expectEqual(@as(usize, 10), @sizeOf(ZyntraDockGroup));
    try stdt.testing.expectEqual(@as(usize, 28), @sizeOf(ZyntraDockPaneInfo));
    try stdt.testing.expectEqual(@as(usize, 40), @sizeOf(ZyntraDockSplitInfo));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraDockDrop));
    try stdt.testing.expectEqual(@as(usize, 88), @sizeOf(ZyntraDockViewResult));
    try stdt.testing.expectEqual(@as(usize, 36), @sizeOf(ZyntraDockStyle));
    try stdt.testing.expectEqual(@as(i32, 0), @backingInt(ZyntraDockZone.left));
    try stdt.testing.expectEqual(@as(i32, 4), @backingInt(ZyntraDockZone.center));
    try stdt.testing.expect(std.enums.fromInt(ZyntraDockZone, 9) == null);
    try stdt.testing.expectEqual(@as(c_int, 0), @backingInt(ZyntraResult.ok));
    try stdt.testing.expectEqual(@as(i32, 0), @backingInt(ZyntraThemeKind.dark));
    try stdt.testing.expectEqual(@as(i32, 1), @backingInt(ZyntraThemeKind.light));
    // Teclas/máscaras da fronteira C espelham a entrada Zig.
    try stdt.testing.expectEqual(@as(i32, @backingInt(event_mod.Key.enter)), @backingInt(ZyntraKey.enter));
    try stdt.testing.expectEqual(@as(i32, @backingInt(event_mod.Key.page_down)), @backingInt(ZyntraKey.page_down));
    try stdt.testing.expectEqual(@as(usize, 21), @typeInfo(ZyntraKey).@"enum".field_names.len);
    // Enum fechado: valor desconhecido não vira tecla.
    try stdt.testing.expect(std.enums.fromInt(ZyntraKey, 999) == null);
    try stdt.testing.expect(std.enums.fromInt(ZyntraKey, 0) != null);
    try stdt.testing.expectEqual(@as(u8, 0x0F), key_modifiers_mask);
    try stdt.testing.expectEqual(@as(u8, 0x02), @as(u8, @bitCast(event_mod.Modifiers{ .ctrl = true })));
}
