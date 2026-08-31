# V4.2 — Editor visual de matrícula

A tela genérica **Editor avançado / enrollments** com edição manual em JSON não deve ser usada no fluxo operacional.

## Editor visual

A edição de matrícula usa a RPC `admin_student_editor_get` para carregar dados legíveis e `admin_student_update_enrollment` para salvar.

Nenhum identificador técnico precisa ser digitado. O usuário escolhe cursos e turmas pelo nome.

Campos visuais:
- curso;
- turma;
- vencimento;
- data de início;
- horário;
- método de pagamento;
- status financeiro;
- matrícula;
- primeira mensalidade;
- mensalidade;
- modalidade comercial;
- parcelas;
- valor total;
- observações.

## UX

O modal usa o componente padrão `openModal` do portal, em tamanho grande e responsivo.

Ações disponíveis:
- Salvar alterações;
- Encerrar curso / Restaurar curso;
- Abrir cadastro completo.

Em **Secretaria > Alunos e matrículas**, cada linha passa a ter **Editar matrícula** e **Cadastro completo**.

## Segurança e consistência

A UI não expõe `lead_id`, `course_id`, `pricing_version_id` ou JSON para edição manual.

Troca de curso continua sendo validada no backend e recalcula valores vigentes. O sistema impede o mesmo curso ativo duplicado para o mesmo aluno.
