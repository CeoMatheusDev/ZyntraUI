# ZyntraUI — Benchmarks

Medidos, não estimados. Metodologia: tempo externo (`date +%s%N`) sobre o
binário instalado, excluindo compilação; 3 execuções, mediana reportada.
O programa (`examples/bench.zig`, step `run-bench`) imprime checksum para
impedir eliminação por otimização.

## Carga (por execução)

* 200 frames × (5000 `rect_filled` + 500 `pushText` de 38 bytes + 1 evento
  `mouse_move` + `submit` ao `NullRenderer` com culling em viewport 1080p).
* Total: **1.100.000 comandos** (1.100.200 itens com eventos, cf. checksum).

## Resultados

Máquina: Intel Xeon E5-2680 v3 (24 threads), Linux x86_64,
alocador `page_allocator`.

Pipeline (commit `97f9f2f`, 2026-10-14):

| Modo | Tempo total | Por comando | Por frame (5500 cmds) |
|---|---|---|---|
| `ReleaseFast` | 19,0 ms | ~17 ns | ~95 µs |
| `Debug` | 282,5 ms | ~257 ns | ~1,4 ms |

Medianas de (19.04, 18.80, 21.33) ms e (287.6, 281.6, 282.5) ms.

Raster de referência, fase 2 do bench (50 renders de 5500 cmds, ~1006
desenhados em fb 800×600; commit `d84351f`, 2026-10-15):

| Modo | Total (fases 1+2) | Fase 2 (50 renders) | Por render |
|---|---|---|---|
| `ReleaseFast` | 471,9 ms | ~453 ms | ~9,1 ms |
| `Debug` | 6755 ms | ~6473 ms | ~129 ms |

Medianas de (466.6, 471.9, 483.1) ms e (6751, 6755, 6800) ms; fase 2 por
subtração das baselines acima, mesma sessão. Referência sem otimização:
~1,9 ns/pixel preenchido em ReleaseFast. Não usar em produção.

M48 (mesma carga): base da linha içada + ramos opaco/blend separados
em `fillRect` — total 327 ms ReleaseFast (~308 ms fase 2, ~1,46×) e
3820 ms Debug (~3538 ms fase 2, ~1,83×); pxsum bit-idêntico
(`293316480`). Medido, não estimado; ganho abaixo de ~10% reverte.

Lição registrada: sem `clear()`, o pxsum DIVERGIA entre modos (lixo do
alocador — Debug preenche com `0xAA`). Com `clear`, pxsum idêntico
(`293316480`, 6/6 execuções, ambos os modos). Framebuffer sem limpar tem
conteúdo indefinido — documentado em `SoftwareFramebuffer`.

## Nota de otimização (Zig 0.17)

`b.standardOptimizeOption` com `-Doptimize=ReleaseFast` gera o comando
`-Ofast` no Zig 0.17 (ver `zig build --verbose`). Comparações feitas com
`zig build-exe -OReleaseFast` (modo diferente) subestimam o desempenho em
~7x no build de comandos — todas as comparações abaixo usam o mesmo modo
do repo (`-Ofast`, via `zig build`).

## M153 — observabilidade, reservas e fill empacotado (2026-10-20)

Metodologia nova: o próprio `examples/bench.zig` mede cada fase com
`std.Io.Clock.awake` (aquecimento + 3 amostras, mediana reportada) e
imprime as métricas estendidas (M153). O tempo externo continua valendo
como total do processo.

Máquina: Intel Xeon E5-2680 v3, Linux x86_64, alocador `page_allocator`.
Carga igual à acima (200 frames × 5500 comandos + 50 renders do último
frame + 100 frames de treeview).

| Fase | Mediana (ReleaseFast) |
|---|---|
| Construção de comandos (200 frames) | ~45,5 ms (~13 ns/comando) |
| Raster (50 frames do último frame) | ~86,7 ms (~1,73 ms/frame) |
| Crescimentos de buffer no frame | **0** (com `reserve` antecipada) |

Métricas do frame medidas: `cmds=5500 visible=4824 culled=676 rects=5000
texts=500 bytes=18500 growths=0`; no raster: `fast=1001 generic=0
pixels=4311502` (o caminho rápido cobre todos os retângulos opacos).

### Antes × depois (v1.40.0 × HEAD), mesmo programa e mesmo modo

Micro-benchmarks isolados, `-Ofast`, 5 rodadas alternadas, mesma máquina:

| Fase | v1.40.0 | HEAD | Δ |
|---|---|---|---|
| Construção de comandos (20 frames × 5500 cmds) | 3.582 µs (32 ns/cmd) | 3.507 µs (31 ns/cmd) | **sem regressão** |
| Raster (50 renders, mesmo frame) | 332.973 µs | 87.278 µs | **3,8× mais rápido** |

O ganho do raster vem do fill opaco com escrita empacotada: com `-Ofast` o
compilador vetoriza o store de `u32` (o mesmo resultado de 4 stores de
byte fica 3,8× mais rápido neste workload). O `pxsum` do bench é
bit-idêntico.

O programa do bench (que agora reserva capacidade, mede 3 amostras e
reporta as métricas) tem números absolutos diferentes do programa antigo —
por isso a comparação acima usa o MESMO programa nas duas bibliotecas.

### Fill de retângulo opaco: A/B alternado

Micro-benchmark isolado (`fillRect` repetido, 64×64, 2000 chamadas por
tamanho), três variantes alternadas no mesmo processo/máquina, 5 rodadas:

| Variante | 16×16 | 64×64 | 256×256 |
|---|---|---|---|
| A: 4 stores de byte (histórico) | ~683 ns | ~10,1 µs | ~167,7 µs |
| B: escrita empacotada (`u32`) | ~542 ns | ~9,7 µs | ~148,1 µs |
| C: linha tipada `[]u32` | — | — | — |

* **B foi adotada**: ~12–20% mais rápida que A, de forma consistente
  (medianas de 5 rodadas alternadas). O `pxsum` do bench é bit-idêntico
  (`293181120`).
* **C foi descartada**: a linha tipada `[]u32` exigia `alignCast` do
  ponteiro do framebuffer (framebuffers construídos à mão podem ter
  ponteiro desalinhado) e, no build testado, ficou ~4× mais lenta. Não
  foi adotada.
* O ambiente é ruidoso (a mesma variante variou ~2× entre janelas de
  medição): as comparações acima são sempre alternadas e relativas.

Nota: a carga do bench passou a rodar 3 amostras (o `checksum` e o
`pxsum` mudaram de valor por isso — `3300600` e `293181120` — e são
determinísticos para a carga atual).

## Leitura

* Steady-state retém capacidade (`clearRetainingCapacity`): sem syscalls de
  crescimento após os primeiros frames; o custo é preenchimento + validação
  + iteração de culling.
* `Debug` inclui checks de segurança do Zig (~15×). Nenhuma otimização
  especulativa foi aplicada; medir de novo após mudanças na hot path.

## Reproduzir

```sh
zig build -Doptimize=ReleaseFast
t0=$(date +%s%N); ./zig-out/bin/zyntra-bench; t1=$(date +%s%N)
echo "$((t1-t0)) ns para 1100000 comandos"
```
