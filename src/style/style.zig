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

/// Estilo de caixa agrupadora com título (M73).
/// Ver `widgets/groupbox` para as regras de degradação.
pub const GroupBoxStyle = extern struct {
    /// Preenchimento; transparente (a == 0) ⇒ não desenhado.
    bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    border: types.Color,
    /// Espessura da borda em px (0 ⇒ sem borda).
    border_width: f32 = 1.0,
    /// Cor do texto do título.
    title: types.Color,
    /// Margem interna em px.
    padding: f32 = 8.0,
    /// Vão (px) entre o título e cada segmento do topo.
    title_gap: f32 = 6.0,

    pub fn isValid(self: GroupBoxStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.padding) and self.padding >= 0 and
            std.math.isFinite(self.title_gap) and self.title_gap >= 0;
    }
};

/// Estilo de painel acoplável (M74). Chrome do cabeçalho + métricas.
pub const PanelStyle = extern struct {
    /// Fundo do corpo (transparente, `a == 0` ⇒ não desenhado).
    bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Fundo do cabeçalho (transparente ⇒ não desenhado).
    header_bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Cor da borda.
    border: types.Color,
    /// Espessura da borda em px (0 ⇒ sem borda).
    border_width: f32 = 1.0,
    /// Cor do texto do título.
    title: types.Color,
    /// Cor dos glifos dos controles (chevron/close).
    control: types.Color,
    /// Fundo do controle sob o mouse (transparente ⇒ não desenhado).
    control_hover: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Linha sob o cabeçalho (transparente ⇒ não desenhada).
    separator: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Padding vertical do cabeçalho (altura = `lineHeight + 2*header_pad`).
    header_pad: f32 = 6.0,
    /// Padding horizontal (título) e reserva lateral.
    padding_x: f32 = 8.0,
    /// Padding vertical do conteúdo.
    padding_y: f32 = 8.0,
    /// Largura/altura reservada a cada controle do cabeçalho.
    control_size: f32 = 18.0,

    pub fn isValid(self: PanelStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.header_pad) and self.header_pad >= 0 and
            std.math.isFinite(self.padding_x) and self.padding_x >= 0 and
            std.math.isFinite(self.padding_y) and self.padding_y >= 0 and
            std.math.isFinite(self.control_size) and self.control_size > 0;
    }
};

