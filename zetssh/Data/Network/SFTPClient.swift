import Foundation
import NIOCore
@preconcurrency import NIOSSH

/// Implementa SFTPv3 (draft-ietf-secsh-filexfer v3) sobre um canal NIOSSH.
/// Os primitivos de baixo nível são stubs — integração NIO completa em fase futura.
final class SFTPClient: SFTPEngine {

    private let channel: Channel
    private var requestId: UInt32 = 0
    private let lock = NSLock()

    init(channel: Channel) {
        self.channel = channel
    }

    // MARK: - SFTPEngine

    func listDirectory(path: String) async throws -> [RemoteFileItem] {
        let handle = try await openDir(path: path)
        defer { Task { try? await closeHandle(handle) } }

        var items: [RemoteFileItem] = []
        while true {
            let batch = try await readDir(handle: handle)
            if batch.isEmpty { break }
            items.append(contentsOf: batch)
        }
        return items.filter { $0.name != "." && $0.name != ".." }
    }

    func download(remotePath: String, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        let handle = try await openFile(path: remotePath, flags: 0x01) // SSH_FXF_READ
        defer { Task { try? await closeHandle(handle) } }

        let totalSize = try await statHandle(handle: handle)
        var offset: UInt64 = 0
        let chunkSize: UInt32 = 32768

        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: localURL)
        defer { try? fileHandle.close() }

        while offset < totalSize {
            let data = try await readData(handle: handle, offset: offset, length: chunkSize)
            if data.isEmpty { break }
            fileHandle.write(data)
            offset += UInt64(data.count)
            progress(totalSize > 0 ? Double(offset) / Double(totalSize) : 1.0)
        }
    }

    func upload(localURL: URL, to remotePath: String, progress: @escaping (Double) -> Void) async throws {
        let localData = try Data(contentsOf: localURL)
        let handle = try await openFile(path: remotePath, flags: 0x1A) // WRITE|CREAT|TRUNC
        defer { Task { try? await closeHandle(handle) } }

        let chunkSize = 32768
        var offset = 0
        let total = localData.count

        while offset < total {
            let end = min(offset + chunkSize, total)
            let chunk = localData[offset..<end]
            try await writeData(handle: handle, offset: UInt64(offset), data: Data(chunk))
            offset = end
            progress(total > 0 ? Double(offset) / Double(total) : 1.0)
        }
    }

    func createDirectory(path: String) async throws {
        try await sendMkdir(path: path)
    }

    func delete(path: String) async throws {
        try await sendRemove(path: path)
    }

    // MARK: - Private SFTP primitives

    private func nextRequestId() -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        requestId += 1
        return requestId
    }

    private func openDir(path: String) async throws -> Data {
        return try await sendPacketAwaitHandle(type: 11, payload: { buf in
            buf.writeSSHString(path)
        })
    }

    private func readDir(handle: Data) async throws -> [RemoteFileItem] {
        return try await sendPacketAwaitNameList(type: 12, handle: handle)
    }

    private func closeHandle(_ handle: Data) async throws {
        _ = try await sendPacketAwaitStatus(type: 4, payload: { buf in
            buf.writeSSHHandle(handle)
        })
    }

    private func openFile(path: String, flags: UInt32) async throws -> Data {
        return try await sendPacketAwaitHandle(type: 3, payload: { buf in
            buf.writeSSHString(path)
            buf.writeInteger(flags)
            buf.writeInteger(UInt32(0))
        })
    }

    private func statHandle(handle: Data) async throws -> UInt64 {
        return try await sendPacketAwaitAttrs(type: 8, handle: handle)
    }

    private func readData(handle: Data, offset: UInt64, length: UInt32) async throws -> Data {
        return try await sendPacketAwaitData(type: 5, payload: { buf in
            buf.writeSSHHandle(handle)
            buf.writeInteger(offset)
            buf.writeInteger(length)
        })
    }

    private func writeData(handle: Data, offset: UInt64, data: Data) async throws {
        _ = try await sendPacketAwaitStatus(type: 6, payload: { buf in
            buf.writeSSHHandle(handle)
            buf.writeInteger(offset)
            buf.writeSSHData(data)
        })
    }

    private func sendMkdir(path: String) async throws {
        _ = try await sendPacketAwaitStatus(type: 14, payload: { buf in
            buf.writeSSHString(path)
            buf.writeInteger(UInt32(0))
        })
    }

    private func sendRemove(path: String) async throws {
        _ = try await sendPacketAwaitStatus(type: 13, payload: { buf in
            buf.writeSSHString(path)
        })
    }

    // MARK: - NIO stubs (integração futura)

    private func sendPacketAwaitHandle(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> Data {
        throw SFTPError.protocolError("SFTP NIO integration not yet complete")
    }

    private func sendPacketAwaitStatus(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> UInt32 {
        throw SFTPError.protocolError("SFTP NIO integration not yet complete")
    }

    private func sendPacketAwaitData(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> Data {
        throw SFTPError.protocolError("SFTP NIO integration not yet complete")
    }

    private func sendPacketAwaitNameList(type: UInt8, handle: Data) async throws -> [RemoteFileItem] {
        throw SFTPError.protocolError("SFTP NIO integration not yet complete")
    }

    private func sendPacketAwaitAttrs(type: UInt8, handle: Data) async throws -> UInt64 {
        throw SFTPError.protocolError("SFTP NIO integration not yet complete")
    }
}

// MARK: - ByteBuffer helpers

private extension ByteBuffer {
    mutating func writeSSHString(_ s: String) {
        let bytes = Array(s.utf8)
        writeInteger(UInt32(bytes.count))
        writeBytes(bytes)
    }

    mutating func writeSSHHandle(_ data: Data) {
        writeInteger(UInt32(data.count))
        writeBytes(data)
    }

    mutating func writeSSHData(_ data: Data) {
        writeInteger(UInt32(data.count))
        writeBytes(data)
    }
}
