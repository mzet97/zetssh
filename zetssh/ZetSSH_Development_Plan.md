# Plano de Desenvolvimento: ZetSSH

Este documento detalha a arquitetura, o escopo e o roadmap para o desenvolvimento do **ZetSSH**, um cliente SSH nativo para macOS focado em segurança, performance e experiência do usuário profissional.

## 1. Visão Geral do Produto
O **ZetSSH** é um cliente SSH de nível profissional, nativo para macOS, desenhado com foco na experiência de uso (UX/UI) alinhada ao *Human Interface Guidelines* da Apple. Diferenciando-se de alternativas baseadas em Electron ou webviews, o ZetSSH proporciona baixo consumo de recursos, inicialização instantânea e forte integração com as tecnologias de segurança do ecossistema Apple (Keychain, Secure Enclave). O objetivo é atender usuários técnicos avançados que necessitam gerenciar dezenas ou centenas de sessões SSH com segurança robusta e um fluxo de trabalho eficiente.

## 2. Escopo do MVP
O Produto Mínimo Viável (MVP) entregará o núcleo essencial para o dia a dia de conexões remotas:
- Interface gráfica (GUI) nativa em SwiftUI com suporte completo ao Dark Mode.
- Criação, edição, exclusão e leitura (CRUD) de sessões e pastas para organização.
- Emulação de terminal interativo com suporte a cores ANSI, *scrollback*, *copy/paste* nativo e redimensionamento dinâmico.
- Conectividade SSH2 básica e autenticação por usuário/senha e chaves privadas (sem passphrase no MVP).
- Armazenamento persistente: metadados no SQLite e senhas protegidas no Keychain.
- Verificação básica de *host keys* (conhecidos vs. desconhecidos).

## 3. Escopo pós-MVP
O produto evoluirá para uma ferramenta completa de administração de infraestrutura:
- **Conectividade:** Interface gráfica para SFTP e SCP, tunelamento local/remoto/dinâmico, suporte nativo a *Jump/Bastion Hosts*.
- **UX/Terminal:** Múltiplas abas, *split panes* (divisão de tela), snippets de comandos rápidos, atalhos globais configuráveis.
- **Autenticação Avançada:** Suporte a chaves protegidas por *passphrase*, *agent forwarding*, importação e gestão de formatos modernos de chave (Ed25519, ECDSA) via Secure Enclave, políticas avançadas de rotação e *StrictHostKeyChecking*.
- **Gestão:** Sincronização via iCloud, busca avançada em todo o texto do *scrollback*, tags e ambientes customizados.

## 4. Requisitos Funcionais
- **RF01:** O sistema deve gerenciar o ciclo de vida de múltiplas sessões SSH, organizadas hierarquicamente em pastas.
- **RF02:** O sistema deve estabelecer e manter conexões remotas seguras via SSH2, suportando execução de comandos e shell interativo.
- **RF03:** O sistema deve autenticar conexões usando senhas ou chaves SSH (fornecidas pelo usuário ou via integração com *ssh-agent* local futuramente).
- **RF04:** O sistema deve emular um terminal VT100/xterm, renderizando adequadamente interfaces baseadas em texto (ex: `vim`, `top`, `htop`).
- **RF05:** O sistema deve alertar proativamente sobre *fingerprints* de hosts desconhecidos ou alterados, bloqueando a conexão em caso de mudança inesperada.
- **RF06:** O sistema deve permitir a duplicação rápida e exportação/importação (apenas metadados) de sessões.

## 5. Requisitos Não Funcionais
- **RNF01 (Segurança):** O sistema não deve, sob nenhuma circunstância, gravar credenciais ou chaves privadas em banco de dados SQLite ou em texto puro; todo material sensível deve ser guardado no Keychain.
- **RNF02 (Desempenho):** O tempo de renderização do terminal deve manter 60 FPS durante a execução de comandos com alta saída de texto (ex: `tail -f`).
- **RNF03 (Arquitetura):** O projeto deve utilizar a linguagem Swift e frameworks nativos da Apple, rejeitando ativamente soluções *cross-platform* para o *frontend*.
- **RNF04 (Usabilidade):** O sistema deve seguir o *look and feel* padrão do macOS (menus, atalhos, barra de ferramentas, *sidebar* translúcida).

## 6. Arquitetura Proposta
A arquitetura seguirá os princípios da **Clean Architecture**, combinando padrões MVVM (Model-View-ViewModel) para a interface do usuário e o padrão Coordinator/Router para o fluxo de navegação. 

