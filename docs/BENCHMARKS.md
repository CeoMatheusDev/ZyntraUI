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

Lição registrada: sem `clear()`, o pxsum DIVERGIA entre modos (lixo do
alocador — Debug preenche com `0xAA`). Com `clear`, pxsum idêntico
(`293316480`, 6/6 execuções, ambos os modos). Framebuffer sem limpar tem
conteúdo indefinido — documentado em `SoftwareFramebuffer`.

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
