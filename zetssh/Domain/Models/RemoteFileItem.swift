import Foundation

struct RemoteFileItem: Identifiable, Hashable {
    let id: String  // caminho completo como ID único
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modifiedAt: Date

    var displaySize: String {
        isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
