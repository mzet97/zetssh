# ZetSSH — Final Product Design Spec

**Data:** 2026-04-14  
**Autor:** Matheus Zeitune  
**Status:** Aprovado para implementação

---

## Visão Geral

ZetSSH é um cliente SSH profissional nativo macOS (SwiftUI + SwiftNIO-SSH + SwiftTerm + GRDB). Este documento especifica os 8 subsistemas que completam o produto para distribuição, executados em ordem A→H usando `superpowers:subagent-driven-development` com agentes paralelos onde os subsistemas são independentes.

**Stack base aprovada:** Swift 5.9+, SwiftUI/AppKit, SwiftNIO-SSH 0.12.0, GRDB 6.29.3, SwiftTerm 1.13.0, Crypto (via NIOSSH), macOS 13+

---

## Subsistema A — Autenticação por Chave Privada

### Objetivo
Suporte completo a Ed25519, RSA e ECDSA com passphrase opcional. Design: Segmented Control "Senha | Chave Privada" no SessionFormView (opção A1 aprovada pelo usuário).

### Componentes

**Domain:**
- `Session.swift`: adicionar campo `privateKeyPath: String?`

**Data:**
- `AppDatabase.swift`: migração v3 — coluna `privateKeyPath TEXT` na tabela `session`
- `KeychainService.swift`: métodos `savePassphrase(_:forSessionId:)`, `fetchPassphrase(forSessionId:)`, `deletePassphrase(forSessionId:)` (separados do password)
- `RealSSHEngine.swift`: implementar `authenticate(privateKeyPath:passphrase:)` com `NIOSSHPrivateKey(pemRepresentation:passphrase:)`
- `PrivateKeyAuthenticationDelegate` (nova classe privada em RealSSHEngine.swift): usa `.privateKey` offer em `nextAuthenticationType`

**Presentation:**
- `SessionFormView.swift`: Picker segmentado "Senha" / "Chave Privada"; quando "Chave Privada" ativo, mostra path label + botão "Selecionar..." (NSOpenPanel) + SecureField passphrase opcional
- `SSHTerminalView.swift` (Coordinator.connect): detecta `session.privateKeyPath != nil` e chama a variante correta de `authenticate`

### Fluxo
1. Usuário seleciona "Chave Privada" → NSOpenPanel com filtro `.pem`, `.pub`, sem extensão
2. Path retornado → salvo em `session.privateKeyPath` (GRDB)
3. Passphrase (se houver) → Keychain com key `"passphrase-{sessionId}"`
4. Na conexão: `engine.authenticate(privateKeyPath: URL(fileURLWithPath: path), passphrase: passphrase)`
5. Engine lê PEM do disco → `NIOSSHPrivateKey` → `PrivateKeyAuthenticationDelegate` → servidor

### Arquivos
- Modify: `zetssh/Domain/Models/Session.swift`
- Modify: `zetssh/Data/Database/AppDatabase.swift`
- Modify: `zetssh/Data/Security/KeychainService.swift`
- Modify: `zetssh/Data/Network/RealSSHEngine.swift`
- Modify: `zetssh/Presentation/Sessions/SessionFormView.swift`
- Modify: `zetssh/Presentation/Terminal/TerminalView.swift`

---

## Subsistema B — Multi-tab SSH

### Objetivo
Múltiplas sessões SSH simultâneas em abas nativas macOS. Cada aba tem seu próprio `RealSSHEngine` independente, sem compartilhamento de estado.

### Design de UI
`NavigationSplitView` mantido na sidebar. O painel detail exibe um `TabView` quando há abas abertas. Cada aba = `SessionTabItem` com `SessionDetailView` interno.

### Componentes

**Domain:**
- `ActiveSession.swift` (novo): `struct ActiveSession: Identifiable { let id: UUID; let session: Session; var title: String }`

**Presentation:**
- `TabBarView.swift` (novo): barra de abas customizada acima do terminal com botão "+" e fechar "×"
- `MultiSessionView.swift` (novo): `@StateObject var tabsVM: TabsViewModel` → renderiza `TabBarView` + conteúdo da aba selecionada
- `TabsViewModel.swift` (novo): `@MainActor ObservableObject` com `@Published var tabs: [ActiveSession]`, `@Published var selectedTabId: UUID?`, métodos `open(session:)`, `close(tabId:)`
- `SessionDetailView.swift`: sem mudanças de interface — reutilizado dentro de cada aba
- `ContentView.swift`: detail passa a renderizar `MultiSessionView` quando há tabs; mantém `SessionConnectionView` quando nenhuma aba aberta

