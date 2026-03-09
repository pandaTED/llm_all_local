import Foundation

#if canImport(llama)
import llama
#elseif canImport(LlamaSwift)
import LlamaSwift
#endif

actor LlamaService {
#if canImport(llama) || canImport(LlamaSwift)
    private var context: OpaquePointer?
    private var model: OpaquePointer?
    private var vocab: OpaquePointer?
#endif
    private var decodeBatchSize: Int32 = 512
    private(set) var session: InferenceSession?

    func loadModel(at path: String, contextLength: Int32 = 4096) throws {
#if canImport(llama) || canImport(LlamaSwift)
        unloadModel()

        llama_backend_init()

        var modelParams = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#else
        modelParams.n_gpu_layers = 999
#endif

        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed(path: path)
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextLength)
        contextParams.n_batch = 512

        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw LlamaError.contextCreationFailed
        }

        guard let loadedVocab = llama_model_get_vocab(loadedModel) else {
            llama_free(loadedContext)
            llama_model_free(loadedModel)
            throw LlamaError.vocabUnavailable
        }

        model = loadedModel
        context = loadedContext
        vocab = loadedVocab
        decodeBatchSize = Int32(contextParams.n_batch)
        session = InferenceSession(
            modelPath: path,
            modelName: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            contextLength: contextLength,
            loadedAt: Date()
        )
#else
        throw LlamaError.runtimeUnavailable
