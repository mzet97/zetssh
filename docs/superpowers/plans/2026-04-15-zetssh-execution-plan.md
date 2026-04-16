# ZetSSH — Plano de Execução por Fases

> **SWE Principal:** Orquestração Sisyphus + OMC Multi-Agent  
> **Data:** 2026-04-15  
> **Baseado em:** `docs/superpowers/plans/2026-04-15-zetssh-complete.md`  
> **Status do Codebase:** Análise completa de 38 arquivos Swift, Podfile, e project.pbxproj

---

## Descobertas Críticas vs. Plano Original

| Item no Plano Original | Estado Real no Codebase | Impacto |
|---|---|---|
| **Task 1** — Sendable warnings | Código já usa `@unchecked Sendable` + `nonisolated` + captura de valores. Pode haver warnings residuais em Swift 6 strict. | Baixo risco — verificar com `xcodebuild` |
| **Task 6** — SQLCipher | **JÁ IMPLEMENTADO.** `Podfile` usa `GRDB.swift/SQLCipher`, `AppDatabase.swift` usa `KeychainService.shared.getOrCreateDatabaseEncryptionKey()` + `db.usePassphrase()`. Migração com backup automático existe. | **REMOVER do escopo** — apenas verificar |
| **Task 5** — SFTP real | SFTPClient é **skeleton completo** com alta/média lógica — só os 5 `sendPacketAwait*` são stubs. ByteBuffer helpers já existem. | Escopo menor que o previsto — implementar só os stubs + SFTPChannelHandler + `openSFTPClient()` em RealSSHEngine |

---

## Mapa de Infraestrutura Disponível

### Agents OMC (orquestração via `task()`)

| Agent | Modelo | Uso neste Projeto |
|---|---|---|
| `explore` | haiku | Busca contextual no codebase — mapear dependências, encontrar padrões |
| `oracle` | opus | Arquitetura SFTP/NIO, validação de design de concorrência Swift |
| `librarian` | sonnet | Referência SwiftNIO-SSH API, GRDB SQLCipher docs, SwiftTerm API |
| `code-reviewer` | opus | Review pós-implementação de cada fase |
| `test-engineer` | sonnet | Estratégia de testes unitários/integração |
| `designer` | sonnet | UI/UX do indicador de estado nas abas |
| `debugger` | sonnet | Diagnóstico se build/lint falhar |
| `verifier` | sonnet | Verificação de completude ao final de cada fase |

### Skills OMC (via `skill` tool)

| Skill | Fases |
|---|---|
| `omc-reference` | Todas — catálogo de agents, commit protocol, pipeline |
| `frontend-ui-ux` | Fase 3 (tab indicators), Fase 4 (disconnect button UX) |
| `git-master` | Commits atômicos entre fases |
| `review-work` | Pós-Fase 4 (review geral) |

### Categorias de Delegação

| Categoria | Uso |
|---|---|
| `visual-engineering` | Tab indicators (Fase 3), Disconnect button (Fase 2) |
| `deep` | SFTP NIO implementation (Fase 4) — problema complexo com múltiplas camadas |
| `quick` | Sendable fix (Fase 1), SQLCipher verification |
| `unspecified-high` | Reconnection callback (Fase 2) |

### Ferramentas Diretas

| Ferramenta | Uso |
|---|---|
| `lsp_diagnostics` | Verificar zero errors/warnings após cada mudança |
| `lsp_find_references` | Mapear impacto de mudanças em protocolos |
| `ast_grep_search/replace` | Refatorar padrões Sendable, adicionar callbacks |
| `read/edit/write` | Modificação direta de arquivos |
| `bash` (xcodebuild) | Build validation |

### MCPs Disponíveis

| MCP | Uso |
|---|---|
| `context7` | Documentação SwiftNIO-SSH, GRDB, SwiftTerm |
| `grep_app` (grep.app) | Exemplos reais de SFTPChannelHandler, NIOSSH subsystem requests |
| `microsoft-docs` | Não aplicável (não é stack Microsoft) |

