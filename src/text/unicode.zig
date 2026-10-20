//! ZyntraUI — grapheme clusters (text/unicode).
//!
//! Escopo M166: a distinção entre BYTES, CODEPOINTS e GRAPHEME
//! CLUSTERS. O cursor de um campo de texto deve andar por CLUSTER (o
//! que o usuário vê como UM caractere), nunca por byte nem por
//! codepoint: "e" + acento é um caractere, um emoji com ZWJ (👨‍👩‍👧) é
//! um, uma bandeira (🇧🇷) é um.
//!
//! A implementação segue as regras do UAX #29 (GB1..GB999) para um
//! subconjunto PRÁTICO e documentado:
//! - CR × LF (GB3), controles (GB4/GB5);
//! - Hangul: L×(L|V|LV|LVT), (LV|V)×(V|T), (LVT|T)×T (GB6..GB8);
//! - × (Extend | ZWJ) (GB9), × SpacingMark (GB9a), Prepend × (GB9b);
//! - emoji com ZWJ: ExtPict Extend* ZWJ × ExtPict (GB11);
//! - bandeiras: pares de indicadores regionais (GB12/GB13);
//! - variação (FE00..FE0F) e modificadores de emoji como Extend.
//!
//! LIMITAÇÃO CONHECIDA: as tabelas de Extend/SpacingMark/Prepend
//! cobrem os scripts mais comuns (latino, cirílico, grego, árabe,
//! hebraico, devanagari, bengali, tamil, telugu, coreano, etc.), não
//! a tabela completa do UCD. Para texto SEM diacríticos, SEM emoji e
//! SEM ZWJ (o caso comum) o resultado é exato. Quem precisar do UCD
//! completo pode substituir as tabelas por um gerador externo — o
//! núcleo só depende desta API.

const std = @import("std");

/// Classe do caractere (as classes do UAX #29 que usamos).
pub const Class = enum(u8) {
    /// Qualquer outra coisa.
    other,
    /// Retorno de carro (U+000D).
    cr,
    /// Quebra de linha (U+000A).
    lf,
    /// Controle (C0/C1).
    control,
    /// Marca combinante (Mn/Me e afins).
    extend,
    /// ZWJ (U+200D).
    zwj,
    /// Indicador regional (bandeiras).
    regional_indicator,
    /// Marca espaçadora (Mc).
    spacing_mark,
    /// Prepend.
    prepend,
    /// Hangul L (jamo inicial).
    hangul_l,
    /// Hangul V (jamo medial).
    hangul_v,
    /// Hangul T (jamo final).
    hangul_t,
    /// Hangul LV (sílaba).
    hangul_lv,
    /// Hangul LVT (sílaba com final).
    hangul_lvt,
    /// Modificador de emoji (tom de pele).
    emoji_modifier,
    /// Seletor de variação.
    variation_selector,
    /// Extended_Pictographic (emoji).
    extpict,
};

/// Uma faixa de codepoints (inclusiva).
const Range = struct { lo: u21, hi: u21 };

