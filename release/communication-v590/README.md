# Live Connect V5.9.0 — Lico + Mensageiro Global

## Problemas corrigidos
- O pacote V5.8.1 tinha o módulo do mensageiro, mas o carregamento/caching do Admin não estava confiável no deploy manual. A V5.9.0 usa cache-bust novo e bootstrap redundante.
- O Lico não reutiliza mais indefinidamente uma sessão antiga. Sessões expiram por inatividade e são encerradas.
- A memória do contato é separada da sessão, permitindo iniciar uma conversa nova sem perder informações úteis.
- “Reiniciar atendimento”, “novo atendimento” e o botão ↻ iniciam sessão nova.
- A interface pública não mostra “Qualificação e matrícula”.
- O mascote acompanha o launcher e fica atrás da janela aberta.

## Lico
- Idle padrão: 30 minutos, configurável em `lico_runtime_settings`.
- Memória persistente por `visitor_key` no mesmo navegador.
- Uma nova sessão pede confirmação antes de reaproveitar os dados anteriores.
- O Lico grava eventos estruturados de aprendizado (curso escolhido, objeções, handoff e resultados).
- O ranking de cursos pagos pode ganhar peso progressivo conforme seleções e resultados reais, sem alterar fatos do catálogo.
- Informações factuais sobre cursos continuam vindo do catálogo/banco; o aprendizado não reescreve descrições ou preços.

## Chat da equipe
- O mensageiro é global e fica fora do conteúdo das páginas do Admin.
- Abre automaticamente ao detectar nova mensagem.
- Canais públicos: Geral, Comercial, Secretaria e Diretoria.
- Conversas privadas: Comercial ↔ Secretaria, Comercial ↔ Diretoria e Secretaria ↔ Diretoria.
- O proprietário aparece como Comercial no chat.
- O proprietário tem leitura de todos os tópicos privados; no tópico Secretaria ↔ Diretoria o acesso é somente leitura.
- Essa capacidade de supervisão não é apresentada na interface dos demais participantes.

## Deploy manual
1. Admin completo V5.9.0 → Cloudflare.
2. Portal V5.9.0 → KingHost.
3. Backend já aplicado no Supabase Live Connect Comercial.

Não reutilizar os pacotes V5.8.x após esta versão.
