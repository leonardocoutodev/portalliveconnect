# Pagamento + matrícula automática — V5.6.0

Marco de produção de 02/09/2026.

## Fluxo ativo

1. O aluno envia a ficha pelo Portal Live Connect.
2. O checkout é criado pelo backend.
3. Mercado Pago confirma o pagamento por webhook.
4. A atualização em `payments` aciona `sync_portal_enrollment_queue_payment`.
5. A fila passa para processamento e chama `private.portal_auto_process_paid_enrollment`.
6. O aluno é criado/vinculado na Ouro Moderno e recebe os cursos mapeados.
7. A fila termina em `matriculada_ouro` ou `matriculada_manual`.
8. O lead passa para `matricula_confirmada`.
9. As credenciais ficam preparadas para envio manual pela secretaria via WhatsApp.

## Proteção contra cobrança sem matrícula

`portal_course_auto_enrollment_ready(course_id)` bloqueia a abertura do checkout quando a formação não possui mapeamento Ouro válido.

No momento da auditoria, 29 cursos pagos ativos estavam prontos para o fluxo automático. Quatro formações ficaram protegidas até mapeamento: Atendente de Farmácia, Auxiliar Administrativo, Inglês Fluente e Profissional da Beleza.

## Produção

- `portal-payment`: v13
- `mercadopago-portal-webhook`: v8
- `portal-gateway` self-test: OK
- retorno Mercado Pago: `https://www.liveconnect.com.br/pagamento/`

O frontend KingHost V5.6.0 acompanha pagamento e matrícula separadamente e só exibe conclusão após a fila automática terminar.
