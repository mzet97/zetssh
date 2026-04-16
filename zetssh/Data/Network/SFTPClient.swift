import Foundation
import NIOCore
@preconcurrency import NIOSSH

// MARK: - SFTPChannelHandler

final class SFTPChannelHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn  = SSHChannelData
    typealias InboundOut = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private var buffer = ByteBuffer()
    private var pendingReplies: [UInt32: CheckedContinuation<ByteBuffer, Error>] = [:]
    private let lock = NSLock()

    func register(requestId: UInt32, continuation: CheckedContinuation<ByteBuffer, Error>) {
        lock.lock(); defer { lock.unlock() }
        pendingReplies[requestId] = continuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buf) = channelData.data else { return }
        buffer.writeImmutableBuffer(buf)
        processBuffer()
    }

    private func processBuffer() {
        while buffer.readableBytes >= 9 {
            let length = buffer.getInteger(at: buffer.readerIndex, as: UInt32.self)!
            let packetSize = Int(length) + 4
            guard buffer.readableBytes >= packetSize else { break }
            var packet = buffer.readSlice(length: packetSize)!
            packet.moveReaderIndex(forwardBy: 4)
            guard let _ = packet.readInteger(as: UInt8.self),
                  let reqId  = packet.readInteger(as: UInt32.self) else { break }
            lock.lock()
            let cont = pendingReplies.removeValue(forKey: reqId)
            lock.unlock()
            cont?.resume(returning: packet)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buf = unwrapOutboundIn(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buf))
        context.write(wrapOutboundOut(channelData), promise: promise)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        lock.lock()
        let pending = pendingReplies
        pendingReplies.removeAll()
        lock.unlock()
        pending.values.forEach { $0.resume(throwing: error) }
        context.fireErrorCaught(error)
    }
}

// MARK: - SFTPClient
final class SFTPClient: SFTPEngine {

    private let channel: Channel
    private var requestId: UInt32 = 0
    private let lock = NSLock()
    private var currentListingPath = "/"

    init(channel: Channel) {
        self.channel = channel
    }

    // MARK: - SFTPEngine

    func listDirectory(path: String) async throws -> [RemoteFileItem] {
        currentListingPath = path
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
        return try await sendPacketAwaitNameList(type: 12, handle: handle, path: currentListingPath)
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

    // MARK: - NIO packet I/O

    private func sendPacket(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> ByteBuffer {
        let reqId = nextRequestId()
        var body = channel.allocator.buffer(capacity: 64)
        body.writeInteger(type)
        body.writeInteger(reqId)
        payload(&body)
        var packet = channel.allocator.buffer(capacity: body.readableBytes + 4)
        packet.writeInteger(UInt32(body.readableBytes))
        packet.writeImmutableBuffer(body)

        let reply: ByteBuffer = try await withCheckedThrowingContinuation { continuation in
            channel.pipeline.handler(type: SFTPChannelHandler.self).whenSuccess { handler in
                handler.register(requestId: reqId, continuation: continuation)
            }
            channel.writeAndFlush(packet, promise: nil)
        }
        return reply
    }

    private func sendPacketAwaitHandle(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> Data {
        var reply = try await sendPacket(type: type, payload: payload)
        guard let handleLength = reply.readInteger(as: UInt32.self),
              let handleBytes = reply.readBytes(length: Int(handleLength)) else {
            throw SFTPError.protocolError("Invalid handle response")
        }
        return Data(handleBytes)
    }

    private func sendPacketAwaitStatus(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> UInt32 {
        var reply = try await sendPacket(type: type, payload: payload)
        guard let code = reply.readInteger(as: UInt32.self) else {
            throw SFTPError.protocolError("Invalid status response")
        }
        guard code == 0 else {
            throw SFTPError.protocolError("SFTP status error: \(code)")
        }
        return code
    }

    private func sendPacketAwaitData(type: UInt8, payload: (inout ByteBuffer) -> Void) async throws -> Data {
        var reply = try await sendPacket(type: type, payload: payload)
        guard let dataLength = reply.readInteger(as: UInt32.self),
              let dataBytes = reply.readBytes(length: Int(dataLength)) else {
            throw SFTPError.protocolError("Invalid data response")
        }
        return Data(dataBytes)
    }

    private func sendPacketAwaitNameList(type: UInt8, handle: Data, path: String) async throws -> [RemoteFileItem] {
        var payload = channel.allocator.buffer(capacity: handle.count + 16)
        payload.writeSSHHandle(handle)
        var reply = try await sendPacket(type: type, payload: { buf in
            buf.writeBuffer(&payload)
        })
        guard let count = reply.readInteger(as: UInt32.self) else {
            throw SFTPError.protocolError("Invalid name list response")
        }
        var items: [RemoteFileItem] = []
        for _ in 0..<count {
            guard let nameLen = reply.readInteger(as: UInt32.self),
                  let nameBytes = reply.readBytes(length: Int(nameLen)),
                  let name = String(bytes: nameBytes, encoding: .utf8),
                  let longNameLen = reply.readInteger(as: UInt32.self)
            else { break }
            _ = reply.readSlice(length: Int(longNameLen))
            let _ = reply.readInteger(as: UInt32.self)
            let fullPath = path + (path.hasSuffix("/") ? "" : "/") + name
            items.append(RemoteFileItem(
                id: fullPath,
                name: name,
                path: fullPath,
                isDirectory: false,
                size: 0,
                modifiedAt: Date()
            ))
        }
        return items
    }

    private func sendPacketAwaitAttrs(type: UInt8, handle: Data) async throws -> UInt64 {
        var payload = channel.allocator.buffer(capacity: handle.count + 8)
        payload.writeSSHHandle(handle)
        var reply = try await sendPacket(type: type, payload: { buf in
            buf.writeBuffer(&payload)
        })
        let flags = reply.readInteger(as: UInt32.self) ?? 0
        if flags & 0x01 != 0 {
            return reply.readInteger(as: UInt64.self) ?? 0
        }
        return 0
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
