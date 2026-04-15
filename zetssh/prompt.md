\[Persona]
Atue como um Principal Software Engineer especialista em macOS nativo, Swift, SwiftUI, AppKit, segurança de aplicações desktop, arquitetura de software, UX nativa Apple, protocolos de rede e clientes SSH de nível profissional.

\[Missão]
Crie um plano de desenvolvimento completo para um cliente SSH nativo para macOS chamado **ZetSSH**, construído em Swift, com foco em arquitetura robusta, segurança forte, experiência de usuário nativa do ecossistema Apple e base sólida para evolução futura.

\[Objetivo do Produto]
O **ZetSSH** será um cliente SSH nativo para macOS com interface gráfica, inspirado em ferramentas como Termius, Royal TS, SecureCRT e fluxos de uso de terminais modernos, mas com UX e UI alinhadas ao padrão visual do macOS.

O sistema deve permitir:

- conexão SSH por interface gráfica;
- gerenciamento de múltiplas sessões;
- armazenamento persistente das sessões;
- armazenamento seguro de credenciais;
- suporte a autenticação por senha e por chave;
- experiência visual e comportamental nativa do macOS;
- base técnica preparada para expansão futura.

\[Importante: correção de requisito]
Não trate “salvar senha criptografada no SQLite” como solução ideal de segurança.
Considere a abordagem correta para macOS:

- metadados e configurações podem ficar no SQLite;
- segredos devem ser protegidos com criptografia forte;
- a chave de proteção dos segredos deve ser armazenada de forma segura no ecossistema Apple, preferencialmente usando Keychain e, quando fizer sentido, Secure Enclave;
- o SQLite pode armazenar apenas o ciphertext, referências, metadados e configurações, nunca a senha em texto puro.

\[Escopo Funcional Esperado]
O plano deve considerar, no mínimo:

1. Conectividade e protocolos do ecossistema SSH

- SSH2
- SFTP
- SCP
- execução remota de comandos
- terminal interativo
- tunelamento local, remoto e dinâmico
- jump host / bastion host
- suporte futuro para múltiplas abas e múltiplas conexões simultâneas

1. Autenticação

- usuário e senha
- chave privada
- chaves protegidas por passphrase
- suporte a formatos modernos de chave
- keyboard-interactive
- agent forwarding
- known\_hosts
- validação de fingerprint do host
- política para host desconhecido, host alterado e rotação de chaves

1. Gestão de sessões

- CRUD completo de sessões
- agrupamento por pastas/tags/ambientes
- favoritos
- histórico de conexões
- busca rápida
- duplicação de sessão
- importação/exportação de sessões

1. Experiência de terminal

- emulação de terminal
- copy/paste correto
- suporte a resize
- scrollback
- ANSI colors
- atalhos de teclado nativos
- comportamento consistente com apps do macOS
- suporte futuro a split panes e tabs

1. Persistência

- SQLite para sessões, preferências, histórico, hosts conhecidos, organização e cache
- estratégia de versionamento de schema
- migrações
- separação clara entre dados sensíveis e não sensíveis

1. Segurança

- threat model do app
- criptografia em repouso
- uso de Keychain
- política para desbloqueio de segredos
- proteção contra vazamento de credenciais em logs
- proteção contra downgrade de algoritmo
- validação de host keys
- armazenamento seguro de chaves privadas importadas
- estratégia para auditoria de eventos sensíveis sem expor segredo

1. UX/UI nativa macOS

- aparência alinhada ao Human Interface Guidelines da Apple
- SwiftUI como base, com uso de AppKit quando necessário
- sidebar, search, toolbar, sheets, settings, menu bar e atalhos coerentes com apps nativos
- dark mode
- acessibilidade
- feedback claro de erro, conexão, autenticação e segurança
- fluxo intuitivo para primeira conexão
- UX profissional, limpa e “parecendo Mac”, não um app multiplataforma com cara genérica

\[Restrições de Engenharia]

- O app deve ser nativo macOS, não Electron, não webview-first, não cross-platform como prioridade.
- A análise deve considerar SwiftUI + AppKit quando necessário.
- O plano deve avaliar opções reais para implementar SSH em Swift/macOS:
  - biblioteca SSH em Swift puro, se viável;
  - wrapper de libssh2/libssh;
  - integração com componentes maduros;
  - trade-offs entre performance, manutenção, compatibilidade, segurança e esforço de desenvolvimento.
- Não assuma decisões sem justificar tecnicamente.

\[O que eu quero na resposta]
Quero um plano de desenvolvimento de nível sênior/principal para o **ZetSSH**, estruturado e profundo, cobrindo:

1. Visão geral do produto
2. Escopo do MVP
3. Escopo pós-MVP
4. Requisitos funcionais
5. Requisitos não funcionais
6. Arquitetura proposta
7. Módulos e camadas do sistema
8. Proposta de stack técnica
9. Estratégia de segurança
10. Estratégia de persistência e modelagem dos dados
11. Fluxos principais de UX
12. Principais riscos técnicos
13. Decisões arquiteturais com trade-offs
14. Roadmap por fases
15. Estratégia de testes
16. Estratégia de distribuição no macOS
17. Observabilidade, logs e diagnóstico
18. Backlog inicial priorizado
19. Sugestão de estrutura de pastas/projetos
20. Critérios de aceite do MVP

\[Formato obrigatório da resposta]
A resposta deve:

- ser em português do Brasil;
- ser extremamente objetiva, técnica e detalhada;
- evitar generalidades;
- justificar escolhas;
- mostrar alternativas quando houver decisão importante;
- separar claramente o que entra no MVP e o que deve ficar para versões futuras;
- incluir diagramas textuais simples quando útil;
- incluir tabela de trade-offs quando necessário;
- incluir backlog inicial com prioridades.

\[Exigência adicional]
Ao falar de “todos os protocolos”, interprete corretamente como “todos os principais protocolos, fluxos e capacidades esperadas de um cliente SSH profissional no ecossistema SSH”, e não literalmente todos os protocolos de rede existentes.

\[Contexto de identidade do produto]
Considere que o nome do produto é **ZetSSH**. Ao descrever arquitetura, UX, módulos e roadmap, trate o nome como o nome oficial do aplicativo. Quando fizer sugestões de identidade do produto, onboarding, nomenclatura de menus ou estrutura de funcionalidades, mantenha coerência com um app técnico, profissional e nativo do macOS.

\[Saída final esperada]
No final, entregue:

1. uma arquitetura recomendada;
2. um roadmap em fases;
3. um backlog inicial priorizado;
4. uma proposta de modelo de dados;
5. uma lista dos maiores riscos técnicos;
6. uma recomendação explícita de quais partes devem usar SQLite e quais devem usar Keychain.s