### Fluxo
1. Usuário clica em sessão na sidebar → `TabsViewModel.open(session:)` cria nova `ActiveSession`
2. `MultiSessionView` detecta nova aba → seleciona automaticamente
3. Clique em "×" na aba → `TabsViewModel.close(tabId:)` → engine.disconnect() chamado
4. Sidebar duplo-clique = nova aba; clique simples seleciona aba existente se já aberta

### Arquivos
- Create: `zetssh/Domain/Models/ActiveSession.swift`
- Create: `zetssh/Presentation/Sessions/TabsViewModel.swift`
- Create: `zetssh/Presentation/Sessions/TabBarView.swift`
- Create: `zetssh/Presentation/Sessions/MultiSessionView.swift`
- Modify: `zetssh/Presentation/ContentView.swift`

---

## Subsistema C — Suite de Testes

### Objetivo
Cobertura de teste para lógica crítica: modelos GRDB, KeychainService, SessionViewModel, validação de formulário, SSHConnectionError paths. Segue TDD com `superpowers:test-driven-development`.

### Estratégia
- Target XCTest `ZetSSHTests` adicionado ao projeto
- Usa `LibSSH2WrapperMock` (já existente, com `#if DEBUG`) para simular engine sem rede
- GRDB em memória (`DatabaseQueue(path: ":memory:")`) para testes de repository/ViewModel
- Keychain: wrapper `KeychainServiceProtocol` + mock `KeychainServiceMock` para testes

### Cobertura mínima
| Componente | Testes |
|---|---|
| `Session` | Encode/decode GRDB, campos obrigatórios |
| `KnownHost` | Persistência, lookup por host+port+algo |
| `AppDatabase` | Migrações v1→v3 em memória |
| `SessionViewModel` | `save`, `delete`, `ValueObservation` reatividade |
| `SessionFormView` lógica | `portInt` nil para porta inválida, trim correto |
| `SSHConnectionError` | Todos os casos mapeados |
| `KeychainService` | Mocked: save/fetch/delete password e passphrase |

### Arquivos
- Create: `ZetSSHTests/ZetSSHTests.swift` (target XCTest)
- Create: `ZetSSHTests/Mocks/KeychainServiceMock.swift`
- Create: `ZetSSHTests/Models/SessionTests.swift`
- Create: `ZetSSHTests/Models/KnownHostTests.swift`
- Create: `ZetSSHTests/Database/AppDatabaseTests.swift`
- Create: `ZetSSHTests/ViewModels/SessionViewModelTests.swift`
- Create: `ZetSSHTests/Presentation/SessionFormValidationTests.swift`
- Modify: `zetssh/Data/Security/KeychainService.swift` (extrair protocolo `KeychainServiceProtocol`)
- Modify: `zetssh.xcodeproj/project.pbxproj` (adicionar target de teste)

---

## Subsistema D — Terminal Themes & Fontes

### Objetivo
Seleção de tema de cores e fonte no terminal. Temas predefinidos (Dracula, Solarized Dark, One Dark, Default Dark, Gruvbox). Fonte e tamanho personalizáveis.

### Componentes

**Domain:**
- `TerminalProfile.swift` (novo): `struct TerminalProfile: Codable, PersistableRecord, FetchableRecord` com campos `name`, `foreground`, `background`, `cursor`, `fontName`, `fontSize: Double`, `isDefault: Bool`

**Data:**
- `AppDatabase.swift`: migração v4 — tabela `terminalProfile` + inserção de perfis predefinidos
- `ThemeRegistry.swift` (novo): constantes dos 5 temas em `AnsiColors`/hex, método `apply(profile:to:terminalView:)`

**Presentation:**
- `TerminalSettingsView.swift` (novo): Sheet com picker de tema (cards coloridos) + font picker (`NSFontPanel`) + preview live
- `TerminalPreferencesViewModel.swift` (novo): `@MainActor ObservableObject`, carrega/salva perfil ativo do GRDB
- `TerminalView.swift`: `makeNSView` aplica perfil ativo via `ThemeRegistry`; `Coordinator` observa mudanças de perfil

### Integração SwiftTerm
SwiftTerm expõe `installColors(_:)` e `installTheme(_:)`. `TerminalView.installColors` aceita array de 256 `Color`. `TerminalView.nativeForegroundColor` e `nativeBackgroundColor` são configuráveis.