---

## Diagrama de Dependências entre Fases

```
Fase 0 — Verificação ─────────────────────────────┐
                                                     │
Fase 1 — Quick Wins (Task 1) ──────────────────────┤ Independente
                                                     │
Fase 2 — Ciclo de Vida de Conexão (Tasks 2+3) ─────┤ Seqüencial (3 depende de 2)
                   │                                 │
                   ▼                                 │
Fase 3 — UX: Indicadores de Aba (Task 4) ──────────┤ Depende de 2 (connectionState)
                                                     │
Fase 4 — SFTP Real via NIO (Task 5) ────────────────┤ Depende de 2 (engineRef)
                                                     │
Fase 5 — Review Final + Commit Geral ────────────────┘
```

---

## FASE 0 — Verificação & Preparação

**Duração estimada:** 10 min  
**Objetivo:** Confirmar estado exato do codebase, build limpo, e remover tarefas já concluídas.

### Ações

| # | Ação | Executor | Ferramenta |
|---|---|---|---|
| 0.1 | Build completo do projeto para verificar estado atual | **self** | `bash: xcodebuild -workspace zetssh.xcworkspace -scheme zetssh build` |
| 0.2 | Verificar se existem warnings Sendable residuais | **self** | Parse output do build |
| 0.3 | Confirmar SQLCipher integrado — ler `Podfile` + `AppDatabase.swift` | **self** | Já confirmado ✅ |
| 0.4 | Confirmar SFTP skeleton — mapear stubs exatos | **self** | Já confirmado ✅ — 5 métodos `sendPacketAwait*` em `SFTPClient.swift` |
| 0.5 | Confirmar ausência de testes em `ZetSSHTests/` | **self** | `read` no diretório |

### Decisão de Escopo

- ✅ **Task 6 (SQLCipher)**: REMOVIDA — já implementada. Apenas verificar que funciona no build.
- ✅ **Task 1 (Sendable)**: Manter — verificar se build gera warnings.
- ✅ **Tasks 2, 3, 4, 5**: Manter todas — são gaps reais.

### Gate

> Build deve compilar (erros de warning são aceitáveis aqui — serão corrigidos na Fase 1).  
> Se build falhar com erros hard, diagnosticar com `debugger` agent antes de prosseguir.

---

## FASE 1 — Quick Wins: Sendable Warnings

**Duração estimada:** 15 min  
**Objetivo:** Zero warnings de Sendable em `RealSSHEngine.swift`.  
**Dependência:** Nenhuma (independente).

### Análise do Estado Atual

O código já usa `@unchecked Sendable` nas 4 delegate classes privadas e `nonisolated` nos métodos `nextAuthenticationType`. O `HostKeyVerificationDelegate.validateHostKey` já captura `host` e `port` como `let` antes do `Task { @MainActor in }`.

**Possíveis fontes de warning restantes:**
- `SSHKeepaliveHandler` e `SSHInboundDataHandler` usam `weak var delegate: (any SSHClientDelegate)?` — que é `Sendable` por protocolo mas `any` pode gerar warning em Swift 6 strict
- O `Task { @MainActor in }` dentro de `nonisolated func validateHostKey` pode precisar de `@Sendable` explícito na closure

### Plano de Execução

| # | Ação | Executor | Agent/Tool |
|---|---|---|---|
| 1.1 | Identificar warnings exatos com build | **self** | `bash: xcodebuild 2>&1 \| grep -i "sendable"` |
| 1.2 | Se warnings existirem: consultar referência Swift 6 concurrency | **librarian** (bg) | Buscar padrões Swift 6 Sendable para NIO delegates |
| 1.3 | Aplicar correções nos delegates afetados | **self** | `edit` nos pontos exatos |
| 1.4 | Build + LSP diagnostics — confirmar zero warnings | **self** | `lsp_diagnostics` + `bash: xcodebuild` |
| 1.5 | Commit atômico | **self** (via `git-master`) | `skill: git-master` |