/// Faixas de Extend (marcas combinantes) — subconjunto prático.
const extend_ranges = [_]Range{
    .{ .lo = 0x0300, .hi = 0x036F }, // diacríticos combinantes
    .{ .lo = 0x0483, .hi = 0x0489 },
    .{ .lo = 0x0591, .hi = 0x05BD },
    .{ .lo = 0x05BF, .hi = 0x05BF },
    .{ .lo = 0x05C1, .hi = 0x05C2 },
    .{ .lo = 0x05C4, .hi = 0x05C5 },
    .{ .lo = 0x05C7, .hi = 0x05C7 },
    .{ .lo = 0x0610, .hi = 0x061A },
    .{ .lo = 0x064B, .hi = 0x065F },
    .{ .lo = 0x0670, .hi = 0x0670 },
    .{ .lo = 0x06D6, .hi = 0x06DC },
    .{ .lo = 0x06DF, .hi = 0x06E4 },
    .{ .lo = 0x06E7, .hi = 0x06E8 },
    .{ .lo = 0x06EA, .hi = 0x06ED },
    .{ .lo = 0x0711, .hi = 0x0711 },
    .{ .lo = 0x0730, .hi = 0x074A },
    .{ .lo = 0x07A6, .hi = 0x07B0 },
    .{ .lo = 0x07EB, .hi = 0x07F3 },
    .{ .lo = 0x0816, .hi = 0x0819 },
    .{ .lo = 0x081B, .hi = 0x0823 },
    .{ .lo = 0x0825, .hi = 0x0827 },
    .{ .lo = 0x0829, .hi = 0x082D },
    .{ .lo = 0x0859, .hi = 0x085B },
    .{ .lo = 0x08D3, .hi = 0x08E1 },
    .{ .lo = 0x08E3, .hi = 0x08FF },
    .{ .lo = 0x093A, .hi = 0x093C },
    .{ .lo = 0x093E, .hi = 0x094F },
    .{ .lo = 0x0951, .hi = 0x0957 },
    .{ .lo = 0x0962, .hi = 0x0963 },
    .{ .lo = 0x0981, .hi = 0x0983 },
    .{ .lo = 0x09BC, .hi = 0x09BC },
    .{ .lo = 0x09BE, .hi = 0x09C4 },
    .{ .lo = 0x09C7, .hi = 0x09C8 },
    .{ .lo = 0x09CB, .hi = 0x09CD },
    .{ .lo = 0x09D7, .hi = 0x09D7 },
    .{ .lo = 0x09E2, .hi = 0x09E3 },
    .{ .lo = 0x0A01, .hi = 0x0A03 },
    .{ .lo = 0x0A3C, .hi = 0x0A3C },
    .{ .lo = 0x0A3E, .hi = 0x0A42 },
    .{ .lo = 0x0A47, .hi = 0x0A48 },
    .{ .lo = 0x0A4B, .hi = 0x0A4D },
    .{ .lo = 0x0A51, .hi = 0x0A51 },
    .{ .lo = 0x0A70, .hi = 0x0A71 },
    .{ .lo = 0x0A75, .hi = 0x0A75 },
    .{ .lo = 0x0E31, .hi = 0x0E31 },
    .{ .lo = 0x0E34, .hi = 0x0E3A },
    .{ .lo = 0x0E47, .hi = 0x0E4E },
    .{ .lo = 0x0EB1, .hi = 0x0EB1 },
    .{ .lo = 0x0EB4, .hi = 0x0EBC },
    .{ .lo = 0x0EC8, .hi = 0x0ECD },
    .{ .lo = 0x0F18, .hi = 0x0F19 },
    .{ .lo = 0x0F35, .hi = 0x0F35 },
    .{ .lo = 0x0F37, .hi = 0x0F37 },
    .{ .lo = 0x0F39, .hi = 0x0F39 },
    .{ .lo = 0x0F3E, .hi = 0x0F3F },
    .{ .lo = 0x0F71, .hi = 0x0F84 },
    .{ .lo = 0x0F86, .hi = 0x0F87 },
    .{ .lo = 0x0F8D, .hi = 0x0F97 },
    .{ .lo = 0x0F99, .hi = 0x0FBC },
    .{ .lo = 0x0FC6, .hi = 0x0FC6 },
    .{ .lo = 0x102B, .hi = 0x103E },
    .{ .lo = 0x1056, .hi = 0x1059 },
    .{ .lo = 0x105E, .hi = 0x1060 },
    .{ .lo = 0x1062, .hi = 0x1064 },
    .{ .lo = 0x1067, .hi = 0x106D },
    .{ .lo = 0x1071, .hi = 0x1074 },
    .{ .lo = 0x1082, .hi = 0x108D },
    .{ .lo = 0x108F, .hi = 0x108F },
    .{ .lo = 0x109A, .hi = 0x109D },
    .{ .lo = 0x135D, .hi = 0x135F },
    .{ .lo = 0x1712, .hi = 0x1714 },
    .{ .lo = 0x1732, .hi = 0x1734 },
    .{ .lo = 0x1752, .hi = 0x1753 },
    .{ .lo = 0x1772, .hi = 0x1773 },
    .{ .lo = 0x17B4, .hi = 0x17D3 },
    .{ .lo = 0x17DD, .hi = 0x17DD },
    .{ .lo = 0x180B, .hi = 0x180D },
    .{ .lo = 0x1885, .hi = 0x1886 },
    .{ .lo = 0x18A9, .hi = 0x18A9 },
    .{ .lo = 0x1920, .hi = 0x193B },
    .{ .lo = 0x1A17, .hi = 0x1A1B },
    .{ .lo = 0x1A55, .hi = 0x1A5E },
    .{ .lo = 0x1A60, .hi = 0x1A7C },
    .{ .lo = 0x1AB0, .hi = 0x1ACE },
    .{ .lo = 0x1B00, .hi = 0x1B04 },
    .{ .lo = 0x1B34, .hi = 0x1B44 },
    .{ .lo = 0x1B6B, .hi = 0x1B73 },
    .{ .lo = 0x1B80, .hi = 0x1B82 },
    .{ .lo = 0x1BA1, .hi = 0x1BAD },
    .{ .lo = 0x1BE6, .hi = 0x1BF3 },
    .{ .lo = 0x1C24, .hi = 0x1C37 },
    .{ .lo = 0x1CD0, .hi = 0x1CD2 },
    .{ .lo = 0x1CD4, .hi = 0x1CE8 },
    .{ .lo = 0x1CED, .hi = 0x1CED },
    .{ .lo = 0x1CF2, .hi = 0x1CF4 },
    .{ .lo = 0x1CF8, .hi = 0x1CF9 },
    .{ .lo = 0x1DC0, .hi = 0x1DFF },
    .{ .lo = 0x200C, .hi = 0x200C }, // ZWNJ
    .{ .lo = 0x20D0, .hi = 0x20F0 },
    .{ .lo = 0x2CEF, .hi = 0x2CF1 },
    .{ .lo = 0x2D7F, .hi = 0x2D7F },
    .{ .lo = 0x2DE0, .hi = 0x2DFF },
    .{ .lo = 0x302A, .hi = 0x302F },
    .{ .lo = 0x3099, .hi = 0x309A },
    .{ .lo = 0xA66F, .hi = 0xA672 },
    .{ .lo = 0xA674, .hi = 0xA67D },
    .{ .lo = 0xA69E, .hi = 0xA69F },
    .{ .lo = 0xA6F0, .hi = 0xA6F1 },
    .{ .lo = 0xA802, .hi = 0xA802 },
    .{ .lo = 0xA806, .hi = 0xA806 },
    .{ .lo = 0xA80B, .hi = 0xA80B },
    .{ .lo = 0xA823, .hi = 0xA827 },
    .{ .lo = 0xA880, .hi = 0xA881 },
    .{ .lo = 0xA8B4, .hi = 0xA8C4 },
    .{ .lo = 0xA8E0, .hi = 0xA8F1 },
    .{ .lo = 0xA926, .hi = 0xA92D },
    .{ .lo = 0xA947, .hi = 0xA953 },
    .{ .lo = 0xA980, .hi = 0xA983 },
    .{ .lo = 0xA9B3, .hi = 0xA9C0 },
    .{ .lo = 0xA9E5, .hi = 0xA9E5 },
    .{ .lo = 0xAA29, .hi = 0xAA36 },
    .{ .lo = 0xAA43, .hi = 0xAA43 },
    .{ .lo = 0xAA4C, .hi = 0xAA4D },
    .{ .lo = 0xAA7B, .hi = 0xAA7D },
    .{ .lo = 0xAAB0, .hi = 0xAAB8 },
    .{ .lo = 0xAABE, .hi = 0xAABF },
    .{ .lo = 0xAAC1, .hi = 0xAAC1 },
    .{ .lo = 0xAAEB, .hi = 0xAAEF },
    .{ .lo = 0xAAF5, .hi = 0xAAF5 },
    .{ .lo = 0xABE3, .hi = 0xABEA },
    .{ .lo = 0xABEC, .hi = 0xABED },
    .{ .lo = 0xFB1E, .hi = 0xFB1E },
    .{ .lo = 0xFE00, .hi = 0xFE0F }, // seletores de variação
    .{ .lo = 0xFE20, .hi = 0xFE2F },
    .{ .lo = 0x101FD, .hi = 0x101FD },
    .{ .lo = 0x102E0, .hi = 0x102E0 },
    .{ .lo = 0x10376, .hi = 0x1037A },
    .{ .lo = 0x10A01, .hi = 0x10A0F },
    .{ .lo = 0x10A38, .hi = 0x10A3F },
    .{ .lo = 0x10AE5, .hi = 0x10AE6 },
    .{ .lo = 0x11000, .hi = 0x11002 },
    .{ .lo = 0x11038, .hi = 0x11046 },
    .{ .lo = 0x1107F, .hi = 0x11082 },
    .{ .lo = 0x110B0, .hi = 0x110BA },
    .{ .lo = 0x11100, .hi = 0x11102 },
    .{ .lo = 0x11127, .hi = 0x11134 },
    .{ .lo = 0x11173, .hi = 0x11173 },
    .{ .lo = 0x11180, .hi = 0x11182 },
    .{ .lo = 0x111B3, .hi = 0x111C0 },
    .{ .lo = 0x1122C, .hi = 0x11237 },
    .{ .lo = 0x112DF, .hi = 0x112EA },
    .{ .lo = 0x11300, .hi = 0x11304 },
    .{ .lo = 0x1133E, .hi = 0x11344 },
    .{ .lo = 0x11347, .hi = 0x11348 },
    .{ .lo = 0x1134B, .hi = 0x1134D },
    .{ .lo = 0x11357, .hi = 0x11357 },
    .{ .lo = 0x11362, .hi = 0x11363 },
    .{ .lo = 0x11435, .hi = 0x11446 },
    .{ .lo = 0x1145E, .hi = 0x1145E },
    .{ .lo = 0x114B0, .hi = 0x114C3 },
    .{ .lo = 0x115AF, .hi = 0x115C0 },
    .{ .lo = 0x11630, .hi = 0x11640 },
    .{ .lo = 0x116AB, .hi = 0x116B7 },
    .{ .lo = 0x1171D, .hi = 0x1172B },
    .{ .lo = 0x1182C, .hi = 0x1183A },
    .{ .lo = 0x11930, .hi = 0x1193E },
    .{ .lo = 0x119D4, .hi = 0x119D7 },
    .{ .lo = 0x119DA, .hi = 0x119DF },
    .{ .lo = 0x119E4, .hi = 0x119E4 },
    .{ .lo = 0x1A7F0, .hi = 0x1A7F8 },
    .{ .lo = 0x1AB0, .hi = 0x1ACE },
    .{ .lo = 0x16AF0, .hi = 0x16AF4 },
    .{ .lo = 0x16B30, .hi = 0x16B36 },
    .{ .lo = 0x16F4F, .hi = 0x16F4F },
    .{ .lo = 0x16F8F, .hi = 0x16F9F },
    .{ .lo = 0x16FF0, .hi = 0x16FF0 },
    .{ .lo = 0x1BC9D, .hi = 0x1BC9E },
    .{ .lo = 0x1CF00, .hi = 0x1CF2D },
    .{ .lo = 0x1CF30, .hi = 0x1CF46 },
    .{ .lo = 0x1D167, .hi = 0x1D1A9 },
    .{ .lo = 0x1D1AE, .hi = 0x1D1EA },
    .{ .lo = 0x1D242, .hi = 0x1D244 },
    .{ .lo = 0x1DA00, .hi = 0x1DA36 },
    .{ .lo = 0x1DA3B, .hi = 0x1DA6C },
    .{ .lo = 0x1DA75, .hi = 0x1DA75 },
    .{ .lo = 0x1DA84, .hi = 0x1DA84 },
    .{ .lo = 0x1DA9B, .hi = 0x1DA9F },
    .{ .lo = 0x1DAA1, .hi = 0x1DAAF },
    .{ .lo = 0x1E000, .hi = 0x1E02A },
    .{ .lo = 0x1E130, .hi = 0x1E136 },
    .{ .lo = 0x1E2AE, .hi = 0x1E2AE },
    .{ .lo = 0x1E2EC, .hi = 0x1E2EF },
    .{ .lo = 0x1E8D0, .hi = 0x1E8D6 },
    .{ .lo = 0x1E944, .hi = 0x1E94A },
    .{ .lo = 0xE0020, .hi = 0xE007F },
};

