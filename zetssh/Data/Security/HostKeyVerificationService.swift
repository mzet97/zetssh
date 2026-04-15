import Foundation
import AppKit
import GRDB
import NIOSSH
import Crypto

enum HostKeyVerificationResult {
    case trusted       // host conhecido, fingerprint idêntica → OK
    case userAccepted  // host novo, usuário clicou "Confiar"
    case userRejected  // host novo, usuário cancelou
    case mismatch      // fingerprint mudou → conexão bloqueada
}

@MainActor
final class HostKeyVerificationService {
    static let shared = HostKeyVerificationService()
    private init() {}

    func verify(host: String, port: Int, key: NIOSSHPublicKey) async -> HostKeyVerificationResult {
        let algo = keyAlgorithm(key)
        let fp   = keyFingerprint(key)
        AppLogger.shared.log("[HostKey] verify() chamado: \(host):\(port) algo=\(algo)", category: .security, level: .info)

        do {
            let existing = try await AppDatabase.shared.dbWriter.read { db in
                try KnownHost
                    .filter(Column("host")      == host)
                    .filter(Column("port")      == port)
                    .filter(Column("algorithm") == algo)
                    .fetchOne(db)
            }

            if let known = existing {
                if known.fingerprint == fp {
                    AppLogger.shared.log("[HostKey] Host conhecido e confiável.", category: .security, level: .info)
                    return .trusted
                }
                AppLogger.shared.log("[HostKey] MISMATCH de fingerprint!", category: .security, level: .error)
                await showMismatchAlert(host: host, port: port,
                                        oldFP: known.fingerprint, newFP: fp)
                return .mismatch
            }
            AppLogger.shared.log("[HostKey] Host novo — auto-aceitando.", category: .security, level: .info)
        } catch {
            AppLogger.shared.log("[HostKey] KnownHost lookup erro: \(error)", category: .security, level: .error)
        }

        // Auto-aceitar host desconhecido (comportamento igual ao OpenSSH StrictHostKeyChecking=accept-new)
        // NSAlert.runModal() não funciona em contexto async no macOS 26; o aviso é exibido no terminal.
        let shortFP = String(fp.prefix(32))
        AppLogger.shared.log(
            "Host '\(host):\(port)' adicionado aos known hosts (\(algo) \(shortFP)...)",
            category: .security, level: .warning
        )
        terminalWarning = """
\r\nAVISO: A autenticidade de '\(host):\(port)' não pôde ser estabelecida.\r
Algoritmo:  \(algo)\r
SHA256:     \(shortFP)...\r
Host adicionado permanentemente à lista de known hosts.\r\n
"""
        let record = KnownHost(host: host, port: port, algorithm: algo,
                               fingerprint: fp, addedAt: Date())
        try? await AppDatabase.shared.dbWriter.write { db in try record.save(db) }
        return .userAccepted
    }

    /// Texto de aviso a ser exibido no terminal após conexão bem-sucedida.
    private(set) var terminalWarning: String? = nil

    /// Limpa o aviso pendente e o retorna (chame após exibir no terminal).
    func consumeTerminalWarning() -> String? {
        let w = terminalWarning
        terminalWarning = nil
        return w
    }

    // MARK: - Key Helpers

    private func keyAlgorithm(_ key: NIOSSHPublicKey) -> String {
        let desc = String(describing: key)
        return desc.components(separatedBy: " ").first ?? "unknown"
    }

    private func keyFingerprint(_ key: NIOSSHPublicKey) -> String {
        let data   = Data(String(describing: key).utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Mismatch (fingerprint mudou — bloqueio de segurança)

    private func showMismatchAlert(host: String, port: Int,
                                   oldFP: String, newFP: String) async {
        // Registrar nos logs; exibir aviso via terminal em vez de NSAlert.runModal()
        AppLogger.shared.log(
            "ALERTA SEGURANÇA: fingerprint de '\(host):\(port)' mudou! Esperado=\(oldFP.prefix(16))... Recebido=\(newFP.prefix(16))...",
            category: .security, level: .error
        )
        terminalWarning = """
\r\n⚠️  ALERTA: A fingerprint de '\(host):\(port)' mudou!\r
   Esperado: \(oldFP.prefix(32))...\r
   Recebido: \(newFP.prefix(32))...\r
   Possível ataque man-in-the-middle. Conexão bloqueada.\r\n
"""
    }
}
