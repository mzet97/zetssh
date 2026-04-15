import Foundation

enum SFTPError: Error {
    case notConnected
    case permissionDenied
    case fileNotFound
    case transferFailed(String)
    case protocolError(String)
}

protocol SFTPEngine {
    func listDirectory(path: String) async throws -> [RemoteFileItem]
    func download(remotePath: String, to localURL: URL, progress: @escaping (Double) -> Void) async throws
    func upload(localURL: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws
    func createDirectory(path: String) async throws
    func delete(path: String) async throws
}
