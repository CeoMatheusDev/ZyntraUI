//! ZyntraUI — viewport 3D (viewport3d).
//!
//! Escopo M156+: sistema de viewport 3D OPCIONAL e modular:
//! - `math`: vetores e matrizes (convenções documentadas).
//! - `camera`: câmera independente do widget (dados + helpers).
//! - `mesh`: malhas simples (vértices + índices) e um cubo.
//! - `clipping`: recorte de triângulos contra o plano near.
//! - `depth`: buffer de profundidade.
//! - `raster`: rasterizador de triângulos em software.
//! - `viewport`: o WIDGET (desacoplado do rasterizador: recebe uma
//!   imagem pronta).
//!
//! A biblioteca continua sendo de UI leve: nada aqui é obrigatório
//! para usar a ZyntraUI, e o widget do viewport funciona com QUALQUER
//! produtor de imagem (o rasterizador interno, um renderizador externo
//! ou um backend GPU futuro).

pub const math = @import("math.zig");
pub const camera = @import("camera.zig");
pub const mesh = @import("mesh.zig");
pub const clipping = @import("clipping.zig");
pub const depth = @import("depth.zig");
pub const raster = @import("raster.zig");
pub const grid = @import("grid.zig");
pub const frustum = @import("frustum.zig");
pub const pick = @import("pick.zig");
pub const gizmo = @import("gizmo.zig");
pub const viewport = @import("viewport.zig");

comptime {
    _ = math;
    _ = camera;
    _ = mesh;
    _ = clipping;
    _ = depth;
    _ = raster;
    _ = grid;
    _ = frustum;
    _ = pick;
    _ = gizmo;
    _ = viewport;
}
