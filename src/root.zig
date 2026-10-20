//! ZyntraUI — API pública (root).
//!
//! Esta é a única porta de entrada suportada:
//! `@import("zyntra_ui")`. Módulos internos não são importados
//! diretamente por consumidores.
//!
//! Convenções:
//! - Nomes públicos em `snake_case` para valores e `UpperCamelCase`
//!   para tipos, seguindo o std do Zig.
//! - Quebras de compatibilidade exigem MAJOR bump (ver CHANGELOG).

pub const core = struct {
    pub const types = @import("core/types.zig");
    pub const context = @import("core/context.zig");
    pub const id = @import("core/id.zig");
    pub const scale = @import("core/scale.zig");
};

pub const event = struct {
    pub const event_mod = @import("event/event.zig");
};

pub const draw = struct {
    pub const commands = @import("draw/commands.zig");
    pub const renderer = @import("draw/renderer.zig");
    pub const image = @import("draw/image.zig");
};

pub const text = struct {
    pub const metrics = @import("text/metrics.zig");
    pub const wrap = @import("text/wrap.zig");
    pub const atlas = @import("text/atlas.zig");
    pub const ime = @import("text/ime.zig");
};

pub const c_abi = struct {
    pub const types = @import("c-abi/types.zig");
    pub const api = @import("c-abi/api.zig");
};

pub const software = struct {
    pub const raster = @import("software/raster.zig");
};

pub const anim = struct {
    pub const anim_mod = @import("anim/anim.zig");
};

pub const layout = struct {
    pub const layout_mod = @import("layout/layout.zig");
};

pub const style = struct {
    pub const style_mod = @import("style/style.zig");
};

pub const dock = struct {
    pub const layout = @import("dock/layout.zig");
    pub const serialize = @import("dock/serialize.zig");
};

pub const graph = struct {
    pub const view = @import("graph/view.zig");
};

pub const inspector = struct {
    pub const view = @import("inspector/view.zig");
};

pub const dnd = struct {
    pub const service = @import("dnd/service.zig");
};

pub const timeline = struct {
    pub const view = @import("timeline/view.zig");
};

pub const window = struct {
    pub const registry = @import("window/registry.zig");
    pub const input = @import("window/input.zig");
    pub const compositor = @import("window/compositor.zig");
    pub const decorations = @import("window/decorations.zig");
    pub const interact = @import("window/interact.zig");
};

pub const widgets = struct {
    pub const button = @import("widgets/button.zig");
    pub const checkbox = @import("widgets/checkbox.zig");
    pub const label = @import("widgets/label.zig");
    pub const slider = @import("widgets/slider.zig");
    pub const text_input = @import("widgets/text_input.zig");
    pub const scroll = @import("widgets/scroll.zig");
    pub const popup = @import("widgets/popup.zig");
    pub const progress = @import("widgets/progress.zig");
    pub const menu = @import("widgets/menu.zig");
    pub const radio = @import("widgets/radio.zig");
    pub const tooltip = @import("widgets/tooltip.zig");
    pub const modal = @import("widgets/modal.zig");
    pub const combo = @import("widgets/combo.zig");
    pub const tab_bar = @import("widgets/tab_bar.zig");
    pub const splitter = @import("widgets/splitter.zig");
    pub const list_view = @import("widgets/list_view.zig");
    pub const tree_view = @import("widgets/tree_view.zig");
    pub const table = @import("widgets/table.zig");
    /// `switch` é palavra reservada em Zig; o campo usa identificador
    /// escapado. Acesse via `widgets.@"switch"`.
    pub const @"switch" = @import("widgets/switch.zig");
    pub const spinner = @import("widgets/spinner.zig");
    pub const textarea = @import("widgets/textarea.zig");
    pub const separator = @import("widgets/separator.zig");
    pub const toolbar = @import("widgets/toolbar.zig");
    pub const statusbar = @import("widgets/statusbar.zig");
    pub const groupbox = @import("widgets/groupbox.zig");
    pub const panel = @import("widgets/panel.zig");
    pub const dock_view = @import("widgets/dock_view.zig");
    pub const graph_view = @import("widgets/graph_view.zig");
    pub const timeline_view = @import("widgets/timeline_view.zig");
    pub const inspector_view = @import("widgets/inspector_view.zig");
    pub const drag_ghost = @import("widgets/drag_ghost.zig");
};

