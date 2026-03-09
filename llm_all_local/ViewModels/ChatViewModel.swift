import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var conversations: [ChatConversation] = []
    @Published var activeConversationID: UUID?

    @Published var inputText: String = ""
    @Published var pendingAttachments: [ChatAttachment] = []

    @Published var isGenerating: Bool = false
    @Published var isModelLoading: Bool = false
    @Published var modelLoadError: String?
    @Published var isModelLoaded: Bool = false
    @Published var selectedModelName: String = "No Model"
    @Published var memoryWarningBanner: String?

    @Published var generationStats: GenerationStats = .empty
    @Published var generationSpeedHistory: [Double] = []
    @Published var resourceSamples: [ResourceSample] = []

    @Published var systemPrompt: String
    @Published var contextLength: Int
    @Published var temperature: Double
    @Published var allowsCellularDownloads: Bool

    private let llamaService = LlamaService()
    private let defaults: UserDefaults
    private let conversationStore = ConversationStore()
    private let imageReasoningService = ImageReasoningService()
    private let resourceMonitor = ResourceMonitorService()

    private var generationTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private enum Keys {
        static let systemPrompt = "chat.systemPrompt"
        static let contextLength = "chat.contextLength"
        static let temperature = "chat.temperature"
        static let allowsCellularDownloads = "models.allowsCellularDownloads"
        static let selectedModelPath = "models.selectedPath"
        static let selectedModelName = "models.selectedName"
        static let hasCompletedOnboarding = "onboarding.completed"
        static let activeConversationID = "chat.activeConversationID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? "You are a helpful, harmless, and honest AI assistant."

        let storedContextLength = defaults.integer(forKey: Keys.contextLength)
        self.contextLength = storedContextLength > 0 ? storedContextLength : 4096

        let storedTemperature = defaults.object(forKey: Keys.temperature) as? Double
        self.temperature = storedTemperature ?? 0.7

        if defaults.object(forKey: Keys.allowsCellularDownloads) == nil {
            defaults.set(false, forKey: Keys.allowsCellularDownloads)
        }
        self.allowsCellularDownloads = defaults.bool(forKey: Keys.allowsCellularDownloads)

        if let name = defaults.string(forKey: Keys.selectedModelName), !name.isEmpty {
            selectedModelName = name
        }

        registerLifecycleObservers()
        startResourceMonitor()

        Task {
            await bootstrapConversations()
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        resourceMonitor.stop()
    }

    var shouldShowOnboarding: Bool {
        !defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    var activeConversationTitle: String {
        conversations.first(where: { $0.id == activeConversationID })?.title ?? "New Chat"
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: Keys.hasCompletedOnboarding)
    }

    func updateSystemPrompt(_ value: String) {
        systemPrompt = value
        defaults.set(value, forKey: Keys.systemPrompt)
    }

    func updateContextLength(_ value: Int) {
        contextLength = max(1024, min(8192, value))
        defaults.set(contextLength, forKey: Keys.contextLength)
    }

    func updateTemperature(_ value: Double) {
        temperature = min(2.0, max(0.0, value))
        defaults.set(temperature, forKey: Keys.temperature)
    }

    func updateAllowsCellularDownloads(_ value: Bool) {
        allowsCellularDownloads = value
        defaults.set(value, forKey: Keys.allowsCellularDownloads)
    }

    func loadModel(at path: String, displayName: String? = nil) async {
        isModelLoading = true
        modelLoadError = nil

        defer { isModelLoading = false }

        do {
            try await llamaService.loadModel(at: path, contextLength: Int32(contextLength))
            isModelLoaded = true
            selectedModelName = displayName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            defaults.set(path, forKey: Keys.selectedModelPath)
            defaults.set(selectedModelName, forKey: Keys.selectedModelName)
            markOnboardingCompleted()
        } catch {
            isModelLoaded = false
            modelLoadError = error.localizedDescription
            appendSystemMessage("⚠️ \(error.localizedDescription)")
        }
    }

    func unloadModel() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        Task {
            await llamaService.unloadModel()
        }
        isModelLoaded = false
        selectedModelName = "No Model"
        defaults.removeObject(forKey: Keys.selectedModelPath)
        defaults.removeObject(forKey: Keys.selectedModelName)
        endBackgroundTaskIfNeeded()
        resourceMonitor.setInferenceState(active: false, tokensPerSecond: 0)
    }

    func addPendingImage(_ image: UIImage) {
        Task {
            do {
                let attachment = try await imageReasoningService.createAttachment(from: image)
                await MainActor.run {
                    self.pendingAttachments.append(attachment)
                }
            } catch {
                await MainActor.run {
                    self.appendSystemMessage("⚠️ Failed to process image: \(error.localizedDescription)")
                }
            }
        }
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments

        guard !(userText.isEmpty && attachments.isEmpty) else { return }
        guard !isGenerating else { return }
        guard isModelLoaded else {
            appendSystemMessage("⚠️ No model loaded. Open Model Manager to choose a model.")
            return
        }

        inputText = ""
        pendingAttachments = []

        let augmentation = buildImageAugmentation(attachments)
        let visibleUserContent = userText.isEmpty ? "[Image]" : userText

        let userMessage = ChatMessage(
            role: .user,
            content: visibleUserContent,
            attachments: attachments,
            inferenceAugmentation: augmentation
        )
        messages.append(userMessage)
        trimContextIfNeeded()
        syncActiveConversation()

        var assistantMessage = ChatMessage(role: .assistant, content: "")
        assistantMessage.isGenerating = true
        messages.append(assistantMessage)
        let assistantID = assistantMessage.id

        isGenerating = true
        generationStats = .empty
        let generationStartedAt = Date()

        generationTask = Task {
            var firstTokenAt: Date?
            var tokenCount = 0

            do {
                let promptMessages = messages
                    .filter { $0.id != assistantID }
                    .map { message -> ChatMessage in
                        var copy = message
                        copy.content = message.contentForInference()
                        copy.isGenerating = false
                        return copy
                    }

                let stream = try await llamaService.chat(
                    messages: promptMessages,
                    systemPrompt: systemPrompt,
                    temperature: Float(temperature),
                    maxTokens: 2048
                )

                for try await token in stream {
                    if Task.isCancelled { break }
                    guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { continue }

                    messages[index].content += token
                    tokenCount += 1

                    let now = Date()
                    if firstTokenAt == nil {
                        firstTokenAt = now
                        generationStats.firstTokenLatencyMs = now.timeIntervalSince(generationStartedAt) * 1000
                    }

                    if let firstTokenAt {
                        let elapsed = max(now.timeIntervalSince(firstTokenAt), 0.001)
                        generationStats.tokensPerSecond = Double(tokenCount) / elapsed
                    }

                    generationStats.generatedTokenCount = tokenCount
                    generationStats.lastUpdatedAt = now

                    resourceMonitor.setInferenceState(active: true, tokensPerSecond: generationStats.tokensPerSecond)
                    syncActiveConversation()
                }
            } catch is CancellationError {
                // user initiated cancel
            } catch {
                appendSystemMessage("⚠️ \(friendlyErrorMessage(for: error))")
            }

            if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].isGenerating = false
                if messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages[index].content = "[No output]"
                }
            }

            isGenerating = false
            generationTask = nil
            endBackgroundTaskIfNeeded()
            resourceMonitor.setInferenceState(active: false, tokensPerSecond: generationStats.tokensPerSecond)
            syncActiveConversation()
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil

        if let index = messages.indices.last, messages[index].role == .assistant {
            messages[index].isGenerating = false
        }

        isGenerating = false
        endBackgroundTaskIfNeeded()
        resourceMonitor.setInferenceState(active: false, tokensPerSecond: generationStats.tokensPerSecond)
        syncActiveConversation()
    }

    func clearChat() {
        stopGeneration()
        createNewConversation()
    }

    func createNewConversation() {
        let conversation = ChatConversation()
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        defaults.set(conversation.id.uuidString, forKey: Keys.activeConversationID)
        messages = []
        pendingAttachments = []
        persistConversations()
    }

    func selectConversation(id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        stopGeneration()
        activeConversationID = id
        defaults.set(id.uuidString, forKey: Keys.activeConversationID)
        messages = conversation.messages
        pendingAttachments = []
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }

        if conversations.isEmpty {
            createNewConversation()
            return
        }

        if activeConversationID == id {
            let fallback = conversations[0]
            activeConversationID = fallback.id
            defaults.set(fallback.id.uuidString, forKey: Keys.activeConversationID)
            messages = fallback.messages
        }

        persistConversations()
    }

    private func bootstrapConversations() async {
        let loaded = await conversationStore.loadConversations()

        if loaded.isEmpty {
            createNewConversation()
            return
        }

        conversations = loaded.sorted(by: { $0.updatedAt > $1.updatedAt })

        if
            let storedID = defaults.string(forKey: Keys.activeConversationID),
            let uuid = UUID(uuidString: storedID),
            let existing = conversations.first(where: { $0.id == uuid })
        {
            activeConversationID = existing.id
            messages = existing.messages
        } else if let first = conversations.first {
            activeConversationID = first.id
            defaults.set(first.id.uuidString, forKey: Keys.activeConversationID)
            messages = first.messages
        }
    }

    private func syncActiveConversation() {
        guard let id = activeConversationID, let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        conversations[index].messages = messages
        conversations[index].updatedAt = Date()

        if let title = firstUserTitle(in: messages) {
            conversations[index].title = title
        }

        conversations.sort(by: { $0.updatedAt > $1.updatedAt })
        persistConversations()
    }

    private func persistConversations() {
        let snapshot = conversations
        Task {
            await conversationStore.saveConversations(snapshot)
        }
    }

    private func firstUserTitle(in messages: [ChatMessage]) -> String? {
        guard let text = messages.first(where: { $0.role == .user })?.content else {
            return nil
        }

        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else {
            return nil
        }

        return String(compact.prefix(36))
    }

    private func startResourceMonitor() {
        resourceMonitor.start(interval: 1.0) { [weak self] snapshot in
            guard let self else { return }

            let point = ResourceSample(
                timestamp: snapshot.timestamp,
                cpuPercent: snapshot.cpuPercent,
                memoryPercent: snapshot.memoryPercent,
                memoryMB: snapshot.memoryMB,
                gpuPercent: snapshot.gpuPercent,
                npuPercent: snapshot.npuPercent
            )

            self.resourceSamples.append(point)
            if self.resourceSamples.count > 90 {
                self.resourceSamples.removeFirst(self.resourceSamples.count - 90)
            }

            if self.isGenerating {
                self.generationSpeedHistory.append(self.generationStats.tokensPerSecond)
                if self.generationSpeedHistory.count > 90 {
                    self.generationSpeedHistory.removeFirst(self.generationSpeedHistory.count - 90)
                }
            }
        }
    }

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        let memoryWarning = center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.memoryWarningBanner = "Memory warning received. Model unloaded to protect app stability."
                self.appendSystemMessage("⚠️ Model ran out of memory. Try a smaller model.")
                self.unloadModel()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if self.memoryWarningBanner != nil {
                    self.memoryWarningBanner = nil
                }
            }
        }

        let didEnterBackground = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isGenerating {
                    self.beginBackgroundTaskIfNeeded()
                }
            }
        }

        let willEnterForeground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }

        observers = [memoryWarning, didEnterBackground, willEnterForeground]
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OnDeviceLLMGeneration") { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.stopGeneration()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func trimContextIfNeeded() {
        let softTokenLimit = Int(Double(contextLength) * 0.85)

        while estimatedPromptTokens(messages: messages) > softTokenLimit {
            let nonSystemIndices = messages.indices.filter { messages[$0].role != .system }
            guard nonSystemIndices.count > 8, let removeIndex = nonSystemIndices.first else {
                break
            }
            messages.remove(at: removeIndex)
        }
    }

    private func estimatedPromptTokens(messages: [ChatMessage]) -> Int {
        let contentChars = messages.reduce(0) { partial, message in
            partial + message.content.count + (message.inferenceAugmentation?.count ?? 0)
        }

        let systemChars = systemPrompt.count
        return ((contentChars + systemChars) / 4) + (messages.count * 8)
    }

    private func buildImageAugmentation(_ attachments: [ChatAttachment]) -> String? {
        guard !attachments.isEmpty else {
            return nil
        }

        let blocks = attachments.enumerated().map { index, attachment in
            let ocr = attachment.analysisText ?? "No OCR text"
            return "[Attachment \(index + 1)]\n\(ocr)"
        }

        return """
        The user attached \(attachments.count) image(s). Analyze them with the available OCR/image metadata:
        \(blocks.joined(separator: "\n\n"))
        """
    }

    private func appendSystemMessage(_ content: String) {
        messages.append(ChatMessage(role: .system, content: content))
        syncActiveConversation()
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let llamaError = error as? LlamaError {
            switch llamaError {
            case .contextLimitReached:
                return "Context limit reached. The chat history was too long for the current context size."
            case .runtimeUnavailable:
                return "llama runtime not linked. Add the llama Swift package dependency and rebuild."
            default:
                return llamaError.localizedDescription
            }
        }

        return error.localizedDescription
    }
}
