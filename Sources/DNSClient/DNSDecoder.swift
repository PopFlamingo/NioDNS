import NIO

final class EnvelopeInboundChannel: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias InboundOut = ByteBuffer
    
    init() {}
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data).data
        context.fireChannelRead(wrapInboundOut(buffer))
    }
}

final class DNSDecoder: ChannelInboundHandler {
    var messageCache = [UInt16: SentQuery]()
    var clients = [ObjectIdentifier: DNSClient]()
    weak var mainClient: DNSClient?

    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = Never
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        var buffer = envelope

        guard let header = buffer.readHeader() else {
            context.fireErrorCaught(ProtocolError())
            return
        }

        var questions = [QuestionSection]()

        for _ in 0..<header.questionCount {
            guard let question = buffer.readQuestion() else {
                context.fireErrorCaught(ProtocolError())
                return
            }

            questions.append(question)
        }

        func resourceRecords(count: UInt16) throws -> [Record] {
            var records = [Record]()

            for _ in 0..<count {
                guard let record = buffer.readRecord() else {
                    throw ProtocolError()
                }

                records.append(record)
            }

            return records
        }

        do {
            let answers = try resourceRecords(count: header.answerCount)
            let authorities = try resourceRecords(count: header.authorityCount)
            let additionalData = try resourceRecords(count: header.additionalRecordCount)
            
            let message = Message(
                header: header,
                questions: questions,
                answers: answers,
                authorities: authorities,
                additionalData: additionalData
            )

            guard let query = messageCache[header.id] else {
                throw UnknownQuery()
            }

            query.promise.succeed(message)
            messageCache[header.id] = nil
        } catch {
            messageCache[header.id]?.promise.fail(error)
            messageCache[header.id] = nil
            context.fireErrorCaught(error)
        }
    }

    func errorCaught(context ctx: ChannelHandlerContext, error: Error) {
        for query in self.messageCache.values {
            query.promise.fail(error)
        }

        messageCache = [:]
    }
}
