# Supabase — Portal Live Connect

Este diretório versiona o estado operacional necessário para a integração do Portal com a Ouro Moderno.

## Fonte de verdade versionada

- `migrations/20260831_portal_ouro_auto_enrollment_snapshot.sql`
  - matrícula automática após pagamento;
  - reserva automática de turma presencial;
  - idempotência da matrícula Ouro;
  - captura criptografada da senha inicial;
  - fila manual de envio por WhatsApp;
  - reprocessamento automático;
  - limpeza de credenciais não utilizadas.

- `functions/portal-enrollment-submit/index.ts`
  - snapshot da Edge Function ativa v10.

- `functions/portal-first-access/index.ts`
  - função pública de primeiro acesso mantida desativada (HTTP 503), pois o envio de credenciais é manual pela Secretaria.

## Segredos

Nenhum valor de segredo deve ser commitado.

O runtime Supabase atual espera os nomes:
- `ouro_moderno_api_key`
- `portal_credentials_encryption_key`

A chave de criptografia pode ser criada automaticamente pela migration quando ausente. A chave da Ouro deve ser configurada no Vault.

## Atenção

Este snapshot pressupõe que o schema-base do Portal já exista. Ele versiona a camada operacional que foi alterada em 31/08/2026, não um dump completo de todos os dados do banco.