### Delegação

```
Se warnings > 0:
  → task(category="quick", load_skills=["omc-reference"],
         prompt="Fix Sendable warnings in RealSSHEngine.swift delegates...")
Se warnings == 0:
  → Skip, marcar como concluída
```

### Gate

> `xcodebuild` com 0 warnings de Sendable. `lsp_diagnostics` limpo em `RealSSHEngine.swift`.

---

## FASE 2 — Ciclo de Vida de Conexão (Tasks 2 + 3)

**Duração estimada:** 50 min (30 + 20)  
**Objetivo:** Reconexão automática após disconnect/timeout + Botão Disconnect na toolbar.  
**Dependência:** Sequencial — Task 3 depende do `engineRef` introduzido em Task 2.

### Arquivos Modificados

| Arquivo | Mudança |
|---|---|
| `Presentation/Terminal/TerminalView.swift` | Adicionar `onConnectionEnded` callback + `onEngineReady` callback |
| `Presentation/Sessions/SessionDetailView.swift` | Consumir callbacks, adicionar `@State var activeEngine`, toolbar Disconnect |
| `Data/Network/RealSSHEngine.swift` | Nenhuma mudança (já tem `disconnect()`) |

### Estratégia de Implementação

A abordagem escolhida é a **"abordagem simples"** do plano original: expor callbacks no `SSHTerminalView` e manter `@State var activeEngine` no `SessionDetailView`. Isso evita a refatoração profunda de criar `SSHSessionController` — que seria over-engineering para o escopo atual.

#### Passo 2.1 — Callbacks no SSHTerminalView

**Modificações em `TerminalView.swift`:**

```swift
struct SSHTerminalView: NSViewRepresentable {
    // ... existing props ...
    var onConnectionEnded: (() -> Void)?
    var onEngineReady:    ((any SSHEngine) -> Void)?

    final class Coordinator: NSObject {
        // ... existing props ...
        var onConnectionEnded: (() -> Void)?
        var onEngineReady:    ((any SSHEngine) -> Void)?

        // Em connect(), após authenticate() sucesso:
        // self?.onEngineReady?(engine)
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        // ... existing setup ...
        context.coordinator.onConnectionEnded = onConnectionEnded
        context.coordinator.onEngineReady    = onEngineReady
        return termView
    }
}
```

**Modificações em `onError` e `onDisconnected`:**

```swift
func onError(_ error: Error) {
    // ... existing text formatting ...
    terminalView?.feed(text: text)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        self?.onConnectionEnded?()
    }
}

func onDisconnected() {
    // ... existing text ...
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        self?.onConnectionEnded?()
    }
}
```

#### Passo 2.2 — Consumir callbacks em SessionDetailView

**Modificações em `SessionDetailView.swift`:**

```swift
@State private var activeEngine: (any SSHEngine)?

// No SSHTerminalView:
SSHTerminalView(
    host:           session.host,
    port:           session.port,
    username:       session.username,
    sessionId:      session.id,
    privateKeyPath: session.privateKeyPath,
    onConnectionEnded: {
        connectionStarted = false
        activeEngine = nil
    },
    onEngineReady: { engine in
        activeEngine = engine
    }
)

// Toolbar — novo item Disconnect:
ToolbarItem(placement: .automatic) {
    Button(role: .destructive) {
        activeEngine?.disconnect()
        connectionStarted = false
        activeEngine = nil
    } label: {
        Label("Desconectar", systemImage: "xmark.circle")
    }
    .help("Encerrar sessão SSH")
    .disabled(!connectionStarted)
}
```

### Orquestração