- **Camada de Apresentação (App/UI):** SwiftUI para toda a estrutura de listas, formulários e preferências. Uso de `NSViewRepresentable` para integrar componentes complexos do AppKit (como o emulador de terminal).
- **Camada de Domínio:** Casos de uso (Ex: `ConnectToSessionUseCase`, `ValidateHostKeyUseCase`) e Entidades puras Swift, totalmente independentes de bibliotecas de terceiros ou detalhes de UI.
- **Camada de Dados (Repositórios):** Interfaces abstratas para persistência. 
- **Camada de Infraestrutura:** Implementações concretas (SQLite via GRDB, Apple Security Framework para Keychain, e o motor SSH via C-Interop).

## 7. Módulos e Camadas do Sistema
- **Core SSH Module:** O "motor" responsável pela negociação de protocolos, canais e *streams* de dados. Encapsula o acesso a uma biblioteca base (ex: *libssh2*).
- **Terminal Rendering Module:** Lida com o parsing das sequências de escape ANSI e a renderização do texto na tela.
- **Security & Crypto Module:** Wrapper seguro ao redor do Keychain Services API para gestão do ciclo de vida das senhas e validação criptográfica de *host keys*.
- **Session Management Module:** Lógica de negócios de organização, busca (Search) e histórico.
- **UI & Navigation Module:** Componentes visuais (Sidebar, Detail Views, Settings) e *bindings* de estado em SwiftUI.

## 8. Proposta de Stack Técnica
- **Linguagem Principal:** Swift 5.9+ (com Swift Concurrency / async-await).
- **Interface:** SwiftUI como framework primário; AppKit quando necessário para *performance* de terminal e manipulação avançada de janelas.
- **Persistência Relacional:** `GRDB.swift` (Excelente suporte a concorrência, migrações seguras e mapeamento ORM robusto para SQLite).
- **Gestão de Segredos:** Framework nativo `Security` (Keychain Services).
- **Emulação de Terminal:** `SwiftTerm` (Biblioteca madura em Swift para emulação de terminais XTerm/VT100, integrável via AppKit).
- **Motor SSH:** Integração via C-Interop com a `libssh2`. (Justificativa: *libssh2* é altamente testada para casos de uso clientes completos, incluindo SFTP e túneis. Alternativas como *SwiftNIO SSH* são excelentes, mas demandariam muito mais esforço para recriar funcionalidades focadas em *client* interativo e transferência de arquivos).

