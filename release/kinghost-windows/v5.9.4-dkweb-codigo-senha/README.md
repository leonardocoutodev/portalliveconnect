# Live Connect Portal V5.9.4 — DKWeb Código + Senha

## Correção de autenticação
A versão V5.9.2C interpretava o identificador informado no login como matrícula e consultava `alunos.matricula`.

O DKWeb utiliza **Código do Aluno + Senha**. O bridge V5.9.4 passa a:
- resolver o código pelo campo `alunos.id_aluno`;
- preservar fallback por `matricula` para compatibilidade com acessos antigos;
- manter a validação da senha conforme o cadastro DKWeb sincronizado;
- preservar zeros à esquerda no código informado pelo aluno;
- não registrar nem persistir a senha.

## Frontend
- “Matrícula” foi substituído por **Código**.
- “Ano de nascimento” foi substituído por **Senha**.
- Mensagens de erro passam a usar “Código ou senha inválidos”.
- Cache-bust do entrypoint DKWeb: `v=594`.

## Arquivos do hotfix
- `dkweb-api/index.php`
- `assets/js/v360/dkweb-entry.js`
- `assets/js/v360/pages.js`
- `dkweb/index.html`
- `dkweb/index.htm`
- `dkweb/index.php`

## Deploy
Publicar manualmente na raiz `www` da KingHost, mantendo a estrutura de diretórios.

**Não substituir** `App_Data/dkweb-config.php`.

Após o deploy, validar o acesso presencial pelo código do aluno e sua senha.

## Rollback
Restaurar os seis arquivos da V5.9.2C. Este hotfix não altera o banco de dados.
