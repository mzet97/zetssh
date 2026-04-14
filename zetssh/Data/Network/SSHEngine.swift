import Foundation

public enum SSHConnectionError: Error {
    case authenticationFailed
    case hostKeyMismatch      // fingerprint mudou
    case hostRejected         // usuário cancelou conexão com host desconhecido
    case alreadyConnecting    // engine não está idle
    case networkTimeout
    case unknown
}

public protocol SSHEngine {
    func connect(host: String, port: Int, username: String) async throws
    func authenticate(password: String) async throws
    func authenticate(privateKeyPath: URL, passphrase: String?) async throws
    func disconnect()
}

public final class LibSSH2WrapperMock: SSHEngine {
    public init() {}
    
    public func connect(host: String, port: Int, username: String) async throws {
        AppLogger.shared.log("Iniciando conexão (Mock) com \(host):\(port)...", category: .network, level: .info)
        // Simulando delay de rede
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    public func authenticate(password: String) async throws {
        AppLogger.shared.log("Autenticando via senha (Mock)...", category: .security, level: .info)
        // Simulando auth
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    public func authenticate(privateKeyPath: URL, passphrase: String?) async throws {
        AppLogger.shared.log("Autenticando via chave privada (Mock) em \(privateKeyPath.path)...", category: .security, level: .info)
        // Simulando auth
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    public func disconnect() {
        AppLogger.shared.log("Desconectando (Mock)...", category: .network, level: .info)
    }
}