#endif
    }

    func chat(
        messages: [ChatMessage],
        systemPrompt: String,
        temperature: Float,
        maxTokens: Int
    ) throws -> AsyncThrowingStream<String, Error> {
#if canImport(llama) || canImport(LlamaSwift)
        guard
            let context,
            let vocab,
            let session
        else {
            throw LlamaError.modelNotLoaded
        }

        let prompt = buildChatPrompt(messages: messages, systemPrompt: systemPrompt)
        let promptTokens = tokenize(text: prompt, vocab: vocab, addBos: true)

        if promptTokens.isEmpty {
            throw LlamaError.emptyPrompt
        }

        if promptTokens.count >= session.contextLength {
            throw LlamaError.contextLimitReached
        }

        let decodeBatchSize = self.decodeBatchSize

        return AsyncThrowingStream { continuation in
            let stream = StreamContinuationController(continuation)

            let worker = Task(priority: .userInitiated) {
                defer {
                    llama_memory_clear(llama_get_memory(context), false)
                }

                do {
                    try Self.prefill(
                        context: context,
                        promptTokens: promptTokens,
                        maxBatchTokens: decodeBatchSize
                    )
                    let sampler = try Self.makeSampler(temperature: temperature)
                    defer { llama_sampler_free(sampler) }

                    var generatedCount = 0
                    var currentPosition = Int32(promptTokens.count)
                    var pendingInvalidUTF8: [CChar] = []

                    while generatedCount < maxTokens {
                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        let token = llama_sampler_sample(sampler, context, -1)
                        llama_sampler_accept(sampler, token)

                        if llama_vocab_is_eog(vocab, token) {
                            break
                        }

                        let pieceChars = Self.tokenToPiece(token: token, vocab: vocab)
                        pendingInvalidUTF8.append(contentsOf: pieceChars)

                        if let string = String(validatingUTF8: pendingInvalidUTF8 + [0]) {
                            pendingInvalidUTF8.removeAll(keepingCapacity: true)
                            if let stopRange = string.range(of: "<|im_end|>") {
                                let trimmed = String(string[..<stopRange.lowerBound])
                                if !trimmed.isEmpty {
                                    stream.yield(trimmed)
                                }
                                break
                            }

                            if string.contains("<|im_start|>") || string.contains("<|endoftext|>") {
                                break
                            }

                            stream.yield(string)
                        }

                        var nextBatch = llama_batch_init(1, 0, 1)
                        defer { llama_batch_free(nextBatch) }

                        nextBatch.n_tokens = 0
                        nextBatch.token[Int(nextBatch.n_tokens)] = token
                        nextBatch.pos[Int(nextBatch.n_tokens)] = currentPosition
                        nextBatch.n_seq_id[Int(nextBatch.n_tokens)] = 1
                        nextBatch.seq_id[Int(nextBatch.n_tokens)]?[0] = 0
                        nextBatch.logits[Int(nextBatch.n_tokens)] = 1
                        nextBatch.n_tokens += 1

                        if llama_decode(context, nextBatch) != 0 {
                            throw LlamaError.decodeFailed
                        }

                        currentPosition += 1
                        generatedCount += 1

                        if currentPosition >= Int32(session.contextLength - 1) {
                            throw LlamaError.contextLimitReached
                        }
                    }

                    if !pendingInvalidUTF8.isEmpty {
                        let flushed = String(cString: pendingInvalidUTF8 + [0])
                        if !flushed.isEmpty {
                            stream.yield(flushed)
                        }
                    }

                    stream.finish()
                } catch is CancellationError {
                    stream.finish()
                } catch {
                    stream.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
        }
#else
        throw LlamaError.runtimeUnavailable
#endif
    }

    func unloadModel() {
#if canImport(llama) || canImport(LlamaSwift)
        if let context {
            llama_free(context)
        }
        if let model {
            llama_model_free(model)
        }

        context = nil
        model = nil
        vocab = nil
        decodeBatchSize = 512
        session = nil
        llama_backend_free()
#else
        session = nil
#endif
    }

    private func buildChatPrompt(messages: [ChatMessage], systemPrompt: String) -> String {
#if canImport(llama) || canImport(LlamaSwift)
        if let model, let templated = buildPromptFromModelTemplate(model: model, messages: messages, systemPrompt: systemPrompt) {
            return templated
        }
#endif

        var prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"

        for message in messages {
            switch message.role {
            case .system:
                continue
            case .user:
                prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
            case .assistant:
                prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
            }
        }

        prompt += "<|im_start|>assistant\n"
        return prompt
    }

#if canImport(llama) || canImport(LlamaSwift)
    private func buildPromptFromModelTemplate(
        model: OpaquePointer,
        messages: [ChatMessage],
        systemPrompt: String
    ) -> String? {
        let template = llama_model_chat_template(model, nil)
        guard template != nil else {
            return nil
        }

        var cStrings: [UnsafeMutablePointer<CChar>] = []
        defer {
            cStrings.forEach { free($0) }
        }

        func makeCString(_ value: String) -> UnsafeMutablePointer<CChar>? {
            guard let ptr = strdup(value) else { return nil }
            cStrings.append(ptr)
            return ptr
        }

        var chat: [llama_chat_message] = []

        if let role = makeCString("system"), let content = makeCString(systemPrompt) {
            chat.append(llama_chat_message(role: UnsafePointer(role), content: UnsafePointer(content)))
        } else {
            return nil
        }

        for message in messages where !message.content.isEmpty {
            let roleString: String
            switch message.role {
            case .system:
                roleString = "system"
            case .user:
                roleString = "user"
            case .assistant:
                roleString = "assistant"
            }

            guard let role = makeCString(roleString), let content = makeCString(message.content) else {
                return nil
            }
            chat.append(llama_chat_message(role: UnsafePointer(role), content: UnsafePointer(content)))
        }

        let estimatedChars = max(
            2048,
            systemPrompt.utf8.count + messages.reduce(0) { $0 + $1.content.utf8.count } * 3 + 512
        )
        var buffer = [CChar](repeating: 0, count: estimatedChars)

        let count = chat.withUnsafeBufferPointer { ptr in
            llama_chat_apply_template(
                template,
                ptr.baseAddress,
                ptr.count,
                true,
                &buffer,
                Int32(buffer.count)
            )
        }

        if count < 0 {
            return nil
        }

        if Int(count) >= buffer.count {
            var resized = [CChar](repeating: 0, count: Int(count) + 1)
            let second = chat.withUnsafeBufferPointer { ptr in
                llama_chat_apply_template(
                    template,
                    ptr.baseAddress,
                    ptr.count,
                    true,
                    &resized,
                    Int32(resized.count)
                )
            }
            guard second >= 0 else {
                return nil
            }
            return String(cString: resized)
        }

        return String(cString: buffer)
    }

    private func tokenize(text: String, vocab: OpaquePointer, addBos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let maxCount = utf8Count + (addBos ? 2 : 1)
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: maxCount)
        defer { tokens.deallocate() }

        let actual = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(maxCount), addBos, true)
        if actual <= 0 {
            return []
        }

        var result: [llama_token] = []
        result.reserveCapacity(Int(actual))

        for index in 0..<actual {
            result.append(tokens[Int(index)])
        }

        return result
    }

    private static func prefill(
        context: OpaquePointer,
        promptTokens: [llama_token],
        maxBatchTokens: Int32
    ) throws {
        let chunkSize = max(1, Int(maxBatchTokens))
        var start = 0

        while start < promptTokens.count {
            let end = min(start + chunkSize, promptTokens.count)
            let count = end - start
            var batch = llama_batch_init(Int32(count), 0, 1)
            batch.n_tokens = 0

            for index in start..<end {
                let localIndex = Int(batch.n_tokens)
                batch.token[localIndex] = promptTokens[index]
                batch.pos[localIndex] = Int32(index)
                batch.n_seq_id[localIndex] = 1
                batch.seq_id[localIndex]?[0] = 0
                batch.logits[localIndex] = 0
                batch.n_tokens += 1
            }

            if end == promptTokens.count {
                batch.logits[Int(batch.n_tokens) - 1] = 1
            }

            if llama_decode(context, batch) != 0 {
                llama_batch_free(batch)
                throw LlamaError.decodeFailed
            }

            llama_batch_free(batch)
            start = end
        }
    }

    private static func makeSampler(temperature: Float) throws -> UnsafeMutablePointer<llama_sampler> {
        let params = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(params) else {
            throw LlamaError.samplerCreationFailed
        }

        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(1234))

        return sampler
    }

    private static func tokenToPiece(token: llama_token, vocab: OpaquePointer) -> [CChar] {
        let smallBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: 8)
        smallBuffer.initialize(repeating: 0, count: 8)
        defer { smallBuffer.deallocate() }

        let size = llama_token_to_piece(vocab, token, smallBuffer, 8, 0, false)

        if size < 0 {
            let largeBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(-size))
            largeBuffer.initialize(repeating: 0, count: Int(-size))
            defer { largeBuffer.deallocate() }

            let outputSize = llama_token_to_piece(vocab, token, largeBuffer, -size, 0, false)
            return Array(UnsafeBufferPointer(start: largeBuffer, count: Int(outputSize)))
        }

        return Array(UnsafeBufferPointer(start: smallBuffer, count: Int(size)))
    }
#endif
}

private final class StreamContinuationController: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private let continuation: AsyncThrowingStream<String, Error>.Continuation

    init(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }

    func yield(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        continuation.yield(value)
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        continuation.finish()
    }

    func finish(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        continuation.finish(throwing: error)
    }
}

enum LlamaError: LocalizedError {
    case modelLoadFailed(path: String)
    case contextCreationFailed
    case vocabUnavailable
    case modelNotLoaded
    case decodeFailed
    case samplerCreationFailed
    case contextLimitReached
    case emptyPrompt
    case runtimeUnavailable

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load model at: \(path)"
        case .contextCreationFailed:
            return "Failed to create inference context."
        case .vocabUnavailable:
            return "Failed to obtain vocabulary from loaded model."
        case .modelNotLoaded:
            return "No model is currently loaded."
        case .decodeFailed:
            return "Inference failed while decoding tokens."
        case .samplerCreationFailed:
            return "Failed to create token sampler."
        case .contextLimitReached:
            return "Conversation reached the context limit."
        case .emptyPrompt:
            return "Prompt produced no tokens."
        case .runtimeUnavailable:
            return "llama runtime is unavailable. Add the llama Swift package dependency first."
        }
    }
}