/// Faixas de SpacingMark (Mc) — subconjunto prático.
const spacing_mark_ranges = [_]Range{
    .{ .lo = 0x0903, .hi = 0x0903 },
    .{ .lo = 0x093B, .hi = 0x093B },
    .{ .lo = 0x093E, .hi = 0x0940 },
    .{ .lo = 0x0949, .hi = 0x094C },
    .{ .lo = 0x094E, .hi = 0x094F },
    .{ .lo = 0x0982, .hi = 0x0983 },
    .{ .lo = 0x09BF, .hi = 0x09C0 },
    .{ .lo = 0x09C7, .hi = 0x09C8 },
    .{ .lo = 0x09CB, .hi = 0x09CB },
    .{ .lo = 0x09CD, .hi = 0x09CD },
    .{ .lo = 0x0A03, .hi = 0x0A03 },
    .{ .lo = 0x0A3E, .hi = 0x0A40 },
    .{ .lo = 0x0A83, .hi = 0x0A83 },
    .{ .lo = 0x0ABE, .hi = 0x0AC0 },
    .{ .lo = 0x0AC9, .hi = 0x0AC9 },
    .{ .lo = 0x0ACB, .hi = 0x0ACC },
    .{ .lo = 0x0B02, .hi = 0x0B03 },
    .{ .lo = 0x0B40, .hi = 0x0B40 },
    .{ .lo = 0x0B47, .hi = 0x0B48 },
    .{ .lo = 0x0B4B, .hi = 0x0B4C },
    .{ .lo = 0x0B57, .hi = 0x0B57 },
    .{ .lo = 0x0BBF, .hi = 0x0BBF },
    .{ .lo = 0x0BC1, .hi = 0x0BC2 },
    .{ .lo = 0x0BC6, .hi = 0x0BC8 },
    .{ .lo = 0x0BCA, .hi = 0x0BCC },
    .{ .lo = 0x0C01, .hi = 0x0C03 },
    .{ .lo = 0x0C41, .hi = 0x0C44 },
    .{ .lo = 0x0C82, .hi = 0x0C83 },
    .{ .lo = 0x0CBE, .hi = 0x0CBE },
    .{ .lo = 0x0CC0, .hi = 0x0CC1 },
    .{ .lo = 0x0CC3, .hi = 0x0CC4 },
    .{ .lo = 0x0CC7, .hi = 0x0CC8 },
    .{ .lo = 0x0CCA, .hi = 0x0CCB },
    .{ .lo = 0x0D02, .hi = 0x0D03 },
    .{ .lo = 0x0D3F, .hi = 0x0D40 },
    .{ .lo = 0x0D46, .hi = 0x0D48 },
    .{ .lo = 0x0D4A, .hi = 0x0D4C },
    .{ .lo = 0x0D82, .hi = 0x0D83 },
    .{ .lo = 0x0DD0, .hi = 0x0DD1 },
    .{ .lo = 0x0DD8, .hi = 0x0DDE },
    .{ .lo = 0x0DF2, .hi = 0x0DF3 },
    .{ .lo = 0x0E33, .hi = 0x0E33 },
    .{ .lo = 0x0EB3, .hi = 0x0EB3 },
    .{ .lo = 0x0F3E, .hi = 0x0F3F },
    .{ .lo = 0x0F7F, .hi = 0x0F7F },
    .{ .lo = 0x1031, .hi = 0x1031 },
    .{ .lo = 0x103B, .hi = 0x103C },
    .{ .lo = 0x1056, .hi = 0x1057 },
    .{ .lo = 0x1084, .hi = 0x1084 },
    .{ .lo = 0x1715, .hi = 0x1715 },
    .{ .lo = 0x1734, .hi = 0x1734 },
    .{ .lo = 0x17B6, .hi = 0x17B6 },
    .{ .lo = 0x17BE, .hi = 0x17C5 },
    .{ .lo = 0x17C7, .hi = 0x17C8 },
    .{ .lo = 0x1923, .hi = 0x1926 },
    .{ .lo = 0x1929, .hi = 0x192B },
    .{ .lo = 0x1930, .hi = 0x1931 },
    .{ .lo = 0x1933, .hi = 0x1938 },
    .{ .lo = 0x1A19, .hi = 0x1A1A },
    .{ .lo = 0x1A55, .hi = 0x1A55 },
    .{ .lo = 0x1A57, .hi = 0x1A57 },
    .{ .lo = 0x1A6D, .hi = 0x1A72 },
    .{ .lo = 0x1B04, .hi = 0x1B04 },
    .{ .lo = 0x1B35, .hi = 0x1B35 },
    .{ .lo = 0x1B3B, .hi = 0x1B3B },
    .{ .lo = 0x1B3D, .hi = 0x1B41 },
    .{ .lo = 0x1B43, .hi = 0x1B44 },
    .{ .lo = 0x1B82, .hi = 0x1B82 },
    .{ .lo = 0x1BA1, .hi = 0x1BA1 },
    .{ .lo = 0x1BA6, .hi = 0x1BA7 },
    .{ .lo = 0x1BAA, .hi = 0x1BAA },
    .{ .lo = 0x1BE7, .hi = 0x1BE7 },
    .{ .lo = 0x1BEA, .hi = 0x1BEC },
    .{ .lo = 0x1BEE, .hi = 0x1BEE },
    .{ .lo = 0x1BF2, .hi = 0x1BF3 },
    .{ .lo = 0x1C24, .hi = 0x1C2B },
    .{ .lo = 0x1C34, .hi = 0x1C35 },
    .{ .lo = 0x1CE1, .hi = 0x1CE1 },
    .{ .lo = 0x1CF7, .hi = 0x1CF7 },
    .{ .lo = 0xA823, .hi = 0xA824 },
    .{ .lo = 0xA827, .hi = 0xA827 },
    .{ .lo = 0xA880, .hi = 0xA881 },
    .{ .lo = 0xA8B4, .hi = 0xA8C3 },
    .{ .lo = 0xA952, .hi = 0xA953 },
    .{ .lo = 0xA983, .hi = 0xA983 },
    .{ .lo = 0xA9B4, .hi = 0xA9B5 },
    .{ .lo = 0xA9BA, .hi = 0xA9BB },
    .{ .lo = 0xA9BE, .hi = 0xA9C0 },
    .{ .lo = 0xAA2F, .hi = 0xAA30 },
    .{ .lo = 0xAA33, .hi = 0xAA34 },
    .{ .lo = 0xAA4D, .hi = 0xAA4D },
    .{ .lo = 0xAAEB, .hi = 0xAAEB },
    .{ .lo = 0xAAEE, .hi = 0xAAEF },
    .{ .lo = 0xAAF5, .hi = 0xAAF5 },
    .{ .lo = 0xABE3, .hi = 0xABEA },
    .{ .lo = 0xABEC, .hi = 0xABED },
    .{ .lo = 0xFB1E, .hi = 0xFB1E },
    .{ .lo = 0xFF9E, .hi = 0xFF9F },
};

