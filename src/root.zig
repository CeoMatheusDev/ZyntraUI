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
};

pub const event = struct {
    pub const event_mod = @import("event/event.zig");
};

pub const draw = struct {
    pub const commands = @import("draw/commands.zig");
};

// Re-exportações ergonômicas (M1+M2; compatível com M1).
pub const Vec2 = core.types.Vec2;
pub const Size = core.types.Size;
pub const Rect = core.types.Rect;
pub const Color = core.types.Color;
pub const Id = core.id.Id;
pub const Context = core.context.Context;
pub const ContextConfig = core.context.ContextConfig;
pub const ContextError = core.context.ContextError;

pub const Event = event.event_mod.Event;
pub const EventQueue = event.event_mod.EventQueue;
pub const MouseButton = event.event_mod.MouseButton;
pub const Key = event.event_mod.Key;
pub const Modifiers = event.event_mod.Modifiers;

pub const DrawCommand = draw.commands.DrawCommand;
pub const DrawList = draw.commands.DrawList;

pub const version_major = core.types.version_major;
pub const version_minor = core.types.version_minor;
pub const version_patch = core.types.version_patch;

test {
    // Garante que os blocos `test` dos submódulos executem via `zig build test`.
    _ = @import("core/types.zig");
    _ = @import("core/context.zig");
    _ = @import("core/id.zig");
    _ = @import("event/event.zig");
    _ = @import("draw/commands.zig");
}
