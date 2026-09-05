# Live Connect Portal V5.9.2C — DKWeb sem carregamento infinito

## Correção
A rota `/dkweb/` deixa de depender do bootstrap completo do SPA público para exibir o Portal Presencial.

O novo entrypoint dedicado:
- renderiza o login presencial de forma independente;
- usa matrícula + ano de nascimento;
- aplica timeout de 10 s nas chamadas de login e resumo acadêmico;
- remove sessão presencial inválida/antiga automaticamente;
- nunca mantém spinner infinito: em falha, volta ao login com mensagem clara;
- possui watchdog de 12 s caso o módulo JavaScript nem chegue a iniciar;
- mantém cursos, notas/frequência, financeiro, materiais e certificados;
- permanece white-label.

## Deploy
Copiar `dkweb/` e `assets/` do hotfix para a raiz `www` da KingHost, sobrescrevendo os arquivos atuais.
