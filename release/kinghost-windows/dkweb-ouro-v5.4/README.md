# Integração Ouro Moderno + DKWeb

Integra os dados presenciais preservados no MySQL DKOnline/DKWeb ao mesmo dashboard EAD, usando um único login da Ouro Moderno.

## Arquitetura

1. O aluno entra normalmente em `/area-do-aluno/` com as credenciais da Ouro.
2. O frontend envia o token já existente ao `portal-gateway?service=dkweb`.
3. `dkweb-student-portal` valida o token por uma RPC restrita a `service_role` e consulta a identidade atual diretamente na Ouro.
4. A função envia somente o identificador Ouro e o CPF ao bridge KingHost, entre servidores e com HMAC-SHA256.
5. O bridge procura um único cadastro presencial com o mesmo CPF e executa consultas somente de leitura.
6. O dashboard combina automaticamente EAD e presencial nas telas Visão geral, Meus cursos, Aulas e notas, Turma e horário e Financeiro.

O navegador nunca recebe senha MySQL, CPF, RG, endereço ou credenciais internas. O CPF não é armazenado pelo conector e nenhuma tabela é criada ou modificada no MySQL legado.

## Conteúdo

- `kinghost/www/dkweb-api/`: API PHP 7.3+ protegida por assinatura.
- `kinghost/www/App_Data/`: configuração privada e bloqueada pelo IIS.
- `supabase/functions/dkweb-student-portal/`: validação da sessão Ouro e proxy seguro.
- `supabase/functions/portal-gateway/`: gateway atual acrescido do serviço `dkweb`.
- `supabase/migrations/`: RPC interna que resolve a identidade Ouro sem expor CPF ao navegador.
- O frontend final fica diretamente em `assets/js/v360` no pacote V5.5 do Portal; não existe componente, rota ou aba DKWeb separada.

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

No pacote V5.5, `assets/js/v360/api.js` consulta EAD e presencial automaticamente depois do login. `pages.js` apresenta os dados por modalidade no mesmo dashboard, sem segundo login, nova aba ou menu "Histórico DKWeb".

## Compatibilidade e segurança

- PHP 7.3 ou superior com `mysqli`; não depende de `mysqlnd`.
- MySQL 5.5 preservado; a conexão solicita conversão para UTF-8.
- Consultas preparadas e limitadas.
- Consulta automática somente com CPF único e correspondência exata.
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
