import Foundation

public enum SSHConnectionError: Error {
    case authenticationFailed
    case hostKeyMismatch      // fingerprint mudou
    case hostRejected         // usuário cancelou conexão com host desconhecido
    case alreadyConnecting    // engine não está idle
    case networkTimeout
    case connectionTimedOut   // servidor parou de responder (keepalive expirado)
    case unknown
}

extension SSHConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:  return "Autenticação SSH falhou"
        case .hostKeyMismatch:       return "Chave do host mudou (possível ataque MITM)"
        case .hostRejected:          return "Conexão rejeitada pelo usuário"
        case .alreadyConnecting:     return "Conexão já em andamento"
        case .networkTimeout:        return "Timeout de rede ao conectar"
        case .connectionTimedOut:    return "Servidor não respondeu — conexão encerrada"
        case .unknown:               return "Erro SSH desconhecido"
        }
    }
}

public protocol SSHEngine {
    func connect(host: String, port: Int, username: String) async throws
    func authenticate(password: String) async throws
    func authenticate(privateKeyPath: URL, passphrase: String?) async throws
    func disconnect()
    func sendData(_ data: [UInt8])
    func resize(cols: Int, rows: Int)
    var isConnected: Bool { get }
    var isConnecting: Bool { get }
}

#if DEBUG
public final class LibSSH2WrapperMock: SSHEngine {
    public init() {}
    public func connect(host: String, port: Int, username: String) async throws {}
    public func authenticate(password: String) async throws {}
    public func authenticate(privateKeyPath: URL, passphrase: String?) async throws {}
    public func disconnect() {}
    public func sendData(_ data: [UInt8]) {}
    public func resize(cols: Int, rows: Int) {}
    public var isConnected: Bool { false }
    public var isConnecting: Bool { false }
}
#endif