## 9. Estratégia de Segurança
- **Threat Model:** Mitigação primária focada no roubo de credenciais locais e ataques Man-in-the-Middle (MITM).
- **Proteção em Repouso:** Todo segredo (senha de host, passphrase de chave privada) deve ser gravado no Keychain com atributo `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **Validação de Host:** Implementação estrita de *known_hosts*. Alertas modais bloqueantes em caso de alteração de fingerprint.
- **Logs Sanitizados:** Uso do `OSLog`. O sistema de logs interceptará variáveis, ocultando automaticamente campos sensíveis.

## 10. Estratégia de Persistência e Modelagem dos Dados
- **SQLite (GRDB):**
  - Tabela `Session`: `id` (UUID), `name`, `host`, `port`, `username`, `folder_id`, `created_at`, `updated_at`, `theme_config`.
  - Tabela `Folder`: `id` (UUID), `name`, `parent_id`, `icon`.
  - Tabela `KnownHost`: `host`, `algorithm`, `public_key_fingerprint`, `last_seen`.
  - Migrações (Database Schema Versioning) nativas do GRDB.
- **Keychain:**
  - `Service`: `com.zetssh.credentials`
  - `Account`: `session_id` (O UUID da sessão no SQLite)
  - `Data`: A senha real ou passphrase (texto puro ou *Data* protegido pelo sistema).

## 11. Fluxos Principais de UX
- **Zero State & Onboarding:** Uma tela principal elegante contendo um *call-to-action* claro ("Adicionar Nova Conexão" / "Importar do ~/.ssh/config").
- **Criação/Edição:** Um *Sheet* (modal) organizado em abas: "Geral" (Host, Porta), "Credenciais" (Usuário, Senha/Chave) e "Avançado" (Opções de Terminal).
- **Conexão:** Seleção na *Sidebar* -> O painel de detalhe muda para estado de "Conectando..." com feedback de progresso -> Transição fluida para a visualização do Terminal.
- **Gestão de Exceções:** Em caso de falha de *fingerprint*, a tela de detalhe não abre o terminal; exibe um painel de alerta crítico explicando a ameaça e exigindo ação manual (Aceitar e Salvar vs. Abortar).

## 12. Principais Riscos Técnicos
1. **Performance do Terminal:** Emuladores de terminal nativos exigem alta otimização de renderização de texto. O uso de bibliotecas de terceiros (`SwiftTerm`) mitiga o risco, mas pode limitar customizações futuras pesadas de UI (como split panes muito dinâmicos).
2. **Concorrência e libssh2:** Bibliotecas C não são nativamente seguras em threads Swift. O *wrapper* deverá isolar as chamadas à libssh2 usando *Actors* ou *Serial Dispatch Queues* para evitar *crashes*.
3. **Ciclo de Vida do App (App Nap / Sleep):** Lidar de maneira graciosa com interrupções de rede quando o Mac entra em modo de repouso ou troca de Wi-Fi, evitando travamentos da interface (o *socket* C bloqueando a thread principal).

## 13. Decisões Arquiteturais com Trade-offs

| Decisão | Opção Escolhida | Alternativa Rejeitada | Justificativa |
|---|---|---|---|
| **Motor Protocolo SSH** | `libssh2` via C-Interop | `SwiftNIO SSH` | *libssh2* possui suporte amplo a túneis, SFTP, Agent Forwarding e teclado interativo, cruciais para um *client*. SwiftNIO foca em alta performance assíncrona, sendo ideal para *servers*, mas demandaria reconstruir a roda no frontend. |
| **Framework de UI** | SwiftUI + AppKit | Apenas AppKit | SwiftUI reduzirá o tempo de desenvolvimento das telas de CRUD, configurações e *sidebar* em mais de 60%. O AppKit será restrito apenas ao emulador do terminal via `NSViewRepresentable`. |
| **Armazenamento Local** | SQLite via GRDB | Core Data | Core Data possui sobrecarga desnecessária e comportamento de *faulting* complexo. GRDB permite consultas SQL limpas, melhor controle de concorrência e migrações previsíveis. |

## 14. Roadmap por Fases
- **Fase 1 (MVP - Conectividade Básica):** CRUD de sessões em SQLite; Segurança base via Keychain; Conexão básica e terminal interativo com *libssh2* e *SwiftTerm*.
- **Fase 2 (Produtividade):** Gestão em múltiplas abas; *Split Panes*; Autenticação via Chave Privada; Busca global de sessões.
- **Fase 3 (Ferramentas Avançadas):** Interface gráfica nativa para SFTP e SCP; Gestão visual de túneis de porta (Local/Remoto/Dinâmico); *Jump Hosts*.
- **Fase 4 (Ecossistema Apple):** iCloud Sync (sincronização de configurações); Integração com Secure Enclave; Extensões de Atalhos (*Shortcuts*).

## 15. Estratégia de Testes
- **Testes Unitários:** Foco nos Casos de Uso (regras de validação de *host keys*, parsing de URLs/URIs SSH, lógicas de agrupamento de pastas).
- **Testes de Integração:** Repositórios de dados (banco SQLite em memória) e integração com Keychain mockado para validar os fluxos de criptografia e resiliência de estado.
- **UI Tests (XCUITest):** Automação do fluxo feliz: Criar sessão -> Salvar -> Verificar persistência visual na *Sidebar*.

## 16. Estratégia de Distribuição no macOS
- O app será assinado com certificado **Developer ID** e notarizado pela Apple para distribuição direta via arquivo DMG ou ZIP.
- Adoção de um framework como *Sparkle* para atualizações automáticas (*auto-updater*).
- Arquitetura desenhada já contemplando o **App Sandbox**, prevendo uma futura submissão para a Mac App Store (MAS), garantindo que os *entitlements* de acesso à rede e Keychain sejam bem definidos desde o início.

## 17. Observabilidade, Logs e Diagnóstico
- Utilização exclusiva da API nativa `OSLog` (`Logger`).
- **Níveis de Log:**
  - `Debug/Trace`: Fluxo interno do motor SSH (desabilitado em produção).
  - `Info`: Abertura e fechamento de conexões, tempos de resposta.
  - `Error/Fault`: Falhas criptográficas, erros de banco de dados e quedas inesperadas de *socket*.
- Criação de uma ferramenta oculta no menu de Ajuda para "Exportar Diagnóstico", gerando um arquivo de log anonimizado para suporte técnico.

## 18. Backlog Inicial Priorizado
1. **[Setup]** Configurar o projeto Xcode (SwiftUI, macOS 14+), dependências via SPM (GRDB, SwiftTerm).
2. **[UI/UX]** Implementar o *layout shell* principal (Sidebar vazia, Detail View vazia, Navigation Split View).
3. **[Core]** Criar o *wrapper* básico da *libssh2* e validar uma conexão de teste (*hardcoded*).
4. **[Database]** Implementar o schema GRDB e os repositórios CRUD para Sessões e Pastas.
5. **[Security]** Implementar os serviços de Keychain para ler e gravar senhas.
6. **[Terminal]** Embutir o emulador *SwiftTerm* na tela de detalhe e conectá-lo ao *stream* do motor SSH.
7. **[Integração]** Unir os fluxos: A interface de criação de sessão salva no SQLite/Keychain e aciona a conexão real que renderiza no Terminal.
8. **[Validação]** Implementar tratativas de erro visuais (credenciais inválidas, *host key* recusada, *timeout* de rede).

## 19. Sugestão de Estrutura de Pastas/Projetos
```text
ZetSSH/
├── App/                # Ponto de entrada (App, AppDelegate, injeção de dependência)
├── Core/               # Extensões, Utilitários, OSLog, Constantes Globais
├── Domain/             # Entidades, Enums, Interfaces de Repositórios e UseCases
├── Data/               # Implementações concretas
│   ├── Database/       # GRDB, Migrações, DAOs
│   ├── Security/       # Wrappers do Keychain e validação de chaves
│   └── Network/        # Implementação do SSH Engine (C-Interop libssh2)
├── Presentation/       # Camada Visual (SwiftUI + AppKit)
│   ├── Components/     # Botões, TextFields, alertas reutilizáveis
│   ├── Sessions/       # Sidebar, Formulários de Criação/Edição
│   └── Terminal/       # NSViewRepresentable do SwiftTerm e TerminalView
└── Tests/              # ZetSSHTests (Unit e Integration), ZetSSHUITests
```

## 20. Critérios de Aceite do MVP
- O aplicativo compila e executa nativamente no macOS sem *crashes* na inicialização.
- O usuário consegue criar uma sessão fornecendo Endereço IP/Hostname, Porta, Usuário e Senha.
- A senha fornecida é verificavelmente gravada apenas no Keychain, não existindo no arquivo `.sqlite`.
- Ao selecionar a sessão na *sidebar* e conectar, o aplicativo apresenta um terminal funcional em menos de 2 segundos.
- O terminal suporta corretamente a digitação, exibição de resultados de comandos básicos e comandos baseados em *curses* (como `vim` ou `top`).
- Fechar a aba/janela encerra o processo SSH em *background* de forma limpa, sem deixar threads zumbis ou conexões pendentes (*leaks*).

---

## Saída Final Esperada (Resumo Executivo)

1. **Arquitetura Recomendada:** Clean Architecture (Domain Driven) com Presentation Layer híbrida (SwiftUI como estrutura principal + AppKit para o emulador do Terminal), Data Layer baseada em GRDB (SQLite) e infraestrutura de rede suportada por C-Interop com bibliotecas sólidas (`libssh2`).
2. **Roadmap em Fases:** MVP (Terminal e CRUD básico) ➔ Produtividade (Abas, Split, Busca) ➔ Avançado (Túneis, SFTP) ➔ Enterprise (iCloud, Secure Enclave).
3. **Backlog Inicial Priorizado:** Setup ➔ Estrutura de UI ➔ PoC de Rede SSH ➔ Persistência (SQLite) ➔ Segurança (Keychain) ➔ Emulação de Terminal ➔ Integração Final de Fluxos.
4. **Proposta de Modelo de Dados:** Tabela de sessões leve no SQLite contendo apenas metadados relacionais e de UI.
5. **Maiores Riscos Técnicos:** Renderização do terminal limitando a performance e vazamento de memória/concorrência insegura ao interagir com a biblioteca C (*libssh2*).
6. **Recomendação Explícita (SQLite vs Keychain):** 
   - **No SQLite:** Nomes, Hosts, Portas, Metadados Visuais (cores, fontes), IDs de pastas, *Fingerprints* públicas (para *KnownHosts*).
   - **No Keychain:** Senhas em texto puro, *passphrases* de proteção de chave privada, chaves privadas inteiras (se gerenciadas internamente pelo app).