/// Faixas de Prepend.
const prepend_ranges = [_]Range{
    .{ .lo = 0x0600, .hi = 0x0605 },
    .{ .lo = 0x06DD, .hi = 0x06DD },
    .{ .lo = 0x070F, .hi = 0x070F },
    .{ .lo = 0x0890, .hi = 0x0891 },
    .{ .lo = 0x08E2, .hi = 0x08E2 },
    .{ .lo = 0x0D4E, .hi = 0x0D4E },
    .{ .lo = 0x110BD, .hi = 0x110BD },
    .{ .lo = 0x110CD, .hi = 0x110CD },
    .{ .lo = 0x111C2, .hi = 0x111C3 },
    .{ .lo = 0x1193F, .hi = 0x1193F },
    .{ .lo = 0x11941, .hi = 0x11941 },
    .{ .lo = 0x11A3A, .hi = 0x11A3A },
    .{ .lo = 0x11A84, .hi = 0x11A89 },
    .{ .lo = 0x11D46, .hi = 0x11D46 },
};

/// Faixas Extended_Pictographic (emoji) — subconjunto prático.
const extpict_ranges = [_]Range{
    .{ .lo = 0x00A9, .hi = 0x00A9 },
    .{ .lo = 0x00AE, .hi = 0x00AE },
    .{ .lo = 0x203C, .hi = 0x203C },
    .{ .lo = 0x2049, .hi = 0x2049 },
    .{ .lo = 0x2122, .hi = 0x2122 },
    .{ .lo = 0x2139, .hi = 0x2139 },
    .{ .lo = 0x2194, .hi = 0x2199 },
    .{ .lo = 0x21A9, .hi = 0x21AA },
    .{ .lo = 0x231A, .hi = 0x231B },
    .{ .lo = 0x2328, .hi = 0x2328 },
    .{ .lo = 0x23CF, .hi = 0x23CF },
    .{ .lo = 0x23E9, .hi = 0x23F3 },
    .{ .lo = 0x23F8, .hi = 0x23FA },
    .{ .lo = 0x24C2, .hi = 0x24C2 },
    .{ .lo = 0x25AA, .hi = 0x25AB },
    .{ .lo = 0x25B6, .hi = 0x25B6 },
    .{ .lo = 0x25C0, .hi = 0x25C0 },
    .{ .lo = 0x25FB, .hi = 0x25FE },
    .{ .lo = 0x2600, .hi = 0x2605 },
    .{ .lo = 0x2607, .hi = 0x2612 },
    .{ .lo = 0x2614, .hi = 0x2685 },
    .{ .lo = 0x2690, .hi = 0x2705 },
    .{ .lo = 0x2708, .hi = 0x2712 },
    .{ .lo = 0x2714, .hi = 0x2714 },
    .{ .lo = 0x2716, .hi = 0x2716 },
    .{ .lo = 0x271D, .hi = 0x271D },
    .{ .lo = 0x2721, .hi = 0x2721 },
    .{ .lo = 0x2728, .hi = 0x2728 },
    .{ .lo = 0x2733, .hi = 0x2734 },
    .{ .lo = 0x2744, .hi = 0x2744 },
    .{ .lo = 0x2747, .hi = 0x2747 },
    .{ .lo = 0x274C, .hi = 0x274C },
    .{ .lo = 0x274E, .hi = 0x274E },
    .{ .lo = 0x2753, .hi = 0x2755 },
    .{ .lo = 0x2757, .hi = 0x2757 },
    .{ .lo = 0x2763, .hi = 0x2767 },
    .{ .lo = 0x2795, .hi = 0x2797 },
    .{ .lo = 0x27A1, .hi = 0x27A1 },
    .{ .lo = 0x27B0, .hi = 0x27B0 },
    .{ .lo = 0x27BF, .hi = 0x27BF },
    .{ .lo = 0x2934, .hi = 0x2935 },
    .{ .lo = 0x2B05, .hi = 0x2B07 },
    .{ .lo = 0x2B1B, .hi = 0x2B1C },
    .{ .lo = 0x2B50, .hi = 0x2B50 },
    .{ .lo = 0x2B55, .hi = 0x2B55 },
    .{ .lo = 0x3030, .hi = 0x3030 },
    .{ .lo = 0x303D, .hi = 0x303D },
    .{ .lo = 0x3297, .hi = 0x3297 },
    .{ .lo = 0x3299, .hi = 0x3299 },
    .{ .lo = 0x1F000, .hi = 0x1F0FF },
    .{ .lo = 0x1F10D, .hi = 0x1F10F },
    .{ .lo = 0x1F12F, .hi = 0x1F12F },
    .{ .lo = 0x1F16C, .hi = 0x1F171 },
    .{ .lo = 0x1F17E, .hi = 0x1F17F },
    .{ .lo = 0x1F18E, .hi = 0x1F18E },
    .{ .lo = 0x1F191, .hi = 0x1F19A },
    .{ .lo = 0x1F1AD, .hi = 0x1F1E5 },
    .{ .lo = 0x1F201, .hi = 0x1F20F },
    .{ .lo = 0x1F21A, .hi = 0x1F21A },
    .{ .lo = 0x1F22F, .hi = 0x1F22F },
    .{ .lo = 0x1F232, .hi = 0x1F23A },
    .{ .lo = 0x1F23C, .hi = 0x1F23F },
    .{ .lo = 0x1F249, .hi = 0x1F3FA },
    .{ .lo = 0x1F400, .hi = 0x1F53D },
    .{ .lo = 0x1F546, .hi = 0x1F64F },
    .{ .lo = 0x1F680, .hi = 0x1F6FF },
    .{ .lo = 0x1F774, .hi = 0x1F77F },
    .{ .lo = 0x1F7D5, .hi = 0x1F7FF },
    .{ .lo = 0x1F80C, .hi = 0x1F80F },
    .{ .lo = 0x1F848, .hi = 0x1F84F },
    .{ .lo = 0x1F85A, .hi = 0x1F85F },
    .{ .lo = 0x1F888, .hi = 0x1F8FF },
    .{ .lo = 0x1F90C, .hi = 0x1F93A },
    .{ .lo = 0x1F93C, .hi = 0x1F945 },
    .{ .lo = 0x1F947, .hi = 0x1FAFF },
    .{ .lo = 0x1FC00, .hi = 0x1FFFD },
};

