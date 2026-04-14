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

        do {
            let existing = try await AppDatabase.shared.dbWriter.read { db in
                try KnownHost
                    .filter(Column("host")      == host)
                    .filter(Column("port")      == port)
                    .filter(Column("algorithm") == algo)
                    .fetchOne(db)
            }

            if let known = existing {
                if known.fingerprint == fp { return .trusted }
                await showMismatchAlert(host: host, port: port,
                                        oldFP: known.fingerprint, newFP: fp)
                return .mismatch
            }
        } catch {
            AppLogger.shared.log("KnownHost lookup: \(error)", category: .security, level: .error)
        }

        let accepted = await showUnknownHostAlert(host: host, port: port, algo: algo, fingerprint: fp)
        if accepted {
            let record = KnownHost(host: host, port: port, algorithm: algo,
                                   fingerprint: fp, addedAt: Date())
            try? await AppDatabase.shared.dbWriter.write { db in try record.save(db) }
            return .userAccepted
        }
        return .userRejected
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

    // MARK: - NSAlert Helpers

    private func showUnknownHostAlert(host: String, port: Int,
                                      algo: String, fingerprint: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Host Desconhecido"
            alert.informativeText = """
            A autenticidade de '\(host):\(port)' não pôde ser estabelecida.

            Algoritmo:   \(algo)
            SHA256:      \(fingerprint.prefix(32))...

            Deseja confiar neste host e continuar?
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Confiar e Conectar")
            alert.addButton(withTitle: "Cancelar")
            continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
        }
    }

    private func showMismatchAlert(host: String, port: Int,
                                   oldFP: String, newFP: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let alert = NSAlert()
            alert.messageText = "ALERTA: Fingerprint do host mudou!"
            alert.informativeText = """
            A fingerprint de '\(host):\(port)' é diferente da armazenada.

            Esperado: \(oldFP.prefix(32))...
            Recebido: \(newFP.prefix(32))...

            Isso pode indicar um ataque man-in-the-middle.
            A conexão foi bloqueada por segurança.
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            c.resume()
        }
    }
}
