//! ZyntraUI — tipos fundamentais (core/types).
//!
//! Ownership: tipos por valor, sem alocação.
//! Lifetime: `'static` (sem referências internas).
//! ABI C: todos os tipos abaixo têm representação definida
//! (`extern struct`), prontos para reuso na futura camada C-ABI.
//! Erros: nenhuma função aqui falha.

/// Vetor 2D em pixels lógicos.
pub const Vec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn eql(a: Vec2, b: Vec2) bool {
        return a.x == b.x and a.y == b.y;
    }
};

/// Tamanho 2D em pixels lógicos.
pub const Size = extern struct {
    w: f32 = 0,
    h: f32 = 0,

    pub fn init(w: f32, h: f32) Size {
        return .{ .w = w, .h = h };
    }
};

/// Retângulo em pixels lógicos (origem no canto superior-esquerdo).
pub const Rect = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn init(x: f32, y: f32, w: f32, h: f32) Rect {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    /// Retorna true se o ponto está dentro (borda superior/esquerda
    /// inclusiva, inferior/direita exclusiva). Largura/altura <= 0
    /// nunca contém pontos.
    pub fn contains(self: Rect, p: Vec2) bool {
        if (self.w <= 0 or self.h <= 0) return false;
        return p.x >= self.x and p.x < self.x + self.w and
            p.y >= self.y and p.y < self.y + self.h;
    }

    pub fn size(self: Rect) Size {
        return .{ .w = self.w, .h = self.h };
    }
};

/// Cor RGBA não-premultiplicada, 8 bits por canal.
pub const Color = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    /// Empacota como 0xRRGGBBAA (big-endian lógico).
    pub fn packRgba(self: Color) u32 {
        return (@as(u32, self.r) << 24) |
            (@as(u32, self.g) << 16) |
            (@as(u32, self.b) << 8) |
            @as(u32, self.a);
    }

    pub fn unpackRgba(v: u32) Color {
        return .{
            .r = @intCast((v >> 24) & 0xff),
            .g = @intCast((v >> 16) & 0xff),
            .b = @intCast((v >> 8) & 0xff),
            .a = @intCast(v & 0xff),
        };
    }
};

/// Versão pública da biblioteca (MAJOR.MINOR.PATCH + pré-lançamento).
/// Espelho MANUAL de `build.zig.zon` (fonte única de verdade): o prep de
/// release atualiza os dois juntos; o teste `version_* espelham
/// build.zig.zon` abaixo quebra o CI em qualquer divergência.
/// Servida sem alteração pela API Zig (`root`) e pela ABI C
/// (`zyntra_version_*`); assinaturas e layouts inalterados.
pub const version_major: u32 = 1;
pub const version_minor: u32 = 18;
pub const version_patch: u32 = 0;
/// Sufixo de pré-lançamento (vazio quando estável).
pub const version_prerelease: [:0]const u8 = "";

/// Versão `MAJOR.MINOR.PATCH[-pre]` extraída de `build.zig.zon`.
const ZonVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    prerelease: []const u8,
};

/// Lê `.version = "x.y.z[-pre]"` de `build.zig.zon` (caminho relativo ao
/// fonte: funciona em `zig build test` e em `zig test src/root.zig`).
/// Falha ruidosamente se o campo sumir ou mudar de formato (fail-closed:
/// nunca aprova valores errados em silêncio).
fn parseZonVersion(zon: []const u8) error{MissingVersion}!ZonVersion {
    const std = @import("std");
    const key = std.mem.indexOf(u8, zon, ".version") orelse return error.MissingVersion;
    const open = std.mem.indexOfScalarPos(u8, zon, key, '"') orelse return error.MissingVersion;
    const close = std.mem.indexOfScalarPos(u8, zon, open + 1, '"') orelse return error.MissingVersion;
    var it = std.mem.splitScalar(u8, zon[open + 1 .. close], '.');
    const major_s = it.next() orelse return error.MissingVersion;
    const minor_s = it.next() orelse return error.MissingVersion;
    const patch_pre = it.next() orelse return error.MissingVersion;
    if (it.next() != null) return error.MissingVersion;
    var pit = std.mem.splitScalar(u8, patch_pre, '-');
    const patch_s = pit.next() orelse return error.MissingVersion;
    return .{
        .major = std.fmt.parseInt(u32, major_s, 10) catch return error.MissingVersion,
        .minor = std.fmt.parseInt(u32, minor_s, 10) catch return error.MissingVersion,
        .patch = std.fmt.parseInt(u32, patch_s, 10) catch return error.MissingVersion,
        .prerelease = pit.rest(),
    };
}

test "version_* espelham build.zig.zon (fonte de verdade)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    // O runner executa com CWD na raiz do repo (fluxo e CI); fora dela
    // a leitura falha ruidosamente (nunca aprova em silêncio).
    const io = stdt.testing.io;
    const data = stdt.Io.Dir.cwd().readFileAlloc(io, "build.zig.zon", gpa, .limited(4096)) catch
        return error.MissingVersion;
    defer gpa.free(data);
    const v = try parseZonVersion(data);
    try stdt.testing.expectEqual(v.major, version_major);
    try stdt.testing.expectEqual(v.minor, version_minor);
    try stdt.testing.expectEqual(v.patch, version_patch);
    try stdt.testing.expectEqualStrings(v.prerelease, version_prerelease);
}

test "Vec2 init/eql" {
    const std = @import("std");
    const a = Vec2.init(1.5, -2.0);
    try std.testing.expect(a.eql(Vec2.init(1.5, -2.0)));
    try std.testing.expect(!a.eql(Vec2.init(0, 0)));
}

test "Rect.contains bordas" {
    const std = @import("std");
    const r = Rect.init(10, 20, 100, 50);
    try std.testing.expect(r.contains(Vec2.init(10, 20)));
    try std.testing.expect(r.contains(Vec2.init(109.9, 69.9)));
    try std.testing.expect(!r.contains(Vec2.init(110, 20))); // borda direita exclusiva
    try std.testing.expect(!r.contains(Vec2.init(10, 70))); // borda inferior exclusiva
    try std.testing.expect(!r.contains(Vec2.init(0, 0)));
    try std.testing.expect(!Rect.init(0, 0, 0, 10).contains(Vec2.init(0, 0)));
    try std.testing.expect(!Rect.init(0, 0, 10, 0).contains(Vec2.init(0, 0)));
}

test "Color pack/unpack roundtrip" {
    const std = @import("std");
    const c = Color.init(0x12, 0x34, 0x56, 0x78);
    try std.testing.expectEqual(@as(u32, 0x12345678), c.packRgba());
    try std.testing.expectEqual(c, Color.unpackRgba(c.packRgba()));
    try std.testing.expectEqual(Color.rgb(255, 0, 0), Color.init(255, 0, 0, 255));
}