/// A classe de um codepoint.
pub fn classOf(cp: u21) Class {
    if (cp == 0x000D) return .cr;
    if (cp == 0x000A) return .lf;
    if (cp < 0x20 or (cp >= 0x7F and cp <= 0x9F)) return .control;
    if (cp == 0x200D) return .zwj;
    if (cp >= 0x1F1E6 and cp <= 0x1F1FF) return .regional_indicator;
    if (cp >= 0x1F3FB and cp <= 0x1F3FF) return .emoji_modifier;
    if (cp >= 0xFE00 and cp <= 0xFE0F) return .variation_selector;
    if (cp >= 0xE0100 and cp <= 0xE01EF) return .variation_selector;
    // Hangul
    if (cp >= 0x1100 and cp <= 0x115F) return .hangul_l;
    if (cp >= 0x1160 and cp <= 0x11A7) return .hangul_v;
    if (cp >= 0x11A8 and cp <= 0x11FF) return .hangul_t;
    if (cp >= 0xA960 and cp <= 0xA97C) return .hangul_l;
    if (cp >= 0xD7B0 and cp <= 0xD7C6) return .hangul_v;
    if (cp >= 0xD7CB and cp <= 0xD7FB) return .hangul_t;
    if (cp >= 0xAC00 and cp <= 0xD7A3) {
        return if ((cp - 0xAC00) % 28 == 0) .hangul_lv else .hangul_lvt;
    }
    if (inRanges(&prepend_ranges, cp)) return .prepend;
    if (inRanges(&extend_ranges, cp)) return .extend;
    if (inRanges(&spacing_mark_ranges, cp)) return .spacing_mark;
    if (inRanges(&extpict_ranges, cp)) return .extpict;
    return .other;
}