### Arquivos
- Create: `zetssh/Domain/Models/TerminalProfile.swift`
- Create: `zetssh/Data/Database/ThemeRegistry.swift`
- Create: `zetssh/Presentation/Settings/TerminalSettingsView.swift`
- Create: `zetssh/Presentation/Settings/TerminalPreferencesViewModel.swift`
- Modify: `zetssh/Data/Database/AppDatabase.swift` (migração v4)
- Modify: `zetssh/Presentation/Terminal/TerminalView.swift`

---

## Subsistema E — SFTP / File Browser

### Objetivo
Panel lateral SFTP integrado à sessão SSH ativa. Navegar no sistema de arquivos remoto, fazer upload/download via drag & drop macOS.

### Abordagem técnica
SwiftNIO-SSH suporta subsistemas. SFTP requer abrir um canal de subsistema `"sftp"` após autenticação. Usa `NIOSSH` + protocolo SFTP implementado sobre `ByteBuffer`. Alternativa mais simples: `swift-sftp` package (wrapper sobre libssh2) — mas conflita com a filosofia in-process. **Decisão: implementar SFTP sobre NIOSSH com um `SFTPClient` custom baseado no protocolo SFTPv3 (IETF draft-ietf-secsh-filexfer, versão 3).**

### Componentes
- `SFTPClient.swift` (novo): gerencia canal SFTP, comandos `ls`, `get`, `put`, `mkdir`, `rm`
- `SFTPEngine.swift` (novo): protocolo com métodos async throws para operações SFTP
- `FileBrowserView.swift` (novo): `HSplitView` ou sheet lateral com `List` de arquivos remotos, botões upload/download
- `FileBrowserViewModel.swift` (novo): `@MainActor ObservableObject` com estado de navegação e transferências
- `FileTransferItem.swift` (novo): progresso de transfers `@Published var progress: Double`

### UI
Botão "SFTP" na toolbar do terminal ativo → abre `FileBrowserView` como sheet ou panel lateral. Drag de arquivo local para a janela → upload automático.

### Arquivos
- Create: `zetssh/Data/Network/SFTPClient.swift`
- Create: `zetssh/Data/Network/SFTPEngine.swift`
- Create: `zetssh/Domain/Models/FileTransferItem.swift`
- Create: `zetssh/Presentation/SFTP/FileBrowserView.swift`
- Create: `zetssh/Presentation/SFTP/FileBrowserViewModel.swift`
- Modify: `zetssh/Presentation/Sessions/SessionDetailView.swift` (toolbar SFTP button)
- Modify: `zetssh/Data/Network/RealSSHEngine.swift` (expor canal para SFTPClient)

---

## Subsistema F — SQLCipher Encryption

### Objetivo
Banco GRDB criptografado em repouso usando a chave de 256 bits já gerada no Keychain.

### Abordagem
Substituir `GRDB` (SQLite puro) por `GRDBCipher` (SQLCipher). No SPM, usar o fork `groue/GRDB.swift` com flag `GRDB_SQLITE_HAVE_SQLCIPHER=1` ou o package `stephencelis/SQLCipher-SPM`. A chave já está no Keychain (`KeychainService.getOrCreateDatabaseEncryptionKey()`).

### Mudanças
- `Package.swift` (ou Xcode): trocar dependência `GRDB` por `GRDBCipher`
- `AppDatabase.swift`: descomentar `config.prepareDatabase { db in try db.usePassphrase(encryptionKey) }`
- Migração existente: sem mudança de schema — apenas adição de criptografia
- Teste: verificar que arquivo `.sqlite` não é legível em texto plano após a mudança

### Arquivos
- Modify: `zetssh.xcodeproj/project.pbxproj` (trocar package GRDB → GRDBCipher)
- Modify: `zetssh/Data/Database/AppDatabase.swift` (enable passphrase)
- Modify: `ZetSSHTests/Database/AppDatabaseTests.swift` (usar DB em memória, não passphrase)

---

## Subsistema G — SSH Config Import

### Objetivo
Parser de `~/.ssh/config` que importa hosts como sessões ZetSSH com um clique.

### Formato suportado
```
Host alias
  HostName servidor.com
  User ubuntu
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
```

