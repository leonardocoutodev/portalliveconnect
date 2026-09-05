# Live Connect Portal V5.9.1 — White-label frontend

## Objetivo
Remover do frontend público qualquer referência nominal a fornecedor/plataforma acadêmica externa, mantendo as integrações existentes exclusivamente como infraestrutura de backend.

## Mapeamento
A revisão cobriu 56 rotas `index.html`, incluindo:
- home;
- catálogo e páginas individuais de cursos;
- categorias;
- gratuitos;
- Jovem Aprendiz;
- NRs;
- cursos curtos;
- Área do Aluno;
- pagamento;
- contato, sobre, privacidade e termos;
- redirecionamento do Admin.

## Alterações
- Área do Aluno identificada somente como Live Connect.
- Login EAD/presencial mantido, com textos e nomes de campos neutros.
- Catálogos acadêmicos normalizados no JavaScript para nomes públicos neutros.
- Mensagens de erro, analytics, labels, comentários e seletores CSS neutralizados.
- Links de acesso EAD não expõem o fornecedor no HTML.
- Textos de materiais, financeiro e certificados presenciais neutralizados.
- JavaScript antigo do Admin hospedado na KingHost substituído por redirect stub para o Admin Cloudflare.
- Rota pública legada `/dkweb/` redirecionada com 301 para `/area-do-aluno/` e adicionada ao robots.txt.
- Arquivos TXT antigos de deploy na raiz pública sanitizados.
- Cache-bust frontend atualizado para `v=591`.

## Segurança e compatibilidade
- O patch não inclui `App_Data/`, `dkweb-api/` nem arquivos de configuração/segredos.
- A integração acadêmica de backend não é removida nem alterada.
- Login unificado EAD/presencial permanece preservado.
- Deploy do Portal continua manual na KingHost.

## QA
- 10 módulos JavaScript relevantes validados por sintaxe.
- ZIP validado por integridade.
- Varredura do patch: zero ocorrências públicas de nomes do fornecedor ou do domínio externo.