/// O codepoint está em alguma das faixas? (busca binária).
fn inRanges(ranges: []const Range, cp: u21) bool {
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const r = ranges[mid];
        if (cp < r.lo) {
            hi = mid;
        } else if (cp > r.hi) {
            lo = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

/// Decodifica o codepoint em `offset` (devolve o byte lido e o
/// codepoint). Texto malformado ⇒ `error.InvalidUtf8`.
fn decodeAt(text: []const u8, offset: usize) !struct { cp: u21, len: usize } {
    if (offset >= text.len) return error.InvalidUtf8;
    const len = std.unicode.utf8ByteSequenceLength(text[offset]) catch return error.InvalidUtf8;
    if (offset + len > text.len) return error.InvalidUtf8;
    const cp = std.unicode.utf8Decode(text[offset..][0..len]) catch return error.InvalidUtf8;
    return .{ .cp = cp, .len = len };
}

/// A posição do próximo codepoint (ou o fim do texto).
fn nextCodepoint(text: []const u8, offset: usize) usize {
    if (offset >= text.len) return text.len;
    const len = std.unicode.utf8ByteSequenceLength(text[offset]) catch return text.len;
    return @min(offset + len, text.len);
}

/// O início do codepoint anterior (ou 0).
fn prevCodepoint(text: []const u8, offset: usize) usize {
    if (offset == 0) return 0;
    var o = @min(offset, text.len);
    while (o > 0) {
        o -= 1;
        const b = text[o];
        if ((b & 0xC0) != 0x80) return o;
    }
    return 0;
}

/// O cluster começa em `offset`? (a próxima posição é uma quebra?)
///
/// `ri_run` = quantos indicadores regionais vêm ANTES de `offset`
/// (contagem paridade para a regra das bandeiras).
fn breaksAt(text: []const u8, offset: usize, ri_run: usize) bool {
    if (offset == 0 or offset >= text.len) return true;
    const prev = prevCodepoint(text, offset);
    const cur = offset;
    const a = (decodeAt(text, prev) catch return true).cp;
    const b = (decodeAt(text, cur) catch return true).cp;
    const ca = classOf(a);
    const cb = classOf(b);

    // GB3: CR × LF
    if (ca == .cr and cb == .lf) return false;
    // GB4: (Control | CR | LF) ÷
    if (ca == .control or ca == .cr or ca == .lf) return true;
    // GB5: ÷ (Control | CR | LF)
    if (cb == .control or cb == .cr or cb == .lf) return true;
    // GB6: L × (L | V | LV | LVT)
    if (ca == .hangul_l and
        (cb == .hangul_l or cb == .hangul_v or cb == .hangul_lv or cb == .hangul_lvt))
    {
        return false;
    }
    // GB7: (LV | V) × (V | T)
    if ((ca == .hangul_lv or ca == .hangul_v) and (cb == .hangul_v or cb == .hangul_t)) {
        return false;
    }
    // GB8: (LVT | T) × T
    if ((ca == .hangul_lvt or ca == .hangul_t) and cb == .hangul_t) return false;
    // GB9: × (Extend | ZWJ)
    if (cb == .extend or cb == .zwj) return false;
    // GB9a: × SpacingMark
    if (cb == .spacing_mark) return false;
    // GB9b: Prepend ×
    if (ca == .prepend) return false;
    // GB11: ExtPict Extend* ZWJ × ExtPict
    if (ca == .zwj and cb == .extpict) {
        // O codepoint antes do ZWJ (pulando os Extend) é ExtPict?
        var p = prevCodepoint(text, prev);
        while (p < text.len) {
            const info = decodeAt(text, p) catch break;
            if (classOf(info.cp) == .extend) {
                p = prevCodepoint(text, p);
                continue;
            }
            if (classOf(info.cp) == .extpict) return false;
            break;
        }
    }
    // GB12/GB13: RI × RI (pares)
    if (ca == .regional_indicator and cb == .regional_indicator and (ri_run % 2 == 1)) {
        return false;
    }
    // GB999: quebra
    return true;
}

/// O tamanho (em bytes) do cluster que começa em `offset`.
///
/// `offset` tem de ser o início de um codepoint; se não for, o cluster
/// é medido a partir do início do codepoint que contém `offset`.
pub fn graphemeLen(text: []const u8, offset: usize) usize {
    if (offset >= text.len) return 0;
    const start = codepointStart(text, offset);
    var pos = start;
    var ri_run: usize = 0;
    while (pos < text.len) {
        // Conta os RI anteriores (paridade das bandeiras).
        const info = decodeAt(text, pos) catch return @max(1, pos - start);
        if (classOf(info.cp) == .regional_indicator) ri_run += 1 else ri_run = 0;
        const next = nextCodepoint(text, pos);
        // O fim do texto fecha o cluster.
        if (next >= text.len) return @max(1, text.len - start);
        // A fronteira em `next` fecha o cluster.
        if (breaksAt(text, next, ri_run)) return @max(1, next - start);
        pos = next;
    }
    return @max(1, pos - start);
}

/// O início do codepoint que contém `offset`.
fn codepointStart(text: []const u8, offset: usize) usize {
    if (offset >= text.len) return text.len;
    var o = offset;
    while (o > 0 and (text[o] & 0xC0) == 0x80) o -= 1;
    return o;
}

/// O início do cluster ANTERIOR (a posição anterior a `offset`).
///
/// `offset` pode estar no meio de um cluster: o resultado é o início
/// do cluster que contém `offset` (nunca o meio dele).
pub fn prevGrapheme(text: []const u8, offset: usize) usize {
    if (offset == 0 or text.len == 0) return 0;
    const o = @min(offset, text.len);
    // A maior fronteira estritamente menor que `o`.
    var pos = codepointStart(text, o);
    while (pos > 0) {
        if (pos < o and breaksAt(text, pos, riRunBefore(text, pos))) return pos;
        const prev = prevCodepoint(text, pos);
        if (prev == 0) return 0;
        pos = prev;
    }
    return 0;
}

/// O início do PRÓXIMO cluster (a posição depois de `offset`).
///
/// `offset` pode estar no meio de um cluster: o resultado é o início
/// do cluster que vem DEPOIS do que contém `offset`.
pub fn nextGrapheme(text: []const u8, offset: usize) usize {
    if (offset >= text.len) return text.len;
    const o = codepointStart(text, @min(offset, text.len));
    // A menor fronteira maior que `o`.
    var pos = o;
    while (pos < text.len) {
        const next = nextCodepoint(text, pos);
        if (next >= text.len) return text.len;
        if (breaksAt(text, next, riRunBefore(text, next))) return next;
        pos = next;
    }
    return text.len;
}

/// Quantos indicadores regionais vêm antes de `offset` (paridade).
fn riRunBefore(text: []const u8, offset: usize) usize {
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < offset and pos < text.len) {
        const info = decodeAt(text, pos) catch break;
        if (classOf(info.cp) != .regional_indicator) {
            count = 0;
        } else {
            count += 1;
        }
        pos = nextCodepoint(text, pos);
    }
    return count;
}

/// A posição do início do cluster que contém `offset` (o clique no
/// meio de um emoji vai para o início dele).
pub fn snapToGrapheme(text: []const u8, offset: usize) usize {
    if (offset == 0 or text.len == 0) return 0;
    const o = codepointStart(text, @min(offset, text.len));
    // A maior fronteira menor ou igual a `o`.
    var pos = o;
    while (pos > 0) {
        if (breaksAt(text, pos, riRunBefore(text, pos))) return pos;
        const prev = prevCodepoint(text, pos);
        if (prev == 0) return 0;
        pos = prev;
    }
    return 0;
}

/// Quantos clusters tem o texto.
pub fn graphemeCount(text: []const u8) usize {
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < text.len) {
        const len = graphemeLen(text, pos);
        if (len == 0) break;
        pos += len;
        count += 1;
    }
    return count;
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test "unicode: ASCII é um cluster por byte" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(usize, 5), graphemeCount("hello"));
    try stdt.testing.expectEqual(@as(usize, 1), graphemeLen("hello", 0));
    try stdt.testing.expectEqual(@as(usize, 1), nextGrapheme("hello", 0));
    try stdt.testing.expectEqual(@as(usize, 3), prevGrapheme("hello", 4));
}

