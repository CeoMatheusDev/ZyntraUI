//! ZyntraUI — estilos e temas (style/style).
//!
//! Escopo M3: cores e métricas por valor, sem alocação.
//! `Theme` agrega a paleta; helpers derivam estilos de widgets.
//! Validação: espessuras/raios finitos e >= 0.

const std = @import("std");
const types = @import("../core/types.zig");

/// Estilo de botão por estado.
pub const ButtonStyle = extern struct {
    bg: types.Color,
    bg_hover: types.Color,
    bg_pressed: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    radius: f32 = 0,

    pub fn isValid(self: ButtonStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.radius) and self.radius >= 0;
    }
};

/// Estilo de checkbox.
pub const CheckboxStyle = extern struct {
    box_size: f32 = 18,
    bg: types.Color,
    bg_checked: types.Color,
    border: types.Color,
    check: types.Color,
    border_width: f32 = 1.0,

    pub fn isValid(self: CheckboxStyle) bool {
        return std.math.isFinite(self.box_size) and self.box_size > 0 and
            std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo de slider horizontal.
pub const SliderStyle = extern struct {
    track_height: f32 = 4,
    track_bg: types.Color,
    fill: types.Color,
    handle_w: f32 = 12,
    handle_h: f32 = 20,
    handle_bg: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,

    pub fn isValid(self: SliderStyle) bool {
        return std.math.isFinite(self.track_height) and self.track_height > 0 and
            std.math.isFinite(self.handle_w) and self.handle_w > 0 and
            std.math.isFinite(self.handle_h) and self.handle_h > 0 and
            std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo de campo de texto.
pub const TextInputStyle = extern struct {
    bg: types.Color,
    bg_focus: types.Color,
    border: types.Color,
    border_focus: types.Color,
    text: types.Color,
    caret: types.Color,
    /// Destaque de seleção (M13; default preserva literais antigos).
    selection: types.Color = .{ .r = 70, .g = 110, .b = 180, .a = 90 },
    border_width: f32 = 1.0,

    pub fn isValid(self: TextInputStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo de container com scroll.
pub const ScrollStyle = extern struct {
    bar_width: f32 = 8,
    track: types.Color,
    thumb: types.Color,

    pub fn isValid(self: ScrollStyle) bool {
        return std.math.isFinite(self.bar_width) and self.bar_width > 0;
    }
};

/// Estilo de popup flutuante.
pub const PopupStyle = extern struct {
    bg: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,

    pub fn isValid(self: PopupStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo de grupo de radio.
pub const RadioStyle = extern struct {
    box: types.Color,
    dot: types.Color,
    text: types.Color,
    border_width: f32 = 1.0,
    radio_r: f32 = 7,

    pub fn isValid(self: RadioStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.radio_r) and self.radio_r > 0;
    }
};

/// Estilo de tooltip.
pub const TooltipStyle = extern struct {
    bg: types.Color,
    border: types.Color,
    text: types.Color,
    border_width: f32 = 1.0,
    padding: f32 = 6,

    pub fn isValid(self: TooltipStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.padding) and self.padding >= 0;
    }
};

/// Estilo de janela modal.
pub const ModalStyle = extern struct {
    dim: types.Color,
    bg: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    /// Cor do título (M53; default preserva literais antigos).
    title_text: types.Color = types.Color.rgb(235, 235, 240),

    pub fn isValid(self: ModalStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo de barra de abas (M56).
pub const TabBarStyle = extern struct {
    bg: types.Color,
    bg_active: types.Color,
    bg_hover: types.Color,
    text: types.Color,
    text_active: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    padding_x: f32 = 12.0,
    padding_y: f32 = 6.0,

    pub fn isValid(self: TabBarStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.padding_x) and self.padding_x >= 0 and
            std.math.isFinite(self.padding_y) and self.padding_y >= 0;
    }
};

/// Estilo de splitter arrastável (M57).
pub const SplitterStyle = extern struct {
    bg: types.Color,
    bg_hover: types.Color,
    bg_drag: types.Color,
    handle_w: f32 = 8.0,
    handle_h: f32 = 8.0,

    pub fn isValid(self: SplitterStyle) bool {
        return std.math.isFinite(self.handle_w) and self.handle_w >= 0 and
            std.math.isFinite(self.handle_h) and self.handle_h >= 0;
    }
};

/// Estilo de lista vertical (M58).
pub const ListViewStyle = extern struct {
    bg: types.Color,
    bg_selected: types.Color,
    bg_hover: types.Color,
    text: types.Color,
    text_selected: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    item_height: f32 = 28.0,
    padding_x: f32 = 8.0,

    pub fn isValid(self: ListViewStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.item_height) and self.item_height > 0 and
            std.math.isFinite(self.padding_x) and self.padding_x >= 0;
    }
};

/// Estilo de árvore hierárquica (M59).
pub const TreeViewStyle = extern struct {
    bg: types.Color,
    bg_selected: types.Color,
    bg_hover: types.Color,
    text: types.Color,
    text_selected: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    item_height: f32 = 24.0,
    indent: f32 = 16.0,
    expander_size: f32 = 12.0,

    pub fn isValid(self: TreeViewStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.item_height) and self.item_height > 0 and
            std.math.isFinite(self.indent) and self.indent >= 0 and
            std.math.isFinite(self.expander_size) and self.expander_size > 0;
    }
};

/// Estilo de tabela com header fixo (M62).
pub const TableStyle = extern struct {
    bg: types.Color,
    bg_alt: types.Color,
    bg_selected: types.Color,
    bg_hover: types.Color,
    text: types.Color,
    text_header: types.Color,
    text_selected: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    row_height: f32 = 24.0,
    header_height: f32 = 26.0,
    padding_x: f32 = 8.0,

    pub fn isValid(self: TableStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.row_height) and self.row_height > 0 and
            std.math.isFinite(self.header_height) and self.header_height > 0 and
            std.math.isFinite(self.padding_x) and self.padding_x >= 0;
    }
};

/// Estilo de switch (toggle) (M63).
pub const SwitchStyle = extern struct {
    track: types.Color,
    track_on: types.Color,
    track_hover: types.Color,
    knob: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    knob_pad: f32 = 3.0,

    pub fn isValid(self: SwitchStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.knob_pad) and self.knob_pad >= 0;
    }
};

/// Estilo de spinner de carregamento (M64).
pub const SpinnerStyle = extern struct {
    track: types.Color,
    head: types.Color,
    /// Número de dots no anel (>= 2).
    dots: u8 = 8,
    radius: f32 = 10.0,
    dot_radius: f32 = 2.0,

    pub fn isValid(self: SpinnerStyle) bool {
        return self.dots >= 2 and
            std.math.isFinite(self.radius) and self.radius > 0 and
            std.math.isFinite(self.dot_radius) and self.dot_radius > 0 and
            self.dot_radius <= self.radius;
    }
};

/// Estilo de menu dropdown.
pub const MenuStyle = extern struct {
    bg: types.Color,
    border: types.Color,
    item_hover: types.Color,
    text: types.Color,
    text_disabled: types.Color,
    border_width: f32 = 1.0,

    pub fn isValid(self: MenuStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo de barra de progresso.
pub const ProgressStyle = extern struct {
    bg: types.Color,
    fill: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,

    pub fn isValid(self: ProgressStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo de separador estático (M66).
pub const SeparatorStyle = extern struct {
    color: types.Color,
    /// Espessura da linha em px (> 0).
    thickness: f32 = 1.0,
    /// Vão (px) entre o rótulo e cada segmento da linha (>= 0).
    label_gap: f32 = 6.0,

    pub fn isValid(self: SeparatorStyle) bool {
        return std.math.isFinite(self.thickness) and self.thickness > 0 and
            std.math.isFinite(self.label_gap) and self.label_gap >= 0;
    }
};

/// Estilo de barra de ferramentas (M67). Chrome + métricas de
/// posicionamento dos itens (ver `widgets/toolbar`).
pub const ToolbarStyle = extern struct {
    bg: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    padding_x: f32 = 8.0,
    padding_y: f32 = 6.0,
    /// Espaço horizontal entre itens (> = 0).
    spacing: f32 = 6.0,
    /// Altura preferida dos itens (clampada ao conteúdo).
    item_height: f32 = 28.0,

    pub fn isValid(self: ToolbarStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.padding_x) and self.padding_x >= 0 and
            std.math.isFinite(self.padding_y) and self.padding_y >= 0 and
            std.math.isFinite(self.spacing) and self.spacing >= 0 and
            std.math.isFinite(self.item_height) and self.item_height >= 0;
    }
};

/// Paleta mínima do tema.
pub const Theme = extern struct {
    bg: types.Color,
    surface: types.Color,
    text: types.Color,
    accent: types.Color,
    border: types.Color,

    pub fn darkDefault() Theme {
        return .{
            .bg = types.Color.rgb(24, 24, 28),
            .surface = types.Color.rgb(50, 50, 55),
            .text = types.Color.rgb(235, 235, 240),
            .accent = types.Color.rgb(70, 110, 180),
            .border = types.Color.rgb(255, 255, 255),
        };
    }

    pub fn lightDefault() Theme {
        return .{
            .bg = types.Color.rgb(245, 245, 247),
            .surface = types.Color.rgb(255, 255, 255),
            .text = types.Color.rgb(20, 20, 25),
            .accent = types.Color.rgb(40, 90, 200),
            .border = types.Color.rgb(60, 60, 70),
        };
    }

    pub fn buttonStyle(self: Theme) ButtonStyle {
        return .{
            .bg = self.surface,
            .bg_hover = self.accent,
            .bg_pressed = types.Color.rgb(60, 140, 70),
            .border = self.border,
            .border_width = 1.0,
            .radius = 0,
        };
    }

    pub fn checkboxStyle(self: Theme) CheckboxStyle {
        return .{
            .box_size = 18,
            .bg = self.surface,
            .bg_checked = self.accent,
            .border = self.border,
            .check = types.Color.rgb(255, 255, 255),
            .border_width = 1.0,
        };
    }

    pub fn sliderStyle(self: Theme) SliderStyle {
        return .{
            .track_height = 4,
            .track_bg = self.surface,
            .fill = self.accent,
            .handle_w = 12,
            .handle_h = 20,
            .handle_bg = types.Color.rgb(235, 235, 240),
            .border = self.border,
            .border_width = 1.0,
        };
    }

    pub fn textInputStyle(self: Theme) TextInputStyle {
        return .{
            .bg = types.Color.rgb(18, 18, 22),
            .bg_focus = types.Color.rgb(28, 28, 34),
            .border = self.border,
            .border_focus = self.accent,
            .text = self.text,
            .caret = self.accent,
            .selection = .{ .r = 70, .g = 110, .b = 180, .a = 90 },
            .border_width = 1.0,
        };
    }

    pub fn scrollStyle(self: Theme) ScrollStyle {
        return .{
            .bar_width = 8,
            .track = self.surface,
            .thumb = self.accent,
        };
    }

    pub fn popupStyle(self: Theme) PopupStyle {
        return .{
            .bg = self.surface,
            .border = self.border,
            .border_width = 1.0,
        };
    }

    pub fn menuStyle(self: Theme) MenuStyle {
        return .{
            .bg = self.surface,
            .border = self.border,
            .item_hover = self.accent,
            .text = self.text,
            .text_disabled = types.Color.rgb(120, 120, 130),
            .border_width = 1.0,
        };
    }

    pub fn switchStyle(self: Theme) SwitchStyle {
        return .{
            .track = types.Color.rgb(70, 70, 78),
            .track_on = self.accent,
            .track_hover = types.Color.rgb(90, 90, 100),
            .knob = types.Color.rgb(245, 245, 247),
            .border = self.border,
            .border_width = 1.0,
            .knob_pad = 3.0,
        };
    }

    pub fn progressStyle(self: Theme) ProgressStyle {
        return .{
            .bg = self.surface,
            .fill = self.accent,
            .border = self.border,
            .border_width = 1.0,
        };
    }

    pub fn separatorStyle(self: Theme) SeparatorStyle {
        return .{
            .color = self.border,
            .thickness = 1.0,
            .label_gap = 6.0,
        };
    }

    pub fn toolbarStyle(self: Theme) ToolbarStyle {
        return .{
            .bg = self.surface,
            .border = self.border,
            .border_width = 1.0,
            .padding_x = 8.0,
            .padding_y = 6.0,
            .spacing = 6.0,
            .item_height = 28.0,
        };
    }

    pub fn spinnerStyle(self: Theme) SpinnerStyle {
        return .{
            .track = types.Color.rgb(90, 90, 100),
            .head = self.accent,
            .dots = 8,
            .radius = 10.0,
            .dot_radius = 2.0,
        };
    }

    pub fn radioStyle(self: Theme) RadioStyle {
        return .{
            .box = self.surface,
            .dot = types.Color.rgb(235, 235, 240),
            .text = self.text,
            .border_width = 1.0,
            .radio_r = 7,
        };
    }

    pub fn tooltipStyle(self: Theme) TooltipStyle {
        return .{
            .bg = types.Color.rgb(30, 30, 36),
            .border = self.border,
            .text = self.text,
            .border_width = 1.0,
            .padding = 6,
        };
    }

    pub fn modalStyle(self: Theme) ModalStyle {
        return .{
            .dim = .{ .r = 0, .g = 0, .b = 0, .a = 160 },
            .bg = self.surface,
            .border = self.border,
            .border_width = 1.0,
            .title_text = self.text,
        };
    }

    pub fn tabBarStyle(self: Theme) TabBarStyle {
        return .{
            .bg = self.surface,
            .bg_active = self.accent,
            .bg_hover = types.Color.rgb(80, 80, 90),
            .text = self.text,
            .text_active = types.Color.rgb(255, 255, 255),
            .border = self.border,
            .border_width = 1.0,
            .padding_x = 12.0,
            .padding_y = 6.0,
        };
    }

    pub fn splitterStyle(self: Theme) SplitterStyle {
        return .{
            .bg = self.bg,
            .bg_hover = types.Color.rgb(80, 80, 90),
            .bg_drag = self.accent,
            .handle_w = 8.0,
            .handle_h = 8.0,
        };
    }

    pub fn listViewStyle(self: Theme) ListViewStyle {
        return .{
            .bg = self.surface,
            .bg_selected = self.accent,
            .bg_hover = types.Color.rgb(80, 80, 90),
            .text = self.text,
            .text_selected = types.Color.rgb(255, 255, 255),
            .border = self.border,
            .border_width = 1.0,
            .item_height = 28.0,
            .padding_x = 8.0,
        };
    }

    pub fn treeViewStyle(self: Theme) TreeViewStyle {
        return .{
            .bg = self.surface,
            .bg_selected = self.accent,
            .bg_hover = types.Color.rgb(80, 80, 90),
            .text = self.text,
            .text_selected = types.Color.rgb(255, 255, 255),
            .border = self.border,
            .border_width = 1.0,
            .item_height = 24.0,
            .indent = 16.0,
            .expander_size = 12.0,
        };
    }

    pub fn tableStyle(self: Theme) TableStyle {
        return .{
            .bg = self.surface,
            .bg_alt = types.Color.rgb(48, 48, 56),
            .bg_selected = self.accent,
            .bg_hover = types.Color.rgb(80, 80, 90),
            .text = self.text,
            .text_header = self.text,
            .text_selected = types.Color.rgb(255, 255, 255),
            .border = self.border,
            .border_width = 1.0,
            .row_height = 24.0,
            .header_height = 26.0,
            .padding_x = 8.0,
        };
    }
};

test "Theme defaults + derivados válidos" {
    const stdt = @import("std");
    const dark = Theme.darkDefault();
    const light = Theme.lightDefault();
    try stdt.testing.expect(dark.buttonStyle().isValid());
    try stdt.testing.expect(light.buttonStyle().isValid());
    try stdt.testing.expect(dark.checkboxStyle().isValid());
    try stdt.testing.expect(dark.sliderStyle().isValid());
    try stdt.testing.expect(light.sliderStyle().isValid());
    try stdt.testing.expect(dark.textInputStyle().isValid());
    try stdt.testing.expect(dark.scrollStyle().isValid());
    try stdt.testing.expect(dark.popupStyle().isValid());
    try stdt.testing.expect(dark.tooltipStyle().isValid());
    try stdt.testing.expect(dark.modalStyle().isValid());
    try stdt.testing.expect(dark.radioStyle().isValid());
    try stdt.testing.expect(dark.menuStyle().isValid());
    try stdt.testing.expect(dark.switchStyle().isValid());
    try stdt.testing.expect(light.switchStyle().isValid());
    try stdt.testing.expect(dark.spinnerStyle().isValid());
    try stdt.testing.expect(light.spinnerStyle().isValid());
    try stdt.testing.expect(dark.progressStyle().isValid());
    try stdt.testing.expect(dark.separatorStyle().isValid());
    try stdt.testing.expect(light.separatorStyle().isValid());
    try stdt.testing.expect(dark.toolbarStyle().isValid());
    try stdt.testing.expect(light.toolbarStyle().isValid());
    const bad_btn = ButtonStyle{
        .bg = dark.bg,
        .bg_hover = dark.bg,
        .bg_pressed = dark.bg,
        .border = dark.border,
        .border_width = -1,
    };
    try stdt.testing.expect(!bad_btn.isValid());
    const bad_chk = CheckboxStyle{
        .box_size = 0,
        .bg = dark.bg,
        .bg_checked = dark.bg,
        .border = dark.border,
        .check = dark.text,
    };
    try stdt.testing.expect(!bad_chk.isValid());
}
