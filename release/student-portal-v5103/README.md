# Portal do Aluno — DKWeb Academic Normalization V5.10.3

## Incidente

Foram relatados três sintomas no Portal do Aluno presencial:

- módulos aparecendo mais de uma vez;
- módulos com evidência acadêmica que não apareciam na trilha;
- notas/médias que não acompanhavam as avaliações atuais.

## Causa raiz comprovada

O Portal presencial recebe o resumo acadêmico do bridge DKWeb através da Edge Function `dkweb-student-portal`.

A auditoria de resumos reais mostrou inconsistências no payload do bridge 5.10.2:

- `modules[]` podia omitir módulos que estavam presentes em `grades[]`;
- em um caso de Mundo Digital 2026, `modules[]` veio vazio embora existissem avaliações de três módulos;
- em Mundo Digital 2025, Microsoft Word Fast existia nas notas, mas não em `modules[]`;
- o bridge podia retornar mais de uma linha `MÉDIA` para o mesmo módulo;
- a linha `MÉDIA` podia divergir do cálculo das avaliações por arredondamento/atualização;
- o mesmo curso pode ter quantidades diferentes de módulos efetivamente vinculados ao aluno, então não é seguro inventar módulos apenas pelo catálogo comercial.

## Correção

A versão 13 de `dkweb-student-portal` normaliza o resumo antes de devolvê-lo ao Portal:

1. deduplica módulos pela chave `id_aluno_curso + id_modulo`;
2. recupera módulos ausentes quando existe evidência em `grades[]`;
3. deduplica avaliações repetidas por chave estável;
4. descarta múltiplas linhas `MÉDIA` da origem;
5. recalcula exatamente uma média por módulo a partir das avaliações atuais;
6. preserva os demais blocos do resumo: cursos, materiais, frequência, financeiro e capacidades;
7. continua sem cache no endpoint.

A resposta passa a incluir:

- `portal_data_version: "5.10.3"`;
- `academic_normalization` com contadores de normalização.

## Validação com dados reais

Foram auditadas quatro identidades recentes sem alterar notas, matrículas ou frequência.

Resultados do endpoint de produção após a correção:

- Gestão Empresarial: 6 módulos -> 6; nenhuma duplicidade.
- Gestão Empresarial: 4 módulos -> 4; nenhuma duplicidade.
- Mundo Digital 2025: 3 módulos brutos -> 4 módulos normalizados, recuperando Microsoft Word Fast; uma MÉDIA duplicada removida.
- Mundo Digital 2026: 0 módulos brutos -> 3 módulos normalizados (Digitação, Windows 11 e Introdução à Informática V3); duas MÉDIAS duplicadas removidas.

Em todos os casos finais:
- `duplicate_modules=[]`;
- `duplicate_medias=[]`;
- uma única média por módulo.

O teste end-to-end criou sessões técnicas temporárias somente para leitura e as removeu no `finally`. Após o teste:
- 0 sessões `audit-temp` restantes;
- 0 RPCs auxiliares de auditoria restantes.

A Edge Function temporária de auditoria foi desativada e exige JWT.

## Produção

Edge Function:

`dkweb-student-portal`

Versão Supabase:

`13`

SHA da Edge Function:

`fca801974aa1c9b3de40e9b8bc58d1b61fba28d4c4bb60932e1fb5a6f493aaf1`

O frontend da KingHost não precisou ser alterado para esta correção: os campos existentes `modules` e `grades` continuam com o mesmo contrato, porém normalizados.
