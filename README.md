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

## Fluxo operacional vigente — matrícula automática Ouro Moderno (31/08/2026)

A matrícula não depende mais de aprovação manual da Secretaria.

Fluxo:

1. ficha de matrícula no Portal;
2. pagamento aprovado ou matrícula isenta, conforme a regra comercial;
3. o gatilho de pagamento inicia automaticamente o processamento;
4. se a modalidade for presencial, o Portal reserva automaticamente uma vaga na turma selecionada;
5. o Portal identifica ou cria o aluno na Ouro Moderno;
6. resolve os cursos Ouro pelo mapeamento acadêmico;
7. matricula somente os cursos ainda não vinculados ao aluno;
8. verifica a matrícula diretamente na Ouro;
9. confirma a ocupação da vaga presencial, quando aplicável;
10. conclui a fila como `matriculada_ouro`;
11. a matrícula entra na fila de credenciais pendentes para envio manual pela Secretaria.

Controles incorporados:

- idempotência para evitar duplicidade de aluno e cursos;
- validação de que a turma pertence ao curso da matrícula;
- tratamento separado para Presencial e EAD;
- registro do ID do aluno Ouro, IDs dos cursos e contratos;
- contador e horário de tentativas;
- reprocessamento automático a cada 5 minutos para falhas transitórias, limitado por tentativas;
- erro explícito quando não houver turma/vaga/mapeamento válido;
- auditoria de sucesso e falha.

## Primeiro acesso e WhatsApp

O envio das credenciais é deliberadamente manual.

Para aluno novo:

1. a Ouro cria o aluno e devolve usuário + senha inicial;
2. a senha inicial é criptografada no schema privado;
3. a matrícula aparece para a Secretaria como credencial pendente;
4. a Secretaria abre a mensagem pronta;
5. envia a mensagem manualmente pelo WhatsApp;
6. marca como enviada;
7. a senha inicial é eliminada do banco após a confirmação de envio.

No primeiro login, a própria Ouro obriga o aluno a criar uma nova senha pessoal.

Para aluno já existente na Ouro:

- o Portal não cria nem inventa uma nova senha;
- a Secretaria envia o usuário existente e a orientação para usar a senha atual ou “Esqueceu a senha?”.

Funções operacionais:

- `school_secretary_pending_credentials` — lista matrículas aguardando WhatsApp;
- `school_secretary_prepare_first_access` — monta a mensagem e disponibiliza usuário/senha inicial somente para Secretaria autenticada;
- `school_secretary_mark_credentials_whatsapp_sent` — registra o envio e elimina a senha inicial.

As funções de credenciais não podem ser executadas pelo papel anônimo.

## Segurança das credenciais

- chave de criptografia no Vault;
- senha nunca gravada em leads, fila pública ou logs;
- tabela de credenciais no schema privado com RLS;
- credenciais iniciais não utilizadas são eliminadas automaticamente após 72 horas;
- nenhuma automação de e-mail para credenciais;
- a Edge Function pública de primeiro acesso permanece desativada, pois o envio passou a ser exclusivamente manual via Secretaria/WhatsApp.

## Frontend

O repositório `portalliveconnect` contém somente documentação.

A conta Netlify conectada não contém o projeto `portallc`.

Na Vercel foram localizados protótipos `portal-live-connect-2026` até `portal-live-connect-2026-v4`. A v4 ainda contém fluxos demonstrativos e não deve substituir a produção.

O backend operacional está preparado para o painel real da Secretaria consumir as funções de credenciais quando o frontend de produção estiver disponível para edição.

A credencial da API Ouro permanece no Vault/Supabase e não é exposta ao navegador.
