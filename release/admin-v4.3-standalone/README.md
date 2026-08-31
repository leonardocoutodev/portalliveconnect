# Admin Live Connect V4.3 — Standalone

Destino oficial: `https://admin.liveconnectios.workers.dev/`.

Esta versão corrige o pacote V4.2 separado que ainda dependia de partes do Portal.

## Correções

- Admin inicializa por uma entrypoint própria, sem `pages.js` ou roteamento do Portal.
- Perfis administrativos reconhecidos: Leonardo Couto e Monique Gomes.
- `coadmin` é aceito no frontend e recebe o mesmo acesso efetivo definido pelo backend.
- Editor visual de matrícula preservado.
- Cadastro 360° preservado.
- JSON não faz parte do fluxo normal de edição.
- Tela de erro/retry explícita caso a autenticação ou o backend falhem.
- CSS standalone força largura/viewport corretos e melhora o modal visual.

## QA

- Backend testado como Leonardo: 662 leads, 18 matrículas, 69 cursos e Editor 360° acessível.
- Backend testado como Monique: os mesmos 662 leads, 18 matrículas, 69 cursos e Editor 360° acessível.
- Todos os JS do pacote passam em `node --check`.
- Nenhuma referência estática obrigatória está ausente.
- O runtime entregue não contém o texto/fluxo antigo de editor JSON.
