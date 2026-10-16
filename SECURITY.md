# Security — ZyntraUI

## Escopo

Pré-release (`0.x`): sem garantia de suporte a versões antigas; correções de segurança entram na próxima versão de desenvolvimento.

## Como reportar

- **Vulnerabilidade não sensível** (ex.: validação de tamanho, tratamento de erro): abra uma issue pública no GitHub.
- **Vulnerabilidade sensível** (ex.: execução remota, corrupção de memória explorável via entrada não confiável): use um GitHub Security Advisory privado no repositório (aba Security) em vez de issue pública.

Ainda não há canal privado dedicado (e-mail de segurança): **pendente de decisão do mantenedor**. Não envie dados sensíveis por canais não solicitados.

## Cuidados esperados no código

Interfaces nativas e bindings são superfície de ataque: validar tamanhos, handles, strings e limites antes de cada chamada; nunca confiar em dados externos; tratar `error` sem silenciar; fuzzear traduções de entrada ao evoluir mapeamentos.

## Divulgação

Divulgação responsável: correção primeiro, detalhes públicos depois, com crédito ao reportador (salvo pedido contrário). CHANGELOG registra correções em `Security`.
