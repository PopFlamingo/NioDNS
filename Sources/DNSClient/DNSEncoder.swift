import NIO

final class EnvelopeOutboundChannel: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    
    let address: SocketAddress
    
    init(address: SocketAddress) {
        self.address = address
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        let envelope = AddressedEnvelope(remoteAddress: address, data: buffer)
        context.write(wrapOutboundOut(envelope), promise: promise)
    }
}

final class UInt16FrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer
    
    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard
            let size: UInt16 = buffer.readInteger(),
            let slice = buffer.readSlice(length: Int(size))
        else {
            return .needMoreData
        }
        context.fireChannelRead(wrapInboundOut(slice))
        return .continue
    }
    
    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        try decode(context: context, buffer: &buffer)
    }
}

final class UInt16FrameEncoder: MessageToByteEncoder {
    func encode(data: ByteBuffer, out: inout ByteBuffer) throws {
        try out.writeLengthPrefixed(as: UInt16.self) { out in
            out.writeImmutableBuffer(data)
        }
    }
}

final class DNSEncoder: ChannelOutboundHandler {
    typealias OutboundIn = Message
    typealias OutboundOut = ByteBuffer
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        let data = DNSEncoder.encodeMessage(message, allocator: context.channel.allocator)

        context.write(wrapOutboundOut(data), promise: promise)
    }
    
    static func encodeMessage(_ message: Message, allocator: ByteBufferAllocator) -> ByteBuffer {
        var out = allocator.buffer(capacity: 512)

        let header = message.header

        out.write(header)

        for question in message.questions {
            for label in question.labels {
                out.writeInteger(label.length, endianness: .big)
                out.writeBytes(label.label)
            }

            out.writeInteger(0, endianness: .big, as: UInt8.self)
            out.writeInteger(question.type.rawValue, endianness: .big)
            out.writeInteger(question.questionClass.rawValue, endianness: .big)
        }

        return out
    }
}
