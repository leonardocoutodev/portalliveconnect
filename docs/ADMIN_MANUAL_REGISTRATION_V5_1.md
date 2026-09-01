# Admin V5.1 — Matrícula manual e documentos automáticos

## Fluxo restaurado

O Admin volta a ter **Nova matrícula / inscrição** como opção própria da Secretaria.

O mesmo fluxo atende:
- curso pago;
- curso gratuito;
- Projeto Jovem Aprendiz.

O aluno pode ser novo ou já existente. O backend reaproveita o cadastro pelo WhatsApp e restaura um cadastro soft-deleted quando necessário.

## Documentos

### Curso pago
Ao concluir:
- cria a matrícula;
- cria os lançamentos financeiros;
- aplica turma quando selecionada;
- gera um contrato preenchido e numerado;
- guarda snapshots dos dados pessoais e financeiros;
- permite abrir/imprimir o contrato pelo Admin.

### Curso gratuito
Ao concluir:
- cria a matrícula;
- gera automaticamente a ficha de inscrição;
- permite imprimir a ficha;
- a ficha continua vinculada à matrícula.

### Jovem Aprendiz
Ao concluir:
- cria/atualiza o cadastro;
- cria o interesse Jovem Aprendiz;
- gera a ficha específica do projeto;
- permite abrir/imprimir imediatamente.

## Multifomação

Ao adicionar outro curso pelo Cadastro 360°, o Admin usa o mesmo backend e também gera o documento correspondente.

## Permissões

A função usa a permissão operacional `is_admin_comercial()`.
Leonardo Couto e Monique Gomes foram validados com acesso ao fluxo.

## QA

Testes transacionais sem persistir dados:
- curso pago -> contrato gerado;
- curso gratuito -> ficha gerada;
- Jovem Aprendiz -> ficha gerada;
- contrato recuperado por RPC com curso e vencimento preenchidos;
- acesso de Monique validado no curso gratuito.
