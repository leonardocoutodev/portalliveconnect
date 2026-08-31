# Pessoas e acessos administrativos

## Regra atual

- Os dois perfis administrativos principais possuem os mesmos privilégios efetivos nas áreas da Live Connect.
- O perfil principal é identificado internamente por `private.system_owner`.
- O perfil principal é imutável quanto a nível e estado: não pode ser excluído, desativado ou rebaixado.
- A segunda pessoa administrativa pode operar as mesmas áreas e executar as mesmas ações, inclusive operações estruturais e exclusões permitidas ao nível administrativo.
- A proteção do perfil principal é aplicada no banco por trigger e não depende do frontend.

## Frontend

- Perfis são identificados pelo nome da pessoa.
- Não exibir nomes de papéis como Master, Coadmin, Proprietário ou equivalentes.
- A seção de acesso mostra apenas pessoa, status, último acesso e ação.
- A antiga fila de aprovações não faz parte do fluxo atual.

## Backend

A distinção técnica `master_admin` / `coadmin` permanece apenas para identificar o perfil principal de forma segura, mas `is_master_admin()` considera ambos para autorização funcional.

A tabela privada `system_owner` e o trigger `protect_owner_profile` garantem que o perfil principal não possa ser removido, desativado ou rebaixado.
