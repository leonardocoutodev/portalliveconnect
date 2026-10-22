# EAD online — cobrança pelo Admin antes da matrícula

Data: 2026-10-22

## Fluxo

1. Aluno escolhe uma formação ou módulo no catálogo EAD.
2. O site recalcula o preço no servidor usando a taxa ativa (R$ 15/hora).
3. O aluno envia a ficha de matrícula online.
4. O Admin recebe Lead + solicitação + cobrança pendente.
5. Nenhum acesso é liberado no Ouro enquanto o pagamento estiver pendente.
6. A equipe Live Connect realiza a cobrança e registra/confirma o pagamento.
7. O pagamento `ead_total` dispara o processamento EAD.
8. A fila muda para matrícula paga, o Ouro é provisionado e o Lead vira matrícula confirmada somente após sucesso.

## Produtos

- 30 formações ligadas aos cursos da Live Connect.
- 78 módulos EAD ligados individualmente aos IDs reais do Ouro Moderno.
- Módulos internos ficam `active=false` no catálogo tradicional para não poluir a oferta presencial.
- Cada solicitação recebe um `enrollment_id` na fila para impedir que um pagamento libere outra solicitação do mesmo aluno.

## Segurança

- Preço não vem do navegador; é recalculado no servidor.
- `portal_ead_request_create(jsonb)` é acessível somente via service_role.
- Edge Function pública não recebe acesso direto às tabelas.
- RLS permanece ativo nas tabelas de configuração/mapeamento.
- Consentimento de tratamento de dados é obrigatório.
- Produtos incompletos no Ouro são rejeitados antes da criação da solicitação.

## Endpoint

`portal-ead-enrollment-request` — ACTIVE v1

## Frontend

Pacote:
`Live_Connect_EAD_Catalogo_R15_Hora_v2.zip`

SHA-256:
`30232011e0237f4ca10d5ae650296b8d77f4a054d220e1871fb9f02fa985bc35`

A v2 substitui os CTAs de WhatsApp por uma ficha de matrícula online e deixa claro que a matrícula só é efetivada após a confirmação do pagamento.