| # | Ação | Executor | Agent/Tool |
|---|---|---|---|
| 2.1 | Implementar `onConnectionEnded` + `onEngineReady` no `SSHTerminalView.Coordinator` | **delegar** | `task(category="unspecified-high", load_skills=["omc-reference"])` |
| 2.2 | Modificar `onError`/`onDisconnected` para disparar callback | **delegar** (mesma task) | Continuação da task acima |
| 2.3 | Modificar `SessionDetailView` para consumir callbacks + adicionar toolbar Disconnect | **delegar** (mesma task) | Continuação |
| 2.4 | LSP diagnostics nos 2 arquivos modificados | **self** | `lsp_diagnostics` em paralelo |
| 2.5 | Build validation | **self** | `bash: xcodebuild` |
| 2.6 | Commit atômico (2 arquivos) | **self** (via `git-master`) | `skill: git-master` |

### Delegação (Prompt Completo)

```
1. TASK: Implement reconnection flow + disconnect button for SSH sessions
2. EXPECTED OUTCOME:
   - SSHTerminalView exposes onConnectionEnded and onEngineReady callbacks
   - Coordinator fires onConnectionEnded in onError (after 2s delay) and onDisconnected (after 2s delay)
   - Coordinator fires onEngineReady after successful authenticate() in connect()
   - SessionDetailView stores activeEngine via @State
   - SessionDetailView toolbar has destructive Disconnect button (disabled when not connected)
   - Disconnect button calls activeEngine?.disconnect(), resets connectionStarted=false, activeEngine=nil
3. REQUIRED TOOLS: read, edit, lsp_diagnostics
4. MUST DO:
   - Match existing code style exactly (see surrounding patterns)
   - Use DispatchQueue.main.asyncAfter for the 2-second delay before onConnectionEnded
   - Keep the existing error messages text formatting intact
   - The onEngineReady must fire AFTER authenticate succeeds, not before
   - Toolbar Disconnect button must use Button(role: .destructive)
5. MUST NOT DO:
   - Do NOT create new files (SSHSessionController etc.)
   - Do NOT refactor existing code beyond the specified changes
   - Do NOT change any Sendable annotations
   - Do NOT touch RealSSHEngine.swift
6. CONTEXT:
   - Files: /Users/zeitune/src/zetssh/zetssh/Presentation/Terminal/TerminalView.swift
            /Users/zeitune/src/zetssh/zetssh/Presentation/Sessions/SessionDetailView.swift
   - SSHTerminalView is NSViewRepresentable with nested Coordinator class
   - Coordinator conforms to SSHClientDelegate (onDataReceived, onError, onDisconnected)
   - Coordinator conforms to TerminalViewDelegate (send, sizeChanged)
   - SessionDetailView uses @State private var connectionStarted = false
   - Engine protocol has disconnect() method already
```

### Gate

> App compila. Clicar "Desconectar" na toolbar retorna para SessionConnectionView.  
> Após timeout/desconnect, app retorna automaticamente para SessionConnectionView após 2s.  
> `lsp_diagnostics` limpo em ambos os arquivos.

---

## FASE 3 — UX: Indicador de Estado nas Abas (Task 4)

**Duração estimada:** 30 min  
**Objetivo:** Círculo colorido em cada aba indicando estado da conexão.  
**Dependência:** Depende de Fase 2 — precisa que `onConnectionEnded`/`onEngineReady` propaguem estado.

### Arquivos Modificados

| Arquivo | Mudança |
|---|---|
| `Domain/Models/ActiveSession.swift` | Adicionar `enum TabConnectionState` + `@Published var connectionState` — **mas ActiveSession é struct, não class!** Precisa de ajuste |
| `Presentation/Sessions/TabsViewModel.swift` | Adicionar `updateConnectionState()` |
| `Presentation/Sessions/TabBarView.swift` | Adicionar `Circle()` indicador na `tabButton(for:)` |
| `Presentation/Sessions/MultiSessionView.swift` | Passar `tabsVM` e `tabId` para `SessionDetailView` |
| `Presentation/Sessions/SessionDetailView.swift` | Receber `tabId` + `tabsVM`, propagar estado via `.onChange(of: connectionStarted)` |