/// Estilo de área de docking interativa (M76). Espessura e cores das
/// divisórias + fundo/borda opcionais da área. A espessura é única para
/// todo o layout (mesma métrica usada pela geometria de `dock/layout`).
pub const DockStyle = extern struct {
    /// Espessura da faixa da divisória em px (0 ⇒ fina demais p/ hit-test).
    divider: f32 = 6.0,
    /// Cor da divisória em repouso.
    divider_idle: types.Color,
    /// Cor da divisória sob o mouse.
    divider_hover: types.Color,
    /// Cor da divisória durante o arraste.
    divider_drag: types.Color,
    /// Fundo da área de docking (transparente, `a == 0` ⇒ não desenhado).
    bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Borda da área (transparente ou `border_width == 0` ⇒ não desenhada).
    border: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Espessura da borda em px (>= 0).
    border_width: f32 = 1.0,
    /// Realce da zona de acoplamento durante o arraste de um painel
    /// (transparente ⇒ não desenhado).
    drop_preview: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Borda do realce do drop (transparente ⇒ não desenhada).
    drop_border: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },

    pub fn isValid(self: DockStyle) bool {
        return std.math.isFinite(self.divider) and self.divider >= 0 and
            std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Estilo do grafo de nós (M94). Unidades:
/// - **mundo** (escalam com o zoom): `node_radius`, `header_height`,
///   `title_pad`.
/// - **tela** (espessura constante): `grid_target_px`,
///   `node_border_width`, `node_selected_width`, `edge_width`,
///   `port_radius`.
pub const GraphStyle = extern struct {
    /// Fundo da área (transparente, `a == 0` ⇒ não desenhado).
    bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Linhas da grade (transparente ⇒ sem grade).
    grid: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Espaçamento-alvo da grade em px de tela (<= 0 ⇒ sem grade).
    grid_target_px: f32 = 32.0,
    /// Fundo do nó.
    node_bg: types.Color,
    /// Faixa de título do nó (transparente ⇒ só o corpo).
    node_header: types.Color,
    /// Borda do nó (transparente ou largura 0 ⇒ sem borda).
    node_border: types.Color,
    /// Realce externo do nó selecionado.
    node_selected: types.Color,
    /// Espessura da borda do nó em px de tela (>= 0).
    node_border_width: f32 = 1.0,
    /// Espessura do realce de seleção em px de tela (>= 0).
    node_selected_width: f32 = 2.0,
    /// Raio dos cantos do nó em unidades de mundo (0 ⇒ cantos retos).
    node_radius: f32 = 0.0,
    /// Altura da faixa de título em unidades de mundo (clampada ao nó).
    header_height: f32 = 18.0,
    /// Cor do texto do título.
    title: types.Color,
    /// Recuo interno do título em unidades de mundo (>= 0).
    title_pad: f32 = 8.0,
    /// Cor das arestas.
    edge: types.Color,
    /// Espessura das arestas em px de tela (> 0).
    edge_width: f32 = 1.5,
    /// Cor dos pinos (transparente ⇒ sem pinos).
    port: types.Color,
    /// Raio do pino em px de tela (>= 0).
    port_radius: f32 = 3.0,

    pub fn isValid(self: GraphStyle) bool {
        return std.math.isFinite(self.grid_target_px) and
            std.math.isFinite(self.node_border_width) and self.node_border_width >= 0 and
            std.math.isFinite(self.node_selected_width) and self.node_selected_width >= 0 and
            std.math.isFinite(self.node_radius) and self.node_radius >= 0 and
            std.math.isFinite(self.header_height) and self.header_height >= 0 and
            std.math.isFinite(self.title_pad) and self.title_pad >= 0 and
            std.math.isFinite(self.edge_width) and self.edge_width > 0 and
            std.math.isFinite(self.port_radius) and self.port_radius >= 0;
    }
};

/// Estilo de timeline (M95): régua, trilhas, chaves e playhead
/// (ver `widgets/timeline_view`).
///
/// Unidades: todas as métricas são em px de TELA (a timeline não tem
/// zoom de geometria; o zoom é o eixo temporal `pps`).
pub const TimelineStyle = extern struct {
    /// Fundo da área (transparente ⇒ não desenhado).
    bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Fundo da faixa da régua (transparente ⇒ só as marcas).
    ruler_bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Altura da régua em px (0 ⇒ sem régua nem marcas).
    ruler_height: f32 = 22.0,
    /// Cor das marcas da régua.
    tick: types.Color,
    /// Cor dos rótulos da régua.
    tick_label: types.Color,
    /// Espaçamento-alvo mínimo entre marcas/rótulos (px; <= 0 ⇒ sem régua).
    min_tick_px: f32 = 80.0,
    /// Fundo da linha de trilha.
    track_bg: types.Color,
    /// Fundo alternado (linhas ímpares; `a == 0` ⇒ sem alternância).
    track_alt: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Largura da coluna de nomes à esquerda (px; 0 ⇒ sem coluna).
    name_width: f32 = 0.0,
    /// Fundo da coluna de nomes (transparente ⇒ trilhas aparecem).
    names_bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Cor do texto do nome da trilha.
    track_name: types.Color,
    /// Recuo do nome em px (>= 0).
    name_pad: f32 = 6.0,
    /// Linha separadora entre trilhas (transparente ⇒ sem).
    separator: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Altura de cada trilha em px (> 0).
    row_height: f32 = 24.0,
    /// Cor das chaves.
    key: types.Color,
    /// Cor da chave selecionada.
    key_selected: types.Color,
    /// Meia-diagonal do losango da chave em px (>= 0).
    key_size: f32 = 6.0,
    /// Espessura do contorno do losango em px (> 0).
    key_line_width: f32 = 1.5,
    /// Cor do playhead (linha + alça).
    playhead: types.Color,
    /// Espessura da linha do playhead em px (> 0).
    playhead_width: f32 = 1.5,

    pub fn isValid(self: TimelineStyle) bool {
        return std.math.isFinite(self.ruler_height) and self.ruler_height >= 0 and
            std.math.isFinite(self.min_tick_px) and self.min_tick_px >= 0 and
            std.math.isFinite(self.name_width) and self.name_width >= 0 and
            std.math.isFinite(self.name_pad) and self.name_pad >= 0 and
            std.math.isFinite(self.row_height) and self.row_height > 0 and
            std.math.isFinite(self.key_size) and self.key_size >= 0 and
            std.math.isFinite(self.key_line_width) and self.key_line_width > 0 and
            std.math.isFinite(self.playhead_width) and self.playhead_width > 0;
    }
};

/// Estilo de property inspector (M96): linhas nome/valor, editores de
/// bool/número/escolha (ver `widgets/inspector_view`).
///
/// Unidades: px de TELA.
pub const InspectorStyle = extern struct {
    /// Fundo da área (transparente ⇒ não desenhado).
    bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Fundo da linha.
    row_bg: types.Color,
    /// Fundo alternado (linhas ímpares; `a == 0` ⇒ sem alternância).
    row_alt: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Realce da linha ativa (transparente ⇒ sem realce).
    row_active: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Fundo do editor (coluna de valores) em hover/ativa/arraste.
    editor_bg: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Linha separadora entre linhas (transparente ⇒ sem).
    separator: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Cor do nome.
    name: types.Color,
    /// Largura da coluna de nomes em px (>= 0).
    name_width: f32 = 120.0,
    /// Recuo do nome em px (>= 0).
    name_pad: f32 = 8.0,
    /// Recuo do editor na coluna de valores em px (>= 0).
    value_pad: f32 = 6.0,
    /// Altura de cada linha em px (> 0).
    row_height: f32 = 24.0,
    /// Cor do valor editável.
    value: types.Color,
    /// Cor do valor somente-leitura (`text`/`readonly`).
    value_readonly: types.Color,
    /// Lado da caixa de booleano em px (0 ⇒ sem caixa).
    check_size: f32 = 12.0,
    /// Fundo da caixa de booleano.
    check_bg: types.Color,
    /// Borda da caixa de booleano (transparente ou largura 0 ⇒ sem).
    check_border: types.Color,
    /// Espessura da borda da caixa (>= 0).
    check_border_width: f32 = 1.0,
    /// Marca interna da caixa marcada.
    check_mark: types.Color,

    pub fn isValid(self: InspectorStyle) bool {
        return std.math.isFinite(self.name_width) and self.name_width >= 0 and
            std.math.isFinite(self.name_pad) and self.name_pad >= 0 and
            std.math.isFinite(self.value_pad) and self.value_pad >= 0 and
            std.math.isFinite(self.row_height) and self.row_height > 0 and
            std.math.isFinite(self.check_size) and self.check_size >= 0 and
            std.math.isFinite(self.check_border_width) and self.check_border_width >= 0;
    }
};

/// Estilo do fantasma do arraste (M97; ver `widgets/drag_ghost`).
///
/// Unidades: px de TELA.
pub const DragGhostStyle = extern struct {
    /// Fundo da caixa.
    bg: types.Color,
    /// Borda (transparente ou largura 0 ⇒ sem).
    border: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Espessura da borda (>= 0).
    border_width: f32 = 1.0,
    /// Raio dos cantos (0 ⇒ caixa reta).
    radius: f32 = 3.0,
    /// Sombra projetada (transparente ⇒ sem).
    shadow: types.Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    /// Deslocamento da sombra em px (finito).
    shadow_offset: f32 = 2.0,
    /// Raio do desfoque da sombra em px (>= 0).
    shadow_blur: f32 = 4.0,
    /// Cor do rótulo.
    text: types.Color,
    /// Recuo interno em px (>= 0).
    pad: f32 = 6.0,
    /// Deslocamento da caixa em relação ao cursor.
    offset: types.Vec2 = .{ .x = 10, .y = 10 },
    /// Largura mínima da caixa em px (>= 0).
    min_width: f32 = 48.0,

    pub fn isValid(self: DragGhostStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.radius) and self.radius >= 0 and
            std.math.isFinite(self.shadow_offset) and
            std.math.isFinite(self.shadow_blur) and self.shadow_blur >= 0 and
            std.math.isFinite(self.pad) and self.pad >= 0 and
            std.math.isFinite(self.offset.x) and std.math.isFinite(self.offset.y) and
            std.math.isFinite(self.min_width) and self.min_width >= 0;
    }
};

