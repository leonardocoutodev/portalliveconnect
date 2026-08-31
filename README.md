# Portal Live Connect

Portal institucional, comercial e acadêmico da Live Connect Escola de Profissões.

## Produção

- Site: https://portallc.netlify.app
- Backend: Supabase
- Integração acadêmica: Ouro Moderno
- Deploy: Netlify

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

## Primeiro acesso do aluno

O backend captura a senha inicial retornada pela Ouro somente no momento da criação de um novo aluno e a armazena criptografada no schema privado do Supabase.

O fluxo de entrega é:

1. matrícula concluída na Ouro;
2. usuário e senha inicial são vinculados à matrícula;
3. a Secretaria solicita a mensagem de primeiro acesso;
4. o backend gera um link único, com validade de 24 horas;
5. o aluno abre o link e visualiza usuário + senha inicial uma única vez;
6. a senha inicial é apagada do banco após a visualização;
7. no primeiro login, a Ouro obriga o aluno a criar uma nova senha pessoal.

Controles de segurança:

- chave de criptografia guardada no Vault;
- senha nunca gravada em leads, fila pública, logs ou auditoria;
- tabela de credenciais em schema privado com RLS;
- token armazenado somente como hash;
- link de uso único e com expiração;
- endpoint de primeiro acesso sem cache;
- alunos já existentes não recebem senha inventada; usam o acesso existente ou recuperação de senha.

A Edge Function `portal-first-access` está ativa e o endpoint `portal-enrollment-submit` está na versão 8, aceitando e-mail quando fornecido.

## Pendências para fechamento 100% da operação

- O frontend real do Portal/Secretaria não está presente neste repositório, portanto o botão visual "Enviar acesso pelo WhatsApp" ainda precisa ser ligado ao RPC `school_secretary_prepare_first_access`.
- A conta Netlify conectada não contém o projeto `portallc`, então o deploy visual não pode ser atualizado por esta conexão atual.
- Não há provedor de e-mail transacional configurado no Supabase Vault; a automação de e-mail está bloqueada até a configuração de um provedor (ex.: Resend/Postmark/SendGrid/SMTP externo compatível com Edge Functions).

A credencial da API Ouro permanece no Vault/Supabase e não é exposta ao navegador.