### Desafio Arquitetural

`ActiveSession` é um **struct** (value type). `TabsViewModel` tem `@Published private(set) var tabs: [ActiveSession]`. Para propagar estado de conexão, existem duas abordagens:

**Opção A (recomendada):** Usar `TabsViewModel.updateConnectionState()` que modifica o array `tabs` — já é `@Published`, então a UI reage automaticamente. A `SessionDetailView` chama `tabsVM.updateConnectionState(.connected, forTabId: tabId)`.

**Opção B:** Transformar `ActiveSession` em `class: ObservableObject` — refatoração mais profunda, desproporcional ao beneficio.

### Orquestração

| # | Ação | Executor | Agent/Tool |
|---|---|---|---|
| 3.1 | Adicionar `TabConnectionState` enum + property em `ActiveSession` | **delegar** | `task(category="visual-engineering", load_skills=["omc-reference", "frontend-ui-ux"])` |
| 3.2 | Adicionar `updateConnectionState()` em `TabsViewModel` | **delegar** (mesma task) | Continuação |
| 3.3 | Adicionar indicador `Circle()` em `TabBarView.tabButton(for:)` | **delegar** (mesma task) | Continuação |
| 3.4 | Passar `tabId` + `tabsVM` via `MultiSessionView` para `SessionDetailView` | **delegar** (mesma task) | Continuação |
| 3.5 | Propagar estado em `SessionDetailView` via `.onChange(of: connectionStarted)` | **delegar** (mesma task) | Continuação |
| 3.6 | LSP diagnostics em todos os 5 arquivos | **self** | `lsp_diagnostics` em paralelo |
| 3.7 | Build validation | **self** | `bash: xcodebuild` |
| 3.8 | Commit atômico (5 arquivos) | **self** (via `git-master`) | `skill: git-master` |

### Delegação (Prompt Completo)

```
1. TASK: Add connection state indicator to tab bar tabs
2. EXPECTED OUTCOME:
   - New enum TabConnectionState { idle, connecting, connected, disconnected } in ActiveSession.swift
   - ActiveSession struct gets `var connectionState: TabConnectionState = .idle`
   - TabsViewModel gets `updateConnectionState(_ state: TabConnectionState, forTabId id: UUID)`
   - TabBarView shows 6pt Circle() before tab label: green=connected, yellow=connecting, red=disconnected, clear=idle
   - MultiSessionView passes tabId and tabsVM to SessionDetailView
   - SessionDetailView calls tabsVM.updateConnectionState on onChange(of: connectionStarted)
3. REQUIRED TOOLS: read, edit, lsp_diagnostics
4. MUST DO:
   - Use Option A: modify tabs array via TabsViewModel method, don't convert ActiveSession to class
   - Match existing SwiftUI style (see TabBarView.swift for spacing, font patterns)
   - Circle must be 6x6pt, positioned before the Text in HStack
   - Use Color.green/.yellow/.red/.clear for states
   - SessionDetailView init should accept optional tabId and tabsVM (with defaults nil for backward compat)
5. MUST NOT DO:
   - Do NOT convert ActiveSession from struct to class
   - Do NOT change existing tab close button behavior
   - Do NOT modify RealSSHEngine or TerminalView
6. CONTEXT:
   - ActiveSession is a struct with id, session, label properties (19 lines)
   - TabsViewModel is @MainActor ObservableObject with @Published tabs and selectedTabId
   - TabBarView uses HStack with Text + close Button, 34pt height
   - MultiSessionView iterates tabs with ForEach, passes tab.session to SessionDetailView
   - SessionDetailView currently has no tabId or tabsVM reference
```

### Gate