// Re-exportações ergonômicas (M1..M4; compatível com anteriores).
pub const Vec2 = core.types.Vec2;
pub const Size = core.types.Size;
pub const Rect = core.types.Rect;
pub const Color = core.types.Color;
pub const Id = core.id.Id;
pub const Context = core.context.Context;
pub const ContextConfig = core.context.ContextConfig;
pub const ContextError = core.context.ContextError;
pub const DpiScale = core.scale.DpiScale;

pub const Event = event.event_mod.Event;
pub const EventQueue = event.event_mod.EventQueue;
pub const MouseButton = event.event_mod.MouseButton;
pub const Key = event.event_mod.Key;
pub const Modifiers = event.event_mod.Modifiers;

pub const DrawCommand = draw.commands.DrawCommand;
pub const DrawList = draw.commands.DrawList;
pub const Image = draw.image.Image;
pub const ImageRegion = draw.image.Region;
pub const FrameStats = draw.renderer.FrameStats;
pub const NullRenderer = draw.renderer.NullRenderer;
pub const Backend = draw.renderer.Backend;

pub const FontMetrics = text.metrics.FontMetrics;
pub const TextMetrics = text.metrics.TextMetrics;
pub const LineRange = text.wrap.LineRange;
pub const FontAtlas = text.atlas.FontAtlas;
pub const AtlasBuilder = text.atlas.Builder;
pub const GlyphMetrics = text.atlas.GlyphMetrics;
pub const Glyph = text.atlas.Glyph;
pub const ImeComposition = text.ime.Composition;

pub const ZyntraResult = c_abi.types.ZyntraResult;
pub const ZyntraRect = c_abi.types.ZyntraRect;
pub const ZyntraColor = c_abi.types.ZyntraColor;

pub const Ease = anim.anim_mod.Ease;
pub const Tween = anim.anim_mod.Tween;
pub const AnimTimer = anim.anim_mod.AnimTimer;

pub const SoftwareFramebuffer = software.raster.SoftwareFramebuffer;
pub const SoftwareStats = software.raster.SoftwareStats;
pub const Constraints = layout.layout_mod.Constraints;
pub const EdgeInsets = layout.layout_mod.EdgeInsets;
pub const StackPlacer = layout.layout_mod.StackPlacer;
pub const StackDirection = layout.layout_mod.StackDirection;

pub const Theme = style.style_mod.Theme;
pub const ButtonStyle = style.style_mod.ButtonStyle;
pub const CheckboxStyle = style.style_mod.CheckboxStyle;
pub const SliderStyle = style.style_mod.SliderStyle;
pub const TextInputStyle = style.style_mod.TextInputStyle;
pub const ScrollStyle = style.style_mod.ScrollStyle;
pub const PopupStyle = style.style_mod.PopupStyle;
pub const ProgressStyle = style.style_mod.ProgressStyle;
pub const MenuStyle = style.style_mod.MenuStyle;
pub const RadioStyle = style.style_mod.RadioStyle;
pub const TooltipStyle = style.style_mod.TooltipStyle;
pub const ModalStyle = style.style_mod.ModalStyle;
pub const SplitterStyle = style.style_mod.SplitterStyle;
pub const ListViewStyle = style.style_mod.ListViewStyle;
pub const TreeViewStyle = style.style_mod.TreeViewStyle;
pub const TableStyle = style.style_mod.TableStyle;
pub const SwitchStyle = style.style_mod.SwitchStyle;
pub const SpinnerStyle = style.style_mod.SpinnerStyle;
pub const SeparatorStyle = style.style_mod.SeparatorStyle;
pub const SeparatorOrientation = widgets.separator.SeparatorOrientation;
pub const ToolbarStyle = style.style_mod.ToolbarStyle;
pub const Toolbar = widgets.toolbar.Toolbar;
pub const StatusBarStyle = style.style_mod.StatusBarStyle;
pub const StatusBar = widgets.statusbar.StatusBar;
pub const GroupBoxStyle = style.style_mod.GroupBoxStyle;
pub const PanelStyle = style.style_mod.PanelStyle;
pub const GraphStyle = style.style_mod.GraphStyle;
pub const TimelineStyle = style.style_mod.TimelineStyle;
pub const InspectorStyle = style.style_mod.InspectorStyle;
pub const DragGhostStyle = style.style_mod.DragGhostStyle;

