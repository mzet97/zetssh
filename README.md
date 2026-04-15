# ZetSSH 🚀

**ZetSSH** é um cliente SSH de nível profissional, nativo para macOS, desenhado com foco em segurança, performance e experiência do usuário (UX/UI). Diferenciando-se de alternativas baseadas em Electron ou webviews, o ZetSSH proporciona baixo consumo de recursos, inicialização instantânea e forte integração com as tecnologias de segurança do ecossistema Apple.

## ✨ Características Principais

- **Experiência Nativa:** Interface moderna construída 100% em SwiftUI, com suporte completo ao Dark Mode e navegação fluida.
- **Gestão de Sessões:** Organização hierárquica de múltiplas sessões SSH utilizando pastas, facilitando o dia a dia de desenvolvedores e sysadmins.
- **Emulação de Terminal de Alta Performance:** Integrado com `SwiftTerm` via AppKit para garantir 60 FPS, suporte a cores ANSI, *scrollback*, e redimensionamento dinâmico.
- **Segurança Robusta:** Nenhuma credencial (senha ou passphrase) é salva em texto puro. Todo material sensível é gerenciado com segurança pelo **Apple Keychain**.
- **Autenticação por Chave Privada:** Suporte completo a chaves Ed25519, RSA e ECDSA, com suporte a *passphrases*.
- **Múltiplas Abas (Multi-tab):** Gerencie dezenas de conexões simultâneas utilizando abas nativas do macOS.
- **Navegador SFTP Integrado:** Interface gráfica lateral para explorar o sistema de arquivos remoto, permitindo upload e download via *drag & drop*.
- **Importação de Configurações:** Importação fácil e rápida dos seus hosts a partir do arquivo `~/.ssh/config`.
- **Personalização:** Escolha entre diversos temas predefinidos (Dracula, Solarized, One Dark, etc.) e configure a fonte e o tamanho do seu terminal.

## 🛠 Stack Tecnológica

- **Linguagem:** Swift 5.9+ (com suporte a Swift Concurrency `async/await`)
- **Interface:** SwiftUI (Principal) + AppKit (NSViewRepresentable para o Terminal)
- **Emulador de Terminal:** [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
- **Motor SSH:** [SwiftNIO-SSH](https://github.com/apple/swift-nio-ssh)
- **Persistência de Dados:** [GRDB](https://github.com/groue/GRDB.swift) (SQLite) com **SQLCipher** (criptografia em repouso)
- **Gestão de Segredos:** Apple Security Framework (Keychain Services)

## 🏗 Arquitetura

O projeto foi construído seguindo os princípios da **Clean Architecture** e o padrão **MVVM**, garantindo alta testabilidade e separação de responsabilidades. O código está estruturado nas seguintes camadas principais:

- **Domain (`/Domain`):** Entidades puras Swift (Sessões, Pastas, Perfis de Terminal) e casos de uso. Totalmente independentes de UI ou frameworks de terceiros.
- **Data (`/Data`):** Implementações concretas de persistência (GRDB/AppDatabase), rede (RealSSHEngine, SFTPClient) e segurança (KeychainService).
- **Presentation (`/Presentation`):** Camada visual em SwiftUI contendo Views (Sidebar, Detail, Settings) e ViewModels responsáveis pela reatividade da interface.

## 🚀 Como Executar o Projeto (Desenvolvimento)

### Pré-requisitos
- macOS 13.0 (Ventura) ou superior
- Xcode 15.0 ou superior
- [CocoaPods](https://cocoapods.org/) instalado

### Passos para Compilação

1. Clone o repositório em sua máquina local:
   ```bash
   git clone https://github.com/seu-usuario/zetssh.git
   cd zetssh
   ```

2. Instale as dependências via CocoaPods:
   ```bash
   pod install
   ```

3. Abra o Workspace gerado no Xcode:
   ```bash
   open zetssh.xcworkspace
   ```
   *(Nota: Sempre abra o `.xcworkspace` e não o `.xcodeproj` para que as dependências do Pod sejam carregadas corretamente)*

4. Aguarde a resolução dos pacotes do Swift Package Manager (SPM).
5. Selecione o target `zetssh` e execute (`Cmd + R`).

## 🗺 Roadmap de Desenvolvimento

O ZetSSH está em constante evolução. Abaixo estão algumas das etapas de desenvolvimento:

- [x] Conectividade SSH2 e emulação de terminal interativo
- [x] CRUD de Sessões e Pastas (GRDB)
- [x] Autenticação com Chave Privada
- [x] Navegação Multi-tab
- [x] Personalização de Temas e Fontes
- [x] Suporte a SFTP (Navegador de arquivos)
- [x] Banco de dados criptografado (SQLCipher)
- [x] Importação de `~/.ssh/config`
- [ ] Tunelamento (Local/Remoto/Dinâmico) e Port Forwarding
- [ ] Suporte a *Jump/Bastion Hosts*
- [ ] Sincronização de metadados via iCloud

## 📄 Licença

Este projeto é distribuído sob os termos da licença especificada no arquivo [LICENSE](file:///Users/zeitune/src/zetssh/LICENSE) na raiz do repositório.
