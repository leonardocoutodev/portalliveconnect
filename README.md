# Portal Live Connect

Portal institucional, comercial e acadêmico da Live Connect Escola de Profissões.

## Produção

- Site: https://portallc.netlify.app
- Backend: Supabase
- Integração acadêmica: Ouro Moderno
- Deploy: Netlify

## Versão atual

V3.4 — UI/UX Hardening

## Marco operacional — matrícula automática Ouro Moderno (31/08/2026)

O Portal Live Connect passou a criar matrículas diretamente pela integração autorizada com a Ouro Moderno.

Fluxo operacional:

1. ficha de matrícula no Portal;
2. pagamento aprovado;
3. aprovação e reserva de turma pela Secretaria;
4. identificação ou criação do aluno na Ouro Moderno;
5. resolução dos cursos Ouro pelo mapeamento acadêmico do Portal;
6. matrícula dos cursos na Ouro;
7. verificação independente dos cursos vinculados ao aluno;
8. ocupação definitiva da vaga da turma e confirmação da matrícula no Portal.

Controles incorporados:

- idempotência para evitar duplicidade de aluno e de cursos;
- registro do ID do aluno Ouro, IDs dos cursos e contratos;
- contador e horário das tentativas;
- registro sanitizado de erros e retornos;
- reprocessamento seguro pela Secretaria;
- fallback manual quando a integração não puder concluir;
- bloqueio quando o curso não possuir mapeamento Ouro confiável;
- auditoria de sucesso e falha sem persistir senha retornada pela API.

A credencial da Ouro permanece no Vault/Supabase e não é exposta ao navegador.

Este repositório foi preparado para versionar os pacotes de produção do Portal Live Connect e permitir deploy pelo Netlify conectado ao GitHub.