test "unicode: a letra com acento é UM cluster" {
    const stdt = @import("std");
    // "e" + U+0301 (2 bytes) = 3 bytes, 1 cluster.
    const text = "e\xCC\x81x";
    try stdt.testing.expectEqual(@as(usize, 2), graphemeCount(text));
    try stdt.testing.expectEqual(@as(usize, 3), graphemeLen(text, 0));
    try stdt.testing.expectEqual(@as(usize, 3), nextGrapheme(text, 0));
    try stdt.testing.expectEqual(@as(usize, 0), prevGrapheme(text, 3));
    // O snap leva o meio do cluster ao início.
    try stdt.testing.expectEqual(@as(usize, 0), snapToGrapheme(text, 1));
    try stdt.testing.expectEqual(@as(usize, 3), snapToGrapheme(text, 3));
}

test "unicode: a bandeira é UM cluster" {
    const stdt = @import("std");
    // 🇧🇷 = 2 indicadores regionais (4 bytes cada).
    const text = "\xF0\x9F\x87\xA7\xF0\x9F\x87\xB7x";
    try stdt.testing.expectEqual(@as(usize, 2), graphemeCount(text));
    try stdt.testing.expectEqual(@as(usize, 8), graphemeLen(text, 0));
    try stdt.testing.expectEqual(@as(usize, 8), nextGrapheme(text, 0));
}