> Indicador de estado visível nas abas. Troca de estado funciona ao conectar/desconectar.  
> `lsp_diagnostics` limpo em todos os 5 arquivos.

---

## FASE 4 — SFTP Real via NIO (Task 5)

**Duração estimada:** 2-3h  
**Objetivo:** Implementar SFTPv3 funcional sobre canal NIO-SSH com file browser UI real.  
**Dependência:** Depende de Fase 2 (`activeEngine` / `engineRef` em `SessionDetailView`).

### Arquivos Modificados

| Arquivo | Mudança | Complexidade |
|---|---|---|
| `Data/Network/SFTPClient.swift` | Implementar 5 `sendPacketAwait*` stubs + adicionar `SFTPChannelHandler` | **ALTA** |
| `Data/Network/RealSSHEngine.swift` | Adicionar `openSFTPClient()` | MÉDIA |
| `Presentation/SFTP/FileBrowserViewModel.swift` | Trocar placeholder por engine real | BAIXA |
| `Presentation/Sessions/SessionDetailView.swift` | Substituir placeholder sheet por FileBrowserView real | BAIXA |

### Estratégia de Implementação

Esta é a fase mais complexa. A abordagem é:

1. **Consultar Oracle** sobre design do `SFTPChannelHandler` e integração NIO-SSH
2. **Buscar referências** com librarian para exemplos de NIO-SSH SFTP subsystem
3. **Delegar implementação** para `deep` category com contexto completo

### Orquestração

| # | Ação | Executor | Agent/Tool |
|---|---|---|---|
| 4.1 | Consultar Oracle: design do SFTPChannelHandler + NIO integration | **oracle** (bg) | `task(subagent_type="oracle", run_in_background=true)` |
| 4.2 | Buscar referência SwiftNIO-SSH SFTP subsystem + ChannelDuplexHandler | **librarian** (bg) | `task(subagent_type="librarian", run_in_background=true)` |
| 4.3 | Buscar exemplos reais de SFTP over SSH em Swift/NIO | **grep_app** (bg) | `grep_app_searchGitHub("SSHChannelRequestEvent.SubsystemRequest", language=["Swift"])` |
| 4.4 | **Aguardar** resultados de 4.1 + 4.2 + 4.3 | — | — |
| 4.5 | Sintetizar design e delegar implementação | **delegar** | `task(category="deep", load_skills=["omc-reference"])` |
| 4.6 | LSP diagnostics em todos os arquivos modificados | **self** | `lsp_diagnostics` em paralelo |
| 4.7 | Build validation | **self** | `bash: xcodebuild` |
| 4.8 | Commit atômico | **self** (via `git-master`) | `skill: git-master` |

### Prompt Oracle (4.1)

```
I'm implementing SFTPv3 over SwiftNIO-SSH in a macOS SSH client app.

Current state:
- RealSSHEngine has an active SSH channel (`self.channel: Channel?`) and child channel (`self.sshChildChannel: Channel?`)
- SFTPClient is initialized with a `Channel` and has high-level methods (listDirectory, download, upload) that call 5 stub methods: sendPacketAwaitHandle, sendPacketAwaitStatus, sendPacketAwaitData, sendPacketAwaitNameList, sendPacketAwaitAttrs
- ByteBuffer helpers (writeSSHString, writeSSHHandle, writeSSHData) already exist

Design question:
1. Should SFTPChannelHandler be added to the EXISTING sshChildChannel pipeline, or should we create a NEW child channel via `sshHandler.createChannel()` for the SFTP subsystem?
2. For the SFTPChannelHandler — is ChannelDuplexHandler the correct base? How should pendingReplies be managed thread-safely with NIO's event loop model?
3. The INIT packet (SSH_FXP_INIT, type=1, version=3) — should this be sent before or after the SubsystemRequest?
4. Are there any pitfalls with reusing the same NIOSSHHandler for both shell and SFTP channels simultaneously?

Constraints:
- Swift 6 strict concurrency
- Must work with NIOSSH's channel model (not raw TCP)
- The shell session must remain active while SFTP is open
```

