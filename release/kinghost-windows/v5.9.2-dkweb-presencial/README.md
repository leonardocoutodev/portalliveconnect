# Live Connect Portal V5.9.2 — DKWeb Presencial White-label

## Correção de rota
- `https://liveconnect.com.br/dkweb/` permanece como **Portal do Aluno Presencial**.
- A rota não redireciona mais para `/area-do-aluno/`.
- `/area-do-aluno/` continua disponível para o portal unificado/EAD.

## Login presencial
- Usuário informa **matrícula**.
- Segundo campo solicita **ano de nascimento com 4 dígitos**.
- A rota `/dkweb/` força autenticação pelo fluxo presencial e não abre a sessão EAD.
- Depois do login, logout ou expiração, o aluno permanece na própria rota `/dkweb/`.

## White-label
- Nenhuma referência nominal ao fornecedor acadêmico foi reintroduzida no frontend.
- Integrações acadêmicas permanecem no backend.
- `/dkweb/` é mantido no robots.txt como área privada/não indexável.

## QA
- `api.js`, `pages.js` e `app.js` validados por sintaxe.
- ZIP validado por integridade.
- Confirmado: nenhum redirect de `/dkweb/` para `/area-do-aluno/`.
- Cache-bust: `v=592`.

## Deploy
Publicar manualmente na raiz atual da KingHost, substituindo os arquivos existentes.