/// Estilo de barra de status (M68). Chrome + métricas de
/// posicionamento dos segmentos (ver `widgets/statusbar`).
pub const StatusBarStyle = extern struct {
    bg: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    padding_x: f32 = 8.0,
    padding_y: f32 = 4.0,
    /// Espaço horizontal entre segmentos (>= 0).
    spacing: f32 = 6.0,
    /// Altura preferida dos segmentos (clampada ao conteúdo).
    item_height: f32 = 20.0,

    pub fn isValid(self: StatusBarStyle) bool {
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

    pub fn statusBarStyle(self: Theme) StatusBarStyle {
        return .{
            .bg = self.surface,
            .border = self.border,
            .border_width = 1.0,
            .padding_x = 8.0,
            .padding_y = 4.0,
            .spacing = 6.0,
            .item_height = 20.0,
        };
    }

    pub fn graphStyle(self: Theme) GraphStyle {
        return .{
            .bg = self.bg,
            .grid = .{ .r = 255, .g = 255, .b = 255, .a = 18 },
            .grid_target_px = 32.0,
            .node_bg = self.surface,
            .node_header = self.accent,
            .node_border = self.border,
            .node_selected = types.Color.rgb(255, 190, 70),
            .node_border_width = 1.0,
            .node_selected_width = 2.0,
            .node_radius = 4.0,
            .header_height = 18.0,
            .title = types.Color.rgb(255, 255, 255),
            .title_pad = 8.0,
            .edge = types.Color.rgb(160, 170, 195),
            .edge_width = 1.5,
            .port = types.Color.rgb(235, 235, 240),
            .port_radius = 3.0,
        };
    }

    pub fn timelineStyle(self: Theme) TimelineStyle {
        return .{
            .bg = self.bg,
            .ruler_bg = types.Color.rgb(38, 38, 44),
            .ruler_height = 22.0,
            .tick = types.Color.rgb(120, 125, 140),
            .tick_label = self.text,
            .min_tick_px = 80.0,
            .track_bg = types.Color.rgb(44, 44, 52),
            .track_alt = types.Color.rgb(38, 38, 45),
            .name_width = 90.0,
            .names_bg = types.Color.rgb(32, 32, 38),
            .track_name = self.text,
            .name_pad = 6.0,
            .separator = types.Color.rgb(70, 70, 80),
            .row_height = 24.0,
            .key = types.Color.rgb(255, 190, 70),
            .key_selected = types.Color.rgb(255, 255, 255),
            .key_size = 6.0,
            .key_line_width = 1.5,
            .playhead = types.Color.rgb(230, 80, 80),
            .playhead_width = 1.5,
        };
    }

    pub fn inspectorStyle(self: Theme) InspectorStyle {
        return .{
            .bg = self.bg,
            .row_bg = self.surface,
            .row_alt = types.Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
            .row_active = types.Color.rgb(60, 84, 120),
            .editor_bg = types.Color.rgb(30, 30, 36),
            .separator = types.Color.rgb(70, 70, 80),
            .name = self.text,
            .name_width = 120.0,
            .name_pad = 8.0,
            .value_pad = 6.0,
            .row_height = 24.0,
            .value = self.text,
            .value_readonly = self.border,
            .check_size = 12.0,
            .check_bg = self.bg,
            .check_border = self.border,
            .check_border_width = 1.0,
            .check_mark = self.accent,
        };
    }

    pub fn dragGhostStyle(self: Theme) DragGhostStyle {
        return .{
            .bg = self.surface,
            .border = self.border,
            .border_width = 1.0,
            .radius = 3.0,
            .shadow = types.Color{ .r = 0, .g = 0, .b = 0, .a = 96 },
            .shadow_offset = 2.0,
            .shadow_blur = 4.0,
            .text = self.text,
            .pad = 6.0,
            .offset = types.Vec2.init(10, 10),
            .min_width = 48.0,
        };
    }

    pub fn groupBoxStyle(self: Theme) GroupBoxStyle {
        return .{
            .border = self.border,
            .title = self.text,
            .border_width = 1.0,
            .padding = 8.0,
            .title_gap = 6.0,
        };
    }

    pub fn panelStyle(self: Theme) PanelStyle {
        return .{
            .bg = self.surface,
            .header_bg = self.bg,
            .border = self.border,
            .border_width = 1.0,
            .title = self.text,
            .control = self.text,
            .control_hover = self.accent,
            .separator = self.border,
            .header_pad = 6.0,
            .padding_x = 8.0,
            .padding_y = 8.0,
            .control_size = 18.0,
        };
    }

    pub fn dockStyle(self: Theme) DockStyle {
        return .{
            .divider = 6.0,
            .divider_idle = self.border,
            .divider_hover = types.Color.rgb(80, 80, 90),
            .divider_drag = self.accent,
            .bg = self.bg,
            .border = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
            .border_width = 1.0,
            .drop_preview = types.Color.init(self.accent.r, self.accent.g, self.accent.b, 80),
            .drop_border = self.accent,
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
    try stdt.testing.expect(dark.statusBarStyle().isValid());
    try stdt.testing.expect(light.statusBarStyle().isValid());
    try stdt.testing.expect(dark.groupBoxStyle().isValid());
    try stdt.testing.expect(light.groupBoxStyle().isValid());
    try stdt.testing.expect(dark.graphStyle().isValid());
    try stdt.testing.expect(light.graphStyle().isValid());
    try stdt.testing.expect(dark.timelineStyle().isValid());
    try stdt.testing.expect(light.timelineStyle().isValid());
    try stdt.testing.expect(dark.inspectorStyle().isValid());
    try stdt.testing.expect(light.inspectorStyle().isValid());
    try stdt.testing.expect(dark.dragGhostStyle().isValid());
    try stdt.testing.expect(light.dragGhostStyle().isValid());
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