### Componentes
- `SSHConfigParser.swift` (novo): parser linha a linha, produz `[SSHConfigEntry]` com campos `alias`, `hostname`, `user`, `port`, `identityFile`
- `SSHConfigEntry.swift` (novo): struct com os campos acima
- `SSHConfigImportView.swift` (novo): Sheet com lista de hosts encontrados, checkboxes para selecionar quais importar, botão "Importar Selecionados"
- `SSHConfigImportViewModel.swift` (novo): lê `~/.ssh/config` (requer sandbox entitlement `~/.ssh/` read), converte entries em `Session` + chama `SessionViewModel.save`

### Sandbox
Requer `com.apple.security.files.user-selected.read-write` (já presente) + adicionar `~/.ssh` ao grupo de acesso por NSOpenPanel na primeira importação para obter bookmark persistente.

### Arquivos
- Create: `zetssh/Data/SSH/SSHConfigParser.swift`
- Create: `zetssh/Domain/Models/SSHConfigEntry.swift`
- Create: `zetssh/Presentation/Import/SSHConfigImportView.swift`
- Create: `zetssh/Presentation/Import/SSHConfigImportViewModel.swift`
- Modify: `zetssh/Presentation/Sessions/SidebarView.swift` (menu "Importar do ~/.ssh/config")

---

## Subsistema H — App Icon + Notarização

### Objetivo
App pronto para distribuição: ícone profissional, Info.plist completo, notarização Apple, DMG para download direto.

### Componentes

**App Icon:**
- `Assets.xcassets/AppIcon.appiconset`: ícone gerado para todos os tamanhos (16×16 → 1024×1024)
- Design: terminal SSH estilizado, cores azul/verde, cantos arredondados macOS

**Info.plist:**
- `CFBundleDisplayName: ZetSSH`
- `CFBundleVersion` e `CFBundleShortVersionString`: `1.0.0`
- `NSHumanReadableCopyright`
- `LSMinimumSystemVersion: 13.0`

**Notarização:**
- Script `scripts/notarize.sh`: `xcodebuild archive` → `xcrun altool --notarize-app` → `xcrun stapler staple`
- Requer Apple Developer account + `APPLE_ID`, `TEAM_ID`, `APP_PASSWORD` env vars

**Distribuição:**
- Script `scripts/create-dmg.sh`: usa `create-dmg` (brew) para gerar `.dmg` com background customizado e link para Applications

**Sparkle (atualizações automáticas):**
- Adicionar `sparkle-project/Sparkle` via SPM
- `AppDelegate` ou `zetsshApp`: `SPUStandardUpdaterController` inicializado no launch
- `appcast.xml` hospedado em GitHub Releases

### Arquivos
- Create: `zetssh/Assets.xcassets/AppIcon.appiconset/` (todos os tamanhos)
- Create: `zetssh/App/Info.plist` (se não existir)
- Create: `scripts/notarize.sh`
- Create: `scripts/create-dmg.sh`
- Modify: `zetssh.xcodeproj/project.pbxproj` (adicionar Sparkle SPM)
- Modify: `zetssh/App/zetsshApp.swift` (inicializar Sparkle updater)

---

## Estratégia de Execução

### Paralelismo possível
Os subsistemas têm as seguintes dependências:

```
A (Chave Privada) ──┐
B (Multi-tab)      ──┼── independentes → executar em paralelo (A+B+C+D+G)
C (Testes)         ──┤
D (Themes)         ──┤
G (SSH Config)     ──┘

F (SQLCipher)      ── independente, mas quebra testes se feito antes de C

E (SFTP)           ── depende de A e B (usa conexão autenticada + SessionDetailView com toolbar)
H (Distribuição)   ── depende de todos os outros (último)
```

### Ordem de execução com agentes
- **Fase 1 (paralelo):** A + B + D + G — `superpowers:dispatching-parallel-agents`
- **Fase 2 (sequencial):** C (testes, após A/B/D/G) → F (SQLCipher, após C) → E (SFTP, após A)
- **Fase 3:** H (distribuição, após tudo)

### Skills utilizados por subsistema
| Subsistema | Skill principal |
|---|---|
| A, B, D, E, G | `superpowers:subagent-driven-development` |
| C | `superpowers:test-driven-development` |
| F | `superpowers:subagent-driven-development` |
| H | `superpowers:subagent-driven-development` |
| Fase 1 | `superpowers:dispatching-parallel-agents` |
| Review pós-task | `superpowers:requesting-code-review` |
