# Portal Live Connect

Portal institucional, comercial e acadêmico da Live Connect Escola de Profissões.

## Produção

- Site: https://portallc.netlify.app
- Backend: Supabase
- Integração acadêmica: Ouro Moderno
- Deploy histórico/documentado: Netlify
- Protótipos adicionais localizados: Vercel

## Versão atual

V3.4 — UI/UX Hardening

## Marco operacional — matrícula automática Ouro Moderno (31/08/2026)

O Portal Live Connect passou a criar matrículas diretamente pela integração autorizada com a Ouro Moderno.

Fluxo operacional:

1. ficha de matrícula no Portal;
2. pagamento aprovado;
3. aprovação e reserva de turma pela Secretaria;
4. identificação ou criação do aluno na Ouro Moderno;
5. resolução dos cursos Ouro pelo mapeamento acadêmico do Portal;
6. matrícula dos cursos na Ouro;
7. verificação independente dos cursos vinculados ao aluno;
8. ocupação definitiva da vaga da turma e confirmação da matrícula no Portal.

Controles incorporados:

- idempotência para evitar duplicidade de aluno e de cursos;
- registro do ID do aluno Ouro, IDs dos cursos e contratos;
- contador e horário das tentativas;
- registro sanitizado de erros e retornos;
- reprocessamento seguro pela Secretaria;
- fallback manual quando a integração não puder concluir;
- bloqueio quando o curso não possuir mapeamento Ouro confiável;
- auditoria de sucesso e falha.

## Primeiro acesso do aluno — backend incorporado

O backend captura a senha inicial retornada pela Ouro somente no momento da criação de um novo aluno e a armazena criptografada no schema privado do Supabase.

Controles incorporados:

- chave de criptografia guardada no Vault;
- senha nunca gravada em leads, fila pública, logs ou auditoria;
- tabela de credenciais em schema privado com RLS;
- credenciais iniciais não utilizadas são apagadas automaticamente após 72 horas;
- alunos já existentes não recebem senha inventada; usam o acesso existente ou recuperação de senha;
- o endpoint `portal-enrollment-submit` está na versão 9 e aceita e-mail quando fornecido sem apagar e-mails antigos quando o campo não vier preenchido.

A Ouro foi validada em primeiro acesso: após autenticação com a senha inicial, o aluno recebe a tela obrigatória "Atualizar Senha", com senha atual, nova senha e confirmação.

## Entrega segura — estado atual

Foi identificado que tokens enviados em query string aparecem nos logs de Edge Functions. Por segurança, a entrega por link foi desativada até que a página de primeiro acesso seja implementada no frontend real do Portal utilizando fragmento `#` + POST, sem registrar o token na URL do servidor.

A Edge Function `portal-first-access` está em modo seguro/indisponível (HTTP 503) e não entrega credenciais enquanto o frontend correto não estiver publicado.

## Frontend

O repositório `portalliveconnect` contém apenas documentação.

A conta Netlify conectada não contém o projeto `portallc`.

Na Vercel foram localizados os projetos:
- `portal-live-connect-2026`
- `portal-live-connect-2026-v2`
- `portal-live-connect-2026-preview`
- `portal-live-connect-2026-v3`
- `portal-live-connect-2026-v4`

A versão v4 é um protótipo demonstrativo e não deve substituir a produção: o próprio código ainda simula matrícula, Ouro e pagamento.

## Automação de e-mail

O backend já preserva e-mail do aluno quando recebido pela ficha e registra o estado da entrega de credenciais.

Ainda não existe provedor de e-mail transacional configurado no Supabase Vault. Para envio automático é necessário configurar um provedor de e-mail transacional compatível com Edge Functions (ex.: Resend, Postmark ou SendGrid).

A credencial da API Ouro permanece no Vault/Supabase e não é exposta ao navegador.
