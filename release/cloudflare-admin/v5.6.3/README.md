# Admin Live Connect V5.6.3 — recuperação completa

Data: 2026-09-02

## Incidente

O Admin em `admin.liveconnectios.workers.dev` ficou preso em **Carregando Live Connect…** e apareceu sem CSS/logo.

Diagnóstico: o HTML inicial estava disponível, mas os assets em `/assets/...` não estavam sendo servidos. O comportamento é compatível com publicação de um pacote parcial no Cloudflare, substituindo o conjunto completo de assets do deploy anterior.

## Correção

O pacote completo V5.6.3 deve conter todos os arquivos do Admin V5.2 e as alterações posteriores, não apenas o patch incremental.

Inclui:
- CSS, logo, imagens e todos os módulos JavaScript;
- cache-bust V5.6.3;
- fallback visual caso o bundle estático deixe de carregar;
- turma exata do Jovem Aprendiz:
  - Terça-feira — 09:00 às 10:00
  - Quinta-feira — 14:00 às 15:00
- ficha em duas vias com **TURMA ESCOLHIDA**;
- cadastro manual exigindo a turma;
- fichas antigas pedindo seleção antes de imprimir.

## Backend

Aplicado no projeto Supabase **Live Connect Comercial**:
- RPC `school_commercial_set_young_apprentice_class(uuid,text)`;
- `admin_manual_registration_create(jsonb)` atualizado para persistir a turma;
- Edge Function `portal-young-apprentice-submit` atualizada para validar e gravar a turma.
