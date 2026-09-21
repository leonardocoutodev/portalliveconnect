# Admin Live Connect V5.12.2 — Presencial / EAD + Ouro Moderno

Base: V5.12.1.

## Nova matrícula

A entrada de matrícula agora possui quatro fluxos independentes:

- **Matrícula paga • Presencial**
- **Matrícula paga • EAD**
- **Matrícula gratuita**
- **Jovem Aprendiz**

### Presencial

- usa `admin_manual_paid_registration_create`;
- mantém turma, horário, condições financeiras e contrato;
- não provisiona conta no Ouro.

### EAD

- usa `admin_manual_paid_ead_registration_create`;
- o novo RPC aceita apenas cursos ativos do tipo `pago`;
- o frontend consulta `school_secretary_ouro_catalog_audit` e mostra apenas formações com todos os módulos mapeados;
- exige os dados necessários ao Ouro: e-mail, nascimento, RG, CPF, CEP e endereço completo;
- o provisionamento continua sendo executado pelo fluxo existente `admin_manual_ead_direct_enrollment`;
- depois do provisionamento o Admin consulta `school_secretary_prepare_first_access`;
- para uma conta recém-criada, a tela de sucesso mostra usuário, senha inicial, ID Ouro e contrato, além de botões para copiar as credenciais;
- se a conta Ouro já existia, a senha atual não é recuperada: o Admin mostra o usuário e a orientação de acesso/recuperação de senha.

A senha inicial é mantida criptografada no backend e é temporária; a rotina existente de expiração elimina o segredo após 72 horas.

## Backend

Migration aplicada em produção:

`20260921204915_split_admin_paid_ead_registration`

Validação realizada sem criar aluno externo de teste:

- curso gratuito no RPC EAD => `course_not_paid`;
- curso pago com payload incompleto => alcança o validador EAD e retorna `Nome completo é obrigatório`;
- `authenticated` possui EXECUTE;
- `anon` não possui EXECUTE.

## Frontend

Cache-bust: `5122`.

O pacote completo V5.12.2 foi construído a partir do V5.12.1 fornecido pelo proprietário. O ZIP inclui o patch:

`release-notes/admin-v5122-presential-ead-ouro.patch`

Não fazer deploy parcial dos Static Assets.
