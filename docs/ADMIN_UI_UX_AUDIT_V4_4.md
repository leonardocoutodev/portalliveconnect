# Admin Live Connect V4.4 — Auditoria de Produto, UI e UX

## Causa estrutural

O shell administrativo reservava uma coluna para a sidebar e também aplicava `margin-left: 286px` no conteúdo. O espaço do menu era contabilizado duas vezes, empurrando a interface para a direita e reduzindo a área útil.

## Impactos

- dashboards comprimidos;
- excesso de espaço vazio à esquerda do conteúdo;
- tabelas com rolagem horizontal desnecessária;
- campos operacionais espremidos;
- baixa eficiência em desktop;
- experiência mobile baseada em miniaturas de tabelas desktop.

## Diretriz aplicada

O Admin passa a ser tratado como uma aplicação desktop-first:
- sidebar única;
- conteúdo fluido;
- densidade operacional;
- hierarquia visual compacta;
- mobile por reorganização semântica, não apenas redução de escala.

## V4.4

- sidebar desktop de largura controlada e sticky;
- remoção do deslocamento duplicado;
- conteúdo ocupa toda a largura restante;
- cabeçalho mais compacto;
- cards e métricas adaptativos;
- painéis com espaçamento consistente;
- formulários responsivos;
- tabelas comuns usam 100% da largura;
- tabelas com 8+ colunas só usam largura mínima quando necessário;
- mobile transforma linhas de tabela em cards usando `data-label`;
- modais: 3 colunas desktop, 2 tablet, 1 mobile;
- foco visível e controles com tamanho adequado;
- assets principais versionados com `v=440` para evitar cache antigo.

## QA

- todos os módulos JavaScript passam em `node --check`;
- referências estáticas do HTML validadas;
- CSS V4.4 validado por balanceamento estrutural;
- helper de tabelas inclui rótulos de coluna para o modo card mobile;
- nenhuma alteração de backend ou regra comercial foi necessária para esta revisão.
