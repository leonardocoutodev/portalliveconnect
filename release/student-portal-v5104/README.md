# Portal do Aluno — Finance normalization V5.10.4

## Incidente

O financeiro presencial estava induzindo o Portal a tratar parcelas futuras não quitadas como pendência/dívida, porque o bridge DKWeb retorna todos os lançamentos de `caixa` e o frontend histórico considera qualquer `quitado != 'S'` como "Em aberto".

## Diagnóstico

A auditoria dos acessos presenciais disponíveis mostrou:

- parcelas futuras são retornadas pelo DKWeb com `quitado = 'N'`;
- isso não significa atraso: uma parcela futura está apenas a vencer;
- os lançamentos vencidos observados pertencem ao curso ativo, portanto não eram resíduos de outro curso;
- o financeiro novo do Supabase não possui esses alunos antigos, então não há outra fonte interna automática para confirmar baixas antigas;
- por isso o Portal não deve inventar `Pago` quando o DKWeb ainda informa `N`.

## Correção V5.10.4

A Edge Function `dkweb-student-portal` agora normaliza o financeiro:

- remove estornos;
- deduplica lançamentos pelo número do lançamento;
- ignora lançamentos de vínculos que não fazem parte dos cursos retornados ao aluno;
- classifica cada lançamento como:
  - `paid` / Pago;
  - `overdue` / Vencido;
  - `due_today` / Vence hoje;
  - `upcoming` / A vencer;
  - `unknown` / A confirmar;
- parcelas futuras não entram mais em `finance`, que permanece como histórico visível para frontends legados;
- parcelas futuras são preservadas em `finance_upcoming`;
- todos os lançamentos normalizados ficam em `finance_all`;
- a resposta inclui `finance_summary` e `finance_normalization`.

A resposta passa a usar `portal_data_version = "5.10.4"`.

## Validação

Teste end-to-end contra o endpoint de produção:

Caso 1:
- 14 lançamentos no total;
- 2 futuros separados para `finance_upcoming`;
- nenhum futuro permaneceu no histórico visível;
- 2 vencidos mantidos;
- 10 pagos mantidos.

Caso 2:
- 12 lançamentos no total;
- 3 futuros separados para `finance_upcoming`;
- nenhum futuro permaneceu no histórico visível;
- 2 vencidos mantidos;
- 7 pagos mantidos.

Em ambos:
- `visible_has_upcoming = false`;
- `upcoming_all_upcoming = true`;
- `future_installments_are_debt = false`.

As sessões técnicas temporárias foram removidas após o teste. Restaram 0 sessões e 0 links temporários ativos.

## Limitação conhecida

Quando o DKWeb informa uma mensalidade passada como `quitado = 'N'`, `valor_pago = 0` e sem data de pagamento, o Portal mantém o lançamento como vencido. O sistema não altera esse dado para `Pago` sem uma fonte confiável de baixa.

Se houver alunos comprovadamente pagos que ainda apareçam vencidos no DKWeb, será necessário corrigir a baixa na origem ou integrar uma fonte financeira autoritativa adicional.
