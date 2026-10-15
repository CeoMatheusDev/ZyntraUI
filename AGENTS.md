# ZyntraUI — instruções persistentes

Biblioteca GUI modular em **Zig 0.17.0**: núcleo enxuto, API Zig nativa,
C-ABI opcional, memória explícita, sem renderer/GPU próprio.
Repositório: https://github.com/CeoMatheusDev/ZyntraUI

## Preservar

- Arquitetura modular, API Zig, ABI C, ownership/lifetime, roadmap.
- Sem features, refactors, renomeações ou dependências fora do escopo.
- Nunca inventar APIs, resultados de testes, commits ou pushes.

## Fluxo por tarefa

1. Analisar: objetivo, arquivos relevantes, contratos, risco de regressão.
2. Implementar pequeno e verificável, só arquivos da tarefa.
3. Validar de verdade antes de prosseguir:
   - `zig build test --summary all`
   - `zig fmt --check src/ examples/ build.zig`
   - exemplo/integração C (`zig cc …` + executar) quando afetados
   - Investigar falhas; corrigir; revalidar. Nunca afirmar sem executar.
4. Revisar o diff; sem segredos; `git status` + stage seletivo.
5. Commit descritivo (Conventional Commits) e push; confirmar no remoto.
6. Relatar: feito, validado, testes, commit, push, impacto SemVer, pendências.

## Git — proibido sem autorização explícita

`push --force`, `reset --hard`, `clean -fd`, excluir branches/tags,
reescrever histórico. Preservar tags e releases publicadas.

## Versionamento (SemVer 2.0.0)

- Commit + push NÃO é release. Sem bump por commit; sem release automática.
- Registrar impacto em `## [Não lançado]` do CHANGELOG.md.
- Release só com batch pronto e aprovado: prep commit → tag `vX.Y.Z` →
  push da tag → `gh release create` (`--prerelease` para alpha/beta/rc).
