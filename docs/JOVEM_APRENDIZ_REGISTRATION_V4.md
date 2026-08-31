# Projeto Jovem Aprendiz — Ficha de inscrição V4

## Portal

Os CTAs do Projeto Jovem Aprendiz abrem uma ficha completa seguindo o padrão documental usado nas inscrições gratuitas.

Dados coletados:
- nome e WhatsApp;
- data de nascimento e idade;
- RG e CPF opcionais;
- situação escolar;
- turno disponível;
- CEP e endereço;
- responsável legal quando o participante é menor de 18 anos;
- consentimento para inscrição e contato.

O CEP usa o mesmo preenchimento assistido já usado no portal.

## CRM e banco

Cada envio:
1. localiza ou cria o lead pelo WhatsApp;
2. registra interesse `jovem_aprendiz`;
3. grava atividade no CRM;
4. cria snapshot em `young_apprentice_registration_forms`.

A tabela documental possui status:
- `preenchida`;
- `em_contato`;
- `confirmada`;
- `cancelada`.

## Admin

Nova área **Comercial > Jovem Aprendiz**:
- lista fichas;
- mostra idade, situação escolar e turno;
- permite atualizar status;
- abre ficha pronta para impressão;
- registra a data da impressão.

## Backend

- Edge Function: `portal-young-apprentice-submit`.
- Portal Gateway: `service=young`.
- Acesso direto à tabela pública é bloqueado por RLS/revokes.
- Leitura e alterações administrativas passam por RPCs com validação de `is_admin_comercial()`.

## QA

Foi executado teste interno com dados fictícios:
- criação do lead;
- criação do interesse;
- criação da ficha;
- leitura pela RPC administrativa;
- atualização de status;
- marcação de impressão;
- limpeza integral dos registros de teste.

Todos os arquivos JS V360 da V4.0 passaram no `node --check`.
