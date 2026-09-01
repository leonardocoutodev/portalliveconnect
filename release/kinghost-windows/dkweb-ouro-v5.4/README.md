# Integração Ouro Moderno + DKWeb

Recupera os dados históricos preservados no MySQL DKWeb usando o mesmo login da Ouro Moderno.

## Arquitetura

1. O aluno entra normalmente em `/area-do-aluno/` com as credenciais da Ouro.
2. O frontend envia o token já existente ao `portal-gateway?service=dkweb`.
3. `dkweb-student-portal` valida o token por uma RPC restrita a `service_role` e consulta a identidade atual diretamente na Ouro.
4. A função envia somente o identificador Ouro e o CPF ao bridge KingHost, entre servidores e com HMAC-SHA256.
5. O bridge associa Ouro e DKWeb por CPF apenas na primeira vez e grava somente o hash do identificador Ouro.
6. As consultas seguintes usam o vínculo persistido e devolvem apenas dados do próprio aluno.

O navegador nunca recebe senha MySQL, CPF, RG, endereço ou credenciais internas. O CPF não é armazenado no Supabase nem na tabela de vínculo.

## Conteúdo

- `kinghost/www/dkweb-api/`: API PHP 7.3+ protegida por assinatura.
- `kinghost/www/App_Data/`: configuração privada e bloqueada pelo IIS.
- `supabase/functions/dkweb-student-portal/`: validação da sessão Ouro e proxy seguro.
- `supabase/functions/portal-gateway/`: gateway atual acrescido do serviço `dkweb`.
- `supabase/migrations/`: RPC interna que resolve a identidade Ouro sem expor CPF ao navegador.
- `frontend/`: painel responsivo sem framework e sem HTML inseguro.

## Implantação segura

### 1. KingHost

Envie as pastas `dkweb-api` e `App_Data` para a raiz `www`.

Copie `App_Data/dkweb-config.example.php` para `App_Data/dkweb-config.php` e preencha no servidor:

- senha atual do MySQL `liveconnect`;
- um segredo aleatório com no mínimo 32 caracteres.

Não publique `dkweb-config.php` no GitHub e não envie seu conteúdo por chat.

### 2. Supabase

Primeiro aplique a migration `20260901_portal_student_dkweb_identity.sql`. Ela revoga acesso de `anon` e `authenticated` e concede execução apenas a `service_role`.

Cadastre os segredos:

- `DKWEB_BRIDGE_URL=https://www.liveconnect.com.br/dkweb-api/`
- `DKWEB_BRIDGE_SECRET=<o mesmo segredo configurado na KingHost>`

Implante `dkweb-student-portal` com `verify_jwt=false`. Essa exceção é necessária porque a função recebe o token aleatório de sessão próprio da Ouro; o código calcula o hash e valida a sessão por uma RPC que somente `service_role` pode executar antes de consultar qualquer dado.

Depois implante a versão atualizada de `portal-gateway`.

### 3. Frontend

Carregue:

```html
<link rel="stylesheet" href="/assets/css/dkweb-panel.css">
<script src="/assets/js/dkweb-panel.js"></script>
```

Após o login Ouro já ter produzido o token da sessão:

```js
LiveConnectDKWeb.mount({
  target: "#dkwebHistory",
  token: ouroSessionToken,
  gatewayUrl: CONFIG.apiBase + "/portal-gateway"
});
```

No pacote derivado V5.4, a integração já foi encaixada diretamente em `assets/js/v360/api.js`, `config.js` e `pages.js`: o menu **Histórico DKWeb** reutiliza `lc_student_session_v3`, carrega o histórico somente quando solicitado e preserva todas as correções da V5.3. Os arquivos independentes desta pasta permanecem como componente de referência/fallback.

## Compatibilidade e segurança

- PHP 7.3 ou superior com `mysqli` e `mysqlnd`.
- MySQL 5.5 preservado; a conexão solicita conversão para UTF-8.
- Consultas preparadas e limitadas.
- Vínculo automático somente com CPF único.
- CPF ausente ou duplicado exige associação manual futura pela Secretaria.
- Configuração privada protegida por `App_Data` e `web.config`.
- Requisições com HMAC e validade de 120 segundos.
- Respostas sem cache e sem detalhes internos de erro.

## Validação antes de produção

1. Confirmar que `/App_Data/dkweb-config.php` retorna 404/403 quando acessado pelo navegador.
2. Confirmar que `GET /dkweb-api/` retorna 405.
3. Confirmar que POST sem assinatura retorna 401.
4. Testar login Ouro de um aluno cujo CPF exista uma única vez no DKWeb.
5. Conferir cursos, módulos, notas, frequência e financeiro desse aluno.
6. Testar um aluno sem CPF correspondente e confirmar que nenhum dado de terceiro é exibido.