### Delegação Principal (4.5)

```
1. TASK: Implement SFTPv3 over NIO-SSH — make the file browser functional
2. EXPECTED OUTCOME:
   - SFTPChannelHandler (ChannelDuplexHandler) added to SFTPClient.swift
   - 5 sendPacketAwait* methods implemented with real NIO packet I/O
   - RealSSHEngine.openSFTPClient() creates a new SSH child channel with SFTP subsystem
   - FileBrowserViewModel uses RealSSHEngine.openSFTPClient() instead of placeholder
   - SessionDetailView shows FileBrowserView with real viewModel instead of placeholder text
3. REQUIRED TOOLS: read, edit, write, lsp_diagnostics
4. MUST DO:
   - SFTPChannelHandler must be thread-safe (use lock or event loop guarantees)
   - Create a NEW child channel for SFTP (don't reuse the shell channel)
   - Send SSH_FXP_INIT after SubsystemRequest succeeds
   - Parse responses correctly per SFTPv3 spec (SSH_FXP_HANDLE=102, SSH_FXP_STATUS=101, etc.)
   - sendPacketAwaitNameList must parse uint32 count + N×(filename string + longname string + attrs)
   - sendPacketAwaitAttrs must parse flags + size fields
   - FileBrowserViewModel must accept engine parameter and call connect() in init/task
   - Match existing code patterns (@unchecked Sendable on handlers, NSLock for thread safety)
5. MUST NOT DO:
   - Do NOT modify the existing shell channel or SSHKeepaliveHandler/SSHInboundDataHandler
   - Do NOT change SFTPEngine protocol
   - Do NOT add third-party dependencies
   - Do NOT break existing terminal functionality
6. CONTEXT:
   - [Oracle design guidance will be inserted here from step 4.1]
   - [Librarian references will be inserted here from step 4.2]
   - SFTPClient.swift: 185 lines, has complete high-level flow, only 5 stubs need implementation
   - RealSSHEngine.swift: 736 lines, has openSFTPChannel() stub that returns conn channel
   - FileBrowserViewModel.swift: needs engine reference
   - SessionDetailView.swift: has placeholder sheet "SFTP Browser — requer integração NIO"
   - Podfile: uses GRDB.swift/SQLCipher, SwiftNIO-SSH via SPM
```

### Gate

> Build compila. Conexão SSH funciona. SFTP browser abre e lista diretório `/` do servidor.  
> Upload/download funcional. Nenhum crash.  
> `lsp_diagnostics` limpo em todos os 4 arquivos.

---

## FASE 5 — Review Final + Commit Geral

**Duração estimada:** 20 min  
**Objetivo:** Review completo do código implementado, verificação de qualidade, e polimento final.  
**Dependência:** Todas as fases anteriores.

### Orquestração

| # | Ação | Executor | Agent/Tool |
|---|---|---|---|
| 5.1 | Code review completo de todas as mudanças | **code-reviewer** | `task(subagent_type="oh-my-claudecode:code-reviewer")` |
| 5.2 | Security review — validar Keychain usage, SQLCipher, SSH key handling | **security-reviewer** (bg) | `task(subagent_type="oh-my-claudecode:security-reviewer", run_in_background=true)` |
| 5.3 | Build final com zero warnings | **self** | `bash: xcodebuild` |
| 5.4 | LSP diagnostics completo no diretório `zetssh/` | **self** | `lsp_diagnostics` |
| 5.5 | Squash ou rebase commits se necessário (decisão do usuário) | **self** | Perguntar ao usuário |
| 5.6 | Nota final no project memory | **self** | `oh-my-claudecode_t_project_memory_add_note` |

### Delegação (5.1)

