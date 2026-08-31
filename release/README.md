# Pacote de produção

O deploy do frontend usa um pacote ZIP na raiz desta pasta com o nome:

`portal.zip`

O `netlify.toml` descompacta esse arquivo para `dist/` durante o build.

## Versão de referência

**V4.2 — Editor visual de matrícula**

A V4.2 substitui a edição bruta de `enrollments` em JSON por um editor visual.

O modal apresenta:
- aluno e curso atual;
- curso por nome, sem editar UUID;
- turma;
- vencimento;
- data de início;
- horário / agenda;
- método de pagamento;
- situação da matrícula;
- situação da primeira mensalidade;
- valor de matrícula;
- primeira mensalidade;
- mensalidade;
- modalidade comercial;
- parcelas;
- total do curso;
- observações;
- encerrar/restaurar curso;
- atalho para o Cadastro 360° completo.

IDs técnicos e JSON deixam de fazer parte do fluxo normal do admin.

A V4.2 preserva:
- múltiplos cursos por aluno;
- troca de curso com recálculo financeiro;
- Editor 360°;
- ficha Jovem Aprendiz;
- fichas de cursos gratuitos;
- integrações existentes.

O pacote local de release deve ser publicado como `release/portal.zip` antes do deploy do frontend.
