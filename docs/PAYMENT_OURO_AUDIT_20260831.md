# Auditoria de pagamentos e matrícula automática — 31/08/2026

## Falhas encontradas

### 1. Profissão Rápida
O frontend/backend criava:
- payment.kind = `profissao_rapida_total`
- checkout.scope = `profissao_rapida`

As constraints do banco ainda aceitavam apenas:
- `matricula`, `primeira_mensalidade`
- `initial`, `enrollment`, `first_monthly`

Resultado: o enrollment interno era criado e o endpoint de pagamento retornava HTTP 500 antes de criar o checkout.

### 2. Ouro Moderno
Uma matrícula real chegou a:
- pagamento aprovado;
- vaga reservada;
- tentativa automática de criação do aluno.

O Ouro respondeu HTTP 400 com:
`E-mail > não informado`.

O Portal permitia matrícula paga sem e-mail, apesar de o Ouro exigir esse campo.

## Correções

- constraints ampliadas para Profissão Rápida;
- checkout Mercado Pago tornou-se idempotente/atômico no banco;
- comunicação com o bridge Mercado Pago passa por RPC server-side;
- `portal-payment` recupera sessão persistida caso a resposta interna falhe;
- webhook Mercado Pago usa a mesma ponte server-side;
- domínio de retorno do bridge passou a ser `https://www.liveconnect.com.br`;
- e-mail passou a ser obrigatório para matrícula paga;
- checkout também valida e-mail antes de cobrar;
- fila automática envia cadastros sem e-mail para `pendencia_documental`;
- retry automático ignora/segrega cadastros sem e-mail.

## QA

- bridge Mercado Pago: autenticado, HTTP 200;
- checkout Profissão Rápida: HTTP 200;
- preferência real Mercado Pago gerada com `init_point`;
- Ouro unit token: OK;
- endpoint de matrícula sem e-mail: HTTP 400 / `email_required`;
- nenhum aluno de QA foi criado no Ouro;
- nenhum pagamento de QA foi efetuado;
- registros locais QA removidos ao final.

## Estado após auditoria

Não restaram filas ativas presas em:
- `paga_aguardando_matricula`;
- `em_cadastro_ouro`;
- `pendencia_documental`.

O caso real que falhou antes da correção já estava cancelado e não foi reaberto automaticamente.