```
Review all changes made in this session across the ZetSSH macOS SSH client.
Focus on:
1. Swift 6 concurrency safety (Sendable, @MainActor, data races)
2. Correct NIO channel lifecycle management (no leaked channels, proper cleanup)
3. SwiftUI state management (no retain cycles, proper @State/@Published usage)
4. SFTP protocol correctness (packet framing, response parsing)
5. UI/UX quality (tab indicators, disconnect flow, error messages)
6. Any potential crash paths (force unwraps, unhandled errors)

Files changed:
- Presentation/Terminal/TerminalView.swift
- Presentation/Sessions/SessionDetailView.swift
- Domain/Models/ActiveSession.swift
- Presentation/Sessions/TabsViewModel.swift
- Presentation/Sessions/TabBarView.swift
- Presentation/Sessions/MultiSessionView.swift
- Data/Network/SFTPClient.swift
- Data/Network/RealSSHEngine.swift
- Presentation/SFTP/FileBrowserViewModel.swift
```

### Gate

> Zero erros de build. Code review passa sem blockers de severidade alta.  
> Project memory atualizado com notas sobre arquitetura e decisions.

---

## Cronograma Resumido

| Fase | Duração | Paralelismo | Risco |
|---|---|---|---|
| **0 — Verificação** | 10 min | Self + bash | 🟢 Baixo |
| **1 — Quick Wins** | 15 min | Self + librarian (bg) | 🟢 Baixo |
| **2 — Ciclo de Vida** | 50 min | Delegar (unspecified-high) | 🟡 Médio |
| **3 — Tab Indicators** | 30 min | Delegar (visual-engineering) | 🟢 Baixo |
| **4 — SFTP NIO** | 2-3h | Oracle + Librarian (bg) → Delegar (deep) | 🔴 Alto |
| **5 — Review Final** | 20 min | code-reviewer + security-reviewer (bg) | 🟢 Baixo |
| **Total** | ~4h | — | — |

### Paralelismo entre Fases

```
Fase 0 ──┐
         ├─ Fase 1 ──┐
         │            ├─ Fase 2 ──┬─ Fase 3 ──┐
         │            │           │            ├─ Fase 5
         │            │           └─ Fase 4 ──┘
         │            │
         └─ SQLCipher ✅ (já feito)
```

**Fase 1 e Fase 2** podem rodar em paralelo se Fase 1 não requer mudanças (i.e., sem warnings).
**Fases 3 e 4** podem rodar em paralelo após Fase 2 completar — são independentes entre si.
**Fase 5** sempre sequencial ao final.

---

## Checklist de Verificação por Fase

### Build Validation (todas as fases)
```bash
xcodebuild -workspace zetssh.xcworkspace \
           -scheme zetssh \
           -destination 'platform=macOS' \
           build 2>&1 | tail -20
```

### LSP Diagnostics (pós-mudança)
```
Para cada arquivo modificado:
  → lsp_diagnostics(filePath: <caminho>, severity: "error")
  → Deve retornar zero errors
```

### Commit Protocol
Todos os commits seguem o formato:
```
<type>(<scope>): <descrição concisa>

Constraint: <restrição ativa se houver>
Confidence: high|medium|low
Scope-risk: narrow|moderate|broad
```

---

## Notas Finais

1. **Task 6 (SQLCipher) removida** — já implementada no codebase com Podfile correto, Keychain integration, e backup automático.
2. **SFTP é o risco principal** — depende de design correto do NIO channel handler. Oracle consultation é mandatória antes de implementar.
3. **ActiveSession é struct** — cuidado ao propagar estado de conexão. Usar TabsViewModel.updateConnectionState() ao invés de converter para class.
4. **Swift 6 strict concurrency** — todas as mudanças devem respeitar Sendable. Usar `@unchecked Sendable` apenas onde semanticamente seguro (seguindo padrão existente).
5. **Sem testes existentes** — Fase 5 deve incluir recomendação de test strategy, mas não bloqueia release.
