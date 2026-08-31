# Portal Live Connect V5.0 — Home 10/10

## Objetivo

Reconstrução da página principal com foco em conversão, performance, clareza de posicionamento e experiência mobile/desktop.

## Produto e conversão

A nova Home segue esta ordem:

1. Hero com proposta de valor direta.
2. Sinais de confiança e presença local.
3. Navegação por objetivo do visitante.
4. Formações em destaque.
5. Profissão Rápida.
6. Confiança local e localização.
7. Cursos gratuitos + Jovem Aprendiz.
8. Diferenciais.
9. FAQ.
10. CTA final.

## Prova de confiança

A Home usa como referência pública atual:
- nota 5,0 no Google;
- mais de 200 avaliações;
- presença em Ilhéus desde 2016;
- unidade física no Centro.

## Cards de cursos

Os cards foram redesenhados para eliminar molduras aninhadas.

Estrutura:
- imagem 16:9 dominante;
- apenas um badge de categoria;
- título e resumo;
- fatos essenciais;
- CTA textual.

O mosaico de módulos foi removido do card de catálogo.

### Imagens

O mapeamento final foi validado em 30/30 cursos:
- 30 imagens resolvidas;
- 30 hashes visuais únicos;
- nenhum arquivo repetido entre cards;
- duplicidades antigas foram substituídas por assets dos próprios módulos do curso, mantendo contexto.

## Performance

A Home deixa de carregar as folhas legadas no caminho crítico.

CSS crítico V5:
- public-core.v500.css
- cards.v500.css
- home.v500.css

Total bruto aproximado: 20 KB.

Antes: ~171 KB de CSS legado bloqueante.

Também foram aplicados:
- import dinâmico do Admin;
- import dinâmico de Forms;
- CSS legado carregado sob demanda/idle;
- logo otimizado;
- mascotes da Home redimensionados;
- apenas a foto principal usa fetchpriority=high.

## Campanhas

Popup deixa de abrir com 1,8 segundo.
Novo gatilho:
- 12 segundos; ou
- 42% da página rolada.

## SEO

SEO estrutural existente foi preservado.
Sitemap teve lastmod atualizado para 2026-08-31.

## Separação do Admin

O link administrativo aponta para:
https://admin.liveconnectios.workers.dev/

O Netlify redireciona /admin para o Admin oficial.

## Rollback

Foi preservado o pacote completo anterior antes da V5:

Live_Connect_PORTAL_ROLLBACK_PRE_V5.0.zip

SHA-256:
111a7256e2174757a056b2d7e73c7354082a690aa17448e321adc2f7068ca53f

Também foi criada no GitHub a branch:
portal-pre-v5-rollback-20260831

A V5 é uma alteração de frontend e não exige rollback de banco.
