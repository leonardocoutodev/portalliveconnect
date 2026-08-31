# V4.1 — Cadastro 360° do aluno e múltiplos cursos

## Objetivo

Permitir corrigir praticamente qualquer dado operacional do aluno e gerenciar mais de um curso no mesmo cadastro, mantendo histórico e consistência entre CRM, matrículas, financeiro e fichas.

## Dados editáveis do aluno

- nome;
- WhatsApp;
- e-mail;
- nascimento e idade;
- RG e CPF;
- CEP, endereço e bairro;
- responsável, WhatsApp, nascimento, RG e CPF do responsável;
- situação de trabalho e estudo;
- objetivo profissional;
- status no CRM;
- score;
- arquivamento;
- origem, campanha, landing page, referrer e UTMs;
- situação escolar e turno do Jovem Aprendiz quando houver ficha vinculada.

IDs internos, timestamps técnicos e o indicador de menoridade não são editados manualmente. O indicador de menoridade continua calculado pelo banco a partir da idade.

## Cursos do aluno

Um mesmo lead/aluno pode possuir vários enrollments ativos, desde que sejam cursos diferentes.

Cada vínculo permite editar:
- curso;
- turma;
- dia/horário;
- data de início;
- vencimento;
- método de pagamento;
- situação da matrícula;
- situação da primeira mensalidade;
- valor da matrícula;
- primeira mensalidade;
- mensalidade;
- modalidade comercial;
- quantidade de parcelas;
- valor total;
- observações.

Também é possível:
- adicionar outro curso;
- trocar o curso atual;
- encerrar apenas um vínculo;
- restaurar um curso encerrado.

Existe índice único parcial que impede somente duplicar o mesmo curso ativo para o mesmo aluno.

## Consistência financeira

Quando o curso é trocado:
- o novo tipo e a precificação vigente são recalculados;
- os lançamentos de matrícula e primeira mensalidade são sincronizados;
- pagamentos já confirmados por provedor permanecem históricos;
- valores editados manualmente sincronizam os lançamentos internos que ainda não possuem pagamento externo confirmado.

## Fichas

A ficha de curso gratuito acompanha alterações do aluno e da matrícula. Ao trocar uma matrícula de gratuito para pago, a ficha gratuita antiga é removida daquele enrollment. Ao trocar de volta para um curso gratuito, a ficha correspondente é recriada/atualizada.

A ficha do Jovem Aprendiz também recebe as correções dos dados cadastrais do participante.

## Acesso no admin

O botão **Editar tudo** está disponível em:
- Secretaria > Alunos e matrículas;
- Comercial > Leads / funil;
- Comercial > Jovem Aprendiz.

## QA executado

- aluno fictício criado;
- dois cursos gratuitos ativos simultaneamente;
- um curso trocado sem afetar o segundo;
- terceiro curso pago adicionado;
- snapshots financeiros editados;
- lançamentos internos sincronizados;
- proteção contra curso ativo duplicado validada;
- ficha gratuita removida ao converter enrollment para pago;
- dados pessoais editados;
- todos os registros fictícios removidos após o teste;
- JavaScript V360 validado com `node --check`.