test "unicode: o emoji com ZWJ é UM cluster" {
    const stdt = @import("std");
    // 👨 (4) ZWJ (3) 👩 (4) ZWJ (3) 👧 (4) = 18 bytes.
    const text = "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7";
    try stdt.testing.expectEqual(@as(usize, 1), graphemeCount(text));
    try stdt.testing.expectEqual(@as(usize, 18), graphemeLen(text, 0));
}

test "unicode: a bandeira seguinte é outro cluster" {
    const stdt = @import("std");
    // Duas bandeiras: 2 clusters.
    const text = "\xF0\x9F\x87\xA7\xF0\x9F\x87\xB7\xF0\x9F\x87\xA8\xF0\x9F\x87\xB3";
    try stdt.testing.expectEqual(@as(usize, 2), graphemeCount(text));
    try stdt.testing.expectEqual(@as(usize, 8), nextGrapheme(text, 0));
}

test "unicode: CRLF é um cluster" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(usize, 1), graphemeCount("\r\n"));
    try stdt.testing.expectEqual(@as(usize, 2), graphemeLen("\r\n", 0));
}

test "unicode: o Hangul compõe sílabas" {
    const stdt = @import("std");
    // L (U+1100) + V (U+1161) + T (U+11A8) = um cluster.
    const text = "\xE1\x84\x80\xE1\x85\xA1\xE1\x86\xA8";
    try stdt.testing.expectEqual(@as(usize, 1), graphemeCount(text));
}

test "unicode: o snap leva o clique ao início do cluster" {
    const stdt = @import("std");
    const text = "a\xCC\x81b";
    try stdt.testing.expectEqual(@as(usize, 0), snapToGrapheme(text, 1));
    try stdt.testing.expectEqual(@as(usize, 0), snapToGrapheme(text, 2));
    try stdt.testing.expectEqual(@as(usize, 3), snapToGrapheme(text, 3));
}

test "unicode: texto vazio e limites" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(usize, 0), graphemeCount(""));
    try stdt.testing.expectEqual(@as(usize, 0), graphemeLen("", 0));
    try stdt.testing.expectEqual(@as(usize, 0), prevGrapheme("", 0));
    try stdt.testing.expectEqual(@as(usize, 0), nextGrapheme("", 0));
    try stdt.testing.expectEqual(@as(usize, 0), snapToGrapheme("", 0));
}

test "unicode: texto malformado não trava" {
    const stdt = @import("std");
    // Um byte 0xFF solto (inválido).
    const bad = [_]u8{ 0xFF, 'a' };
    // Não deve entrar em laço infinito nem panicar.
    const n = graphemeCount(&bad);
    try stdt.testing.expect(n >= 1);
    try stdt.testing.expect(nextGrapheme(&bad, 0) <= bad.len);
    try stdt.testing.expect(prevGrapheme(&bad, bad.len) <= bad.len);
}

// ---------------------------------------------------------------------------
// Fuzz
// ---------------------------------------------------------------------------

test "fuzz unicode: os clusters são coerentes (nunca estouram o texto)" {
    try std.testing.fuzz({}, fuzzGrapheme, .{});
}

fn fuzzGrapheme(_: void, smith: *std.testing.Smith) !void {
    var buf: [64]u8 = undefined;
    smith.bytes(&buf);
    const n: usize = smith.valueRangeAtMost(u8, 0, 64);
    const text = buf[0..n];

    // A contagem de clusters é estável (a soma dos tamanhos).
    var pos: usize = 0;
    var count: usize = 0;
    while (pos < text.len) {
        const len = graphemeLen(text, pos);
        try std.testing.expect(len > 0);
        try std.testing.expect(pos + len <= text.len);
        // O cluster começa num codepoint.
        try std.testing.expect((text[pos] & 0xC0) != 0x80);
        pos += len;
        count += 1;
        if (count > 1000) return error.TestUnexpectedResult; // laço infinito
    }
    try std.testing.expectEqual(count, graphemeCount(text));

    // As navegações ficam dentro do texto.
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        try std.testing.expect(prevGrapheme(text, i) <= i);
        try std.testing.expect(nextGrapheme(text, i) >= i);
        try std.testing.expect(nextGrapheme(text, i) <= text.len);
        try std.testing.expect(snapToGrapheme(text, i) <= i);
    }
}