pub const ButtonResult = widgets.button.ButtonResult;
pub const CheckboxResult = widgets.checkbox.CheckboxResult;
pub const LabelResult = widgets.label.LabelResult;
pub const SliderResult = widgets.slider.SliderResult;
pub const TextInputResult = widgets.text_input.TextInputResult;
pub const TextHistory = widgets.text_input.TextHistory;
pub const Clipboard = widgets.text_input.Clipboard;
pub const ScrollResult = widgets.scroll.ScrollResult;
pub const PopupResult = widgets.popup.PopupResult;
pub const MenuItem = widgets.menu.MenuItem;
pub const MenuResult = widgets.menu.MenuResult;
pub const RadioResult = widgets.radio.RadioResult;
pub const TooltipState = widgets.tooltip.TooltipState;
pub const TooltipResult = widgets.tooltip.TooltipResult;
pub const ModalResult = widgets.modal.ModalResult;
pub const ModalDragState = widgets.modal.ModalDragState;
pub const ComboResult = widgets.combo.ComboResult;
pub const TabBarResult = widgets.tab_bar.TabBarResult;
pub const SplitterResult = widgets.splitter.SplitterResult;
pub const SplitterOrientation = widgets.splitter.SplitterOrientation;
pub const SplitterPanes = widgets.splitter.SplitterPanes;
pub const DockLayout = dock.layout.DockLayout;
pub const DockGroup = dock.layout.DockGroup;
pub const DockOrientation = dock.layout.DockOrientation;
pub const DockError = dock.layout.DockError;
pub const DockSplitInfo = dock.layout.DockSplitInfo;
pub const DockPaneInfo = dock.layout.DockPaneInfo;
pub const DockZone = dock.layout.DockZone;
pub const DockSerializeError = dock.serialize.Error;
pub const dock_serial_version = dock.serialize.version;
pub const dock_serial_max_size = dock.serialize.max_size;
pub const dockSerializedSize = dock.serialize.dockSerializedSize;
pub const dockSerialVersion = dock.serialize.dockSerialVersion;
pub const dockSerialize = dock.serialize.dockSerialize;
pub const dockDeserialize = dock.serialize.dockDeserialize;
pub const DockStyle = style.style_mod.DockStyle;
pub const DockViewOptions = widgets.dock_view.DockViewOptions;
pub const DockDrop = widgets.dock_view.DockDrop;
pub const DockViewResult = widgets.dock_view.DockViewResult;
pub const DockViewError = widgets.dock_view.DockViewError;
pub const PanelOptions = widgets.panel.PanelOptions;
pub const PanelResult = widgets.panel.PanelResult;
pub const ListViewResult = widgets.list_view.ListViewResult;
pub const TreeViewResult = widgets.tree_view.TreeViewResult;
pub const TreeItem = widgets.tree_view.TreeItem;
pub const TableResult = widgets.table.TableResult;
pub const TableColumn = widgets.table.TableColumn;
pub const TableRow = widgets.table.TableRow;
pub const SwitchResult = widgets.@"switch".SwitchResult;
pub const TextAreaResult = widgets.textarea.TextAreaResult;

pub const GraphTransform = graph.view.Transform;
pub const GraphPortSide = graph.view.PortSide;
pub const GraphNode = graph.view.GraphNode;
pub const GraphEdge = graph.view.GraphEdge;
pub const GraphViewState = widgets.graph_view.GraphViewState;
pub const GraphViewOptions = widgets.graph_view.GraphViewOptions;
pub const GraphViewResult = widgets.graph_view.GraphViewResult;

pub const TimelineTimeTransform = timeline.view.TimeTransform;
pub const TimelineKeyframe = timeline.view.Keyframe;
pub const TimelineTrack = timeline.view.Track;
pub const TimelineKeyRef = timeline.view.KeyRef;
pub const TimelineViewState = widgets.timeline_view.TimelineViewState;
pub const TimelineViewOptions = widgets.timeline_view.TimelineViewOptions;
pub const TimelineViewResult = widgets.timeline_view.TimelineViewResult;
pub const TimelineDragMode = widgets.timeline_view.TimelineDragMode;

pub const InspectorKind = inspector.view.Kind;
pub const InspectorRange = inspector.view.Range;
pub const InspectorChoice = inspector.view.Choice;
pub const InspectorValue = inspector.view.Value;
pub const InspectorProperty = inspector.view.Property;
pub const InspectorViewState = widgets.inspector_view.InspectorViewState;
pub const InspectorViewOptions = widgets.inspector_view.InspectorViewOptions;
pub const InspectorViewResult = widgets.inspector_view.InspectorViewResult;

