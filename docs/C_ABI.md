# ZyntraUI — Integração C (C-ABI)

Camada opcional em `src/c-abi/` (M5). A API Zig (`@import("zyntra_ui")`)
continua sendo a interface principal.

## Inicialização / destruição

```c
ZyntraContext *ctx = NULL;
ZyntraRect vp = {0, 0, 800, 600};
if (zyntra_context_create(vp, &ctx) != ZYNTRA_OK) { /* ... */ }
// ... um frame por vez: begin -> push/draw -> end ...
zyntra_context_destroy(ctx); // exatamente uma vez; NULL é seguro
```

## Handles

* `ZyntraContext*` é opaco: nunca desreferenciar, copiar o struct interno
  (não existe na fronteira) ou liberar com `free`.
* Um handle, uma thread por vez. Sem locks internos.

## Ownership e lifetime

* `create` aloca no `page_allocator` interno da camada C-ABI; `destroy`
  libera eventos + draws + o próprio handle.
* `begin_frame` invalida eventos/desenhos do frame anterior (retém
  capacidade). Contagens obtidas valem até o próximo `begin`/`destroy`.
* Nenhum slice/string Zig cruza a fronteira na M5 — só tipos de tamanho
  fixo (`float`, `u8`, `u32`, `u64`, structs abaixo).

## Erros

Toda função retorna `ZyntraResult` (`0 == ZYNTRA_OK`):

| Código | Significado |
|---|---|
| `ZYNTRA_OK` | sucesso |
| `ZYNTRA_INVALID_ARGUMENT` | handle/saída nulo, viewport negativo, botão > 2 |
| `ZYNTRA_OUT_OF_MEMORY` | falha de alocação do `page_allocator` |
| `ZYNTRA_INVALID_EVENT` | evento rejeitado na validação |
| `ZYNTRA_INVALID_COMMAND` | comando de desenho inválido (ex.: largura negativa) |
| `ZYNTRA_INVALID_STATE` | `begin` com frame ativo / `end` sem frame ativo |
| `ZYNTRA_INVALID_TEXT` | UTF-8 malformado em `zyntra_draw_text` |

## Strings, buffers, callbacks

* M6: `zyntra_draw_text(handle, pos, color, size, utf8, utf8_len)` copia os
  bytes para a arena da `DrawList` — o chamador pode liberar o buffer logo
  após o retorno. UTF-8 malformado retorna `ZYNTRA_INVALID_TEXT`.
  `utf8_len == 0` aceita ponteiro NULL (run vazio válido).
* Sem callbacks na fronteira. Demais strings/buffers: fora de escopo.

## Compatibilidade ABI

* Structs `extern` com tamanhos travados (`_Static_assert` no C,
  `@compileError` no Zig): `ZyntraVec2=8`, `ZyntraSize=8`,
  `ZyntraRect=16`, `ZyntraColor=4`; `ZyntraResult` é `c_int`.
* Símbolos C estáveis listados em `src/c-abi/zyntra.h`.
* Quebra de layout/assinatura exige MAJOR bump.

## Teste de integração

Consumidor C real em `tests/c/test_c_abi.c`:

```sh
zig build                          # gera zig-out/lib/libzyntra_ui.a
zig cc tests/c/test_c_abi.c zig-out/lib/libzyntra_ui.a \
  -Isrc/c-abi -o /tmp/opencode/zyntra-c-test
/tmp/opencode/zyntra-c-test        # esperado: "C-ABI OK ..."
```
