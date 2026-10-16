# Contributing — ZyntraUI

## Como contribuir

1. Abra uma issue descrevendo o problema ou a proposta antes de mudanças grandes (API, widgets, layout).
2. Crie um branch a partir de `main`: `feat/...`, `fix/...`, `docs/...`, `test/...`, `ci/...`, `chore/...`.
3. Trabalhe incrementalmente sobre o código existente; não recrie módulos funcionais nem mova arquivos sem necessidade.
4. Atualize `CHANGELOG.md` em `## [Não lançado]` para descrever a mudança.
5. Abra o PR com o template preenchido e referências a issues relacionadas.

## Antes de enviar

```bash
zig build
zig build test
zig build run-example  # se aplicável
zig fmt --check .
```

## Padrão de commits

Use Conventional Commits. Pequenos commits focados em uma única preocupação:

```text
feat(widget): add new toolbar layout
fix(text): preserve grapheme cluster on cursor move
test(ui): add selection edge cases
docs: update README for new example
ci: add job for Zig 0.17.0
chore: tidy up examples
```

Sem `push --force` para histórico publicado. Um commit = uma preocupação.

## Requisitos para aprovação

- Build e testes verdes; `zig fmt --check` limpo.
- API pública preservada ou breaking change documentada no CHANGELOG.
- Documentação atualizada para refletir mudanças de comportamento público.
- Nenhuma funcionalidade fictícia; testes declarados devem ser executáveis.

## Aprovação e releases

Revisão pelo mantenedor. Tags `vX.Y.Z` e GitHub Releases são publicadas pelo mantenedor após validação completa.
