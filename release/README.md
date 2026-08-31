# Pacote de produção

O deploy do frontend usa um pacote ZIP na raiz desta pasta com o nome:

`portal.zip`

O `netlify.toml` descompacta esse arquivo para `dist/` durante o build.

## Versão de referência

**V4.1 — Editor 360° do aluno + múltiplos cursos**

A V4.1 inclui:
- edição completa dos dados úteis do aluno;
- edição do curso já vinculado;
- vários cursos ativos simultaneamente no mesmo aluno;
- troca de curso sem afetar os demais vínculos;
- edição individual de turma, horário, vencimento, valores, pagamentos, modalidade comercial e observações;
- encerramento/restauração de curso preservando histórico;
- atualização automática das fichas de curso gratuito;
- acesso ao editor por **Alunos e matrículas**, **Leads / funil** e **Jovem Aprendiz**;
- ficha do Projeto Jovem Aprendiz da V4.0 preservada.

O pacote local de release deve ser publicado como `release/portal.zip` antes do deploy do frontend.
