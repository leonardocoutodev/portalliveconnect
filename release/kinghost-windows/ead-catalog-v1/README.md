# Live Connect EAD — catálogo R$ 15/hora

Data: 2026-10-22

## Regra comercial

- Taxa única: **R$ 15,00 por hora/aula**.
- Módulo avulso: carga horária do módulo no Ouro Moderno × R$ 15.
- Formação completa: soma da carga horária dos módulos confirmados no Ouro Moderno × R$ 15.
- Módulos sem vínculo/carga confirmados não são publicados como produto.
- Formações com qualquer módulo pendente ficam com EAD indisponível até o mapeamento ser concluído.

## Backend

Edge Function: `portal-ead-catalog`
- status: ACTIVE
- verify_jwt: false
- somente leitura
- CORS restrito aos domínios Live Connect/rollback
- usa chave de servidor apenas no Edge Function
- cache público de 5 minutos

Configuração:
- tabela `portal_ead_pricing_settings`
- `hourly_rate = 15.00`
- RLS ativo
- acesso direto de anon/authenticated revogado
- policy exclusiva para service_role

Estado inicial:
- 30 formações cadastradas
- 25 formações com todos os módulos confirmados e preço calculado
- 78 módulos únicos com carga horária e preço
- 5 formações ainda dependem de mapeamento completo

## Frontend KingHost

Pacote gerado:
`Live_Connect_EAD_Catalogo_R15_Hora_v1.zip`

SHA-256:
`8237c34cf41cef2ab9a1e03473bc31eeb045d2658df2d3841be1d727869f443f`

Destino sugerido:
`d:\\web\\localuser\\liveconnect\\www\\ead\\`

URL final:
`https://www.liveconnect.com.br/ead/`

O pacote contém página responsiva com:
- abas Formações completas / Módulos avulsos;
- busca;
- filtro de módulos por formação;
- carga horária;
- quantidade de aulas;
- preço calculado;
- detalhamento dos módulos de cada formação;
- CTA para WhatsApp oficial da Live Connect.
