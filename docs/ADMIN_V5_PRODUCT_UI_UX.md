# Admin Live Connect V5.0 — Reconstrução de Produto, UI e UX

## Objetivo

Transformar o Admin em uma aplicação administrativa independente do Portal, desktop-first e operacional, preservando todas as regras, integrações e dados existentes.

## Mudanças estruturais

- O runtime do Admin carrega apenas um design system dedicado: `admin-v50.css`.
- As folhas antigas do Portal e as camadas de override deixam de participar do runtime.
- A quantidade de `!important` do design system novo é zero.
- Sidebar e conteúdo passam a ocupar apenas suas próprias colunas, sem deslocamento duplicado.
- Navegação é organizada em grupos recolhíveis para diminuir rolagem e carga cognitiva.

## Home

A Home deixa de repetir departamentos e indicadores. A prioridade passa a ser:
1. ações que precisam de intervenção;
2. indicadores essenciais;
3. atalhos de trabalho;
4. saúde geral da operação.

## Tabelas

- Até 9 colunas: sem largura mínima artificial em desktop.
- Apenas tabelas realmente largas usam overflow interno.
- Exportar vira ação secundária.
- Status ganham semântica visual consistente.
- No mobile, linhas de tabela viram cards com rótulos e ações empilhadas.

## CRM

A tela de Leads deixa de carregar apenas os 200 registros mais recentes.
- nova RPC `school_commercial_leads_search`;
- busca server-side;
- filtro server-side por status;
- paginação de 100 registros;
- total real da base.

## Busca global

A nova RPC `school_admin_global_search` pesquisa diretamente no banco:
- leads;
- alunos/matrículas;
- contratos;
- Jovem Aprendiz.

O Admin não precisa mais baixar centenas de registros de quatro fontes para pesquisar no navegador.

## Mensagens técnicas

Falhas do Ouro deixam de aparecer cruas no campo operacional. A interface mostra uma mensagem humana e mantém os detalhes técnicos recolhidos para diagnóstico.

## Responsividade

Desktop:
- sidebar 248 px;
- conteúdo fluido;
- tipografia mínima confortável;
- modais de até 1180 px;
- formulários de 3 ou 4 colunas conforme contexto.

Tablet:
- layouts de 2 colunas;
- sidebar como drawer abaixo de 1020 px.

Mobile:
- tabelas em cards;
- uma coluna;
- ações com largura total;
- drawer lateral;
- modais quase full-screen.

## Segurança

As novas funções de busca usam `SECURITY INVOKER` e continuam subordinadas às políticas RLS e às funções de autorização existentes.

O advisor de segurança não aponta alertas específicos para as novas RPCs.