pub const DndPayload = dnd.service.Payload;
pub const DndDrop = dnd.service.Drop;
pub const DndAcceptResult = dnd.service.AcceptResult;
pub const DndState = dnd.service.State;
pub const DragGhostResult = widgets.drag_ghost.DragGhostResult;

pub const Window = window.registry.Window;
pub const WindowRegistry = window.registry.Registry;
pub const WindowError = window.registry.WindowError;
pub const WindowRoute = window.input.Route;
pub const WindowRouter = window.input.Router;
pub const WindowCompositor = window.compositor.Compositor;
pub const WindowCompositorError = window.compositor.CompositorError;
pub const WindowDecorationStyle = window.decorations.Style;
pub const WindowInteractor = window.interact.Interactor;
pub const WindowInteractOptions = window.interact.Options;
pub const WindowAction = window.interact.Action;
pub const WindowInteractError = window.interact.InteractError;

pub const version_major = core.types.version_major;
pub const version_minor = core.types.version_minor;
pub const version_patch = core.types.version_patch;
pub const version_prerelease = core.types.version_prerelease;

// NOTA (verificado em Zig 0.17.0): arquivos importados mas não
// referenciados sequer são analisados no build da lib, e `export fn`
// deles não é emitido. Esta referência força a análise de
// c-abi/api.zig para que seus símbolos C entrem na lib estática.
comptime {
    _ = c_abi.api;
}

test {
    // Garante que os blocos `test` dos submódulos executem via `zig build test`.
    _ = @import("core/types.zig");
    _ = @import("core/context.zig");
    _ = @import("core/id.zig");
    _ = @import("core/scale.zig");
    _ = @import("event/event.zig");
    _ = @import("draw/commands.zig");
    _ = @import("draw/image.zig");
    _ = @import("layout/layout.zig");
    _ = @import("style/style.zig");
    _ = @import("dock/layout.zig");
    _ = @import("dock/serialize.zig");
    _ = @import("graph/view.zig");
    _ = @import("timeline/view.zig");
    _ = @import("inspector/view.zig");
    _ = @import("window/registry.zig");
    _ = @import("window/input.zig");
    _ = @import("window/compositor.zig");
    _ = @import("window/decorations.zig");
    _ = @import("window/interact.zig");
    _ = @import("dnd/service.zig");
    _ = @import("text/metrics.zig");
    _ = @import("text/wrap.zig");
    _ = @import("text/atlas.zig");
    _ = @import("text/ime.zig");
    _ = @import("draw/renderer.zig");
    _ = @import("c-abi/types.zig");
    _ = @import("c-abi/api.zig");
    _ = @import("anim/anim.zig");
    _ = @import("software/raster.zig");
    _ = @import("widgets/input.zig");
    _ = @import("widgets/button.zig");
    _ = @import("widgets/checkbox.zig");
    _ = @import("widgets/label.zig");
    _ = @import("widgets/slider.zig");
    _ = @import("widgets/text_input.zig");
    _ = @import("widgets/scroll.zig");
    _ = @import("widgets/popup.zig");
    _ = @import("widgets/progress.zig");
    _ = @import("widgets/menu.zig");
    _ = @import("widgets/radio.zig");
    _ = @import("widgets/tooltip.zig");
    _ = @import("widgets/modal.zig");
    _ = @import("widgets/combo.zig");
    _ = @import("widgets/tab_bar.zig");
    _ = @import("widgets/splitter.zig");
    _ = @import("widgets/list_view.zig");
    _ = @import("widgets/tree_view.zig");
    _ = @import("widgets/table.zig");
    _ = @import("widgets/switch.zig");
    _ = @import("widgets/spinner.zig");
    _ = @import("widgets/textarea.zig");
    _ = @import("widgets/separator.zig");
    _ = @import("widgets/toolbar.zig");
    _ = @import("widgets/statusbar.zig");
    _ = @import("widgets/groupbox.zig");
    _ = @import("widgets/panel.zig");
    _ = @import("widgets/dock_view.zig");
    _ = @import("widgets/graph_view.zig");
    _ = @import("widgets/timeline_view.zig");
    _ = @import("widgets/inspector_view.zig");
    _ = @import("widgets/drag_ghost.zig");
}
