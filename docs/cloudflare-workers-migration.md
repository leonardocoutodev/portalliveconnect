# Migração planejada — Cloudflare Workers

## Objetivo

Migrar a camada web do Portal Live Connect para Cloudflare Workers e, a partir daí, usar deploy automático conectado ao GitHub.

## Estado preservado antes da migração

O repositório contém:
- documentação operacional;
- snapshot SQL da integração Ouro;
- Edge Functions Supabase relevantes;
- regras de credenciais manuais por WhatsApp.

O Supabase continua sendo o backend/BD enquanto não houver decisão explícita de migrar também a camada de dados.

## Estratégia recomendada para o próximo marco

1. recuperar/portar o frontend real de produção;
2. criar o projeto Worker;
3. adicionar `wrangler.jsonc` ou `wrangler.toml`;
4. mapear variáveis públicas e secrets;
5. adaptar endpoints hoje implementados como Supabase Edge Functions quando fizer sentido;
6. conectar o repositório ao Cloudflare Workers Builds ou GitHub Actions + Wrangler;
7. configurar deploy automático apenas para a branch `main`;
8. usar preview deployments para alterações antes de promover a produção;
9. executar smoke tests de matrícula, pagamento, Ouro e fila de credenciais após cada deploy.

## Regras de deploy

- nenhum segredo no GitHub;
- nenhuma versão paralela desnecessária;
- commits apenas em marcos funcionais/substanciais;
- produção só é promovida depois de validação do fluxo crítico;
- a Secretaria não aprova matrícula: apenas envia manualmente as credenciais pelo WhatsApp.

## Fluxo crítico que deverá sobreviver à migração

`pagamento aprovado → matrícula automática → Ouro → confirmação → credenciais pendentes → WhatsApp manual`

Quando a plataforma for efetivamente movida, o CI/CD será criado nesse mesmo repositório.
