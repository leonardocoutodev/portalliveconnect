# Admin Live Connect V5.12.0 — matrículas separadas

## Alteração

A tela **Nova matrícula** deixa de usar um formulário híbrido para curso pago e gratuito.

Agora existem três fluxos independentes:

1. **Matrícula paga**
   - lista apenas cursos pagos;
   - mantém turma, vencimento e condições financeiras;
   - chama `admin_manual_paid_registration_create`;
   - gera contrato.

2. **Matrícula gratuita**
   - lista apenas cursos gratuitos;
   - não exibe condições financeiras;
   - chama `admin_manual_free_registration_create`;
   - gera ficha de inscrição gratuita.

3. **Jovem Aprendiz**
   - permanece independente;
   - continua usando o fluxo específico já existente.

O botão **Nova matrícula** na lista de alunos leva primeiro à escolha do fluxo.

## Backend

A migration de separação dos RPCs já está aplicada em produção:

`20260921202532_split_admin_manual_free_paid_registration`

Os RPCs rejeitam cursos do tipo incorreto e não possuem EXECUTE para `anon`.

## Frontend

Base: pacote completo V5.11.9 fornecido pelo proprietário.

Cache-bust: `5120`.

O pacote completo V5.12.0 contém também o patch de comparação em:

`release-notes/admin-v5120-split-registration.patch`

## Deploy

Publicar o pacote **completo** V5.12.0 no mesmo Worker/Static Assets do Admin. Não publicar arquivos isolados como substituição integral.
