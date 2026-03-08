import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false
    @Published var isModelLoading: Bool = false
    @Published var modelLoadError: String?
    @Published var isModelLoaded: Bool = false
    @Published var selectedModelName: String = "No Model"
    @Published var memoryWarningBanner: String?

    @Published var systemPrompt: String
    @Published var contextLength: Int
    @Published var temperature: Double
    @Published var allowsCellularDownloads: Bool

    private let llamaService = LlamaService()
    private let defaults: UserDefaults

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
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var shouldShowOnboarding: Bool {
        !defaults.bool(forKey: Keys.hasCompletedOnboarding)
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
    }

    func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        guard !isGenerating else { return }
        guard isModelLoaded else {
            appendSystemMessage("⚠️ No model loaded. Open Model Manager to choose a model.")
            return
        }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: userText))
        trimContextIfNeeded()

        var assistantMessage = ChatMessage(role: .assistant, content: "")
        assistantMessage.isGenerating = true
        messages.append(assistantMessage)
        let assistantID = assistantMessage.id

        isGenerating = true

        generationTask = Task {
            do {
                let promptMessages = messages.filter { $0.id != assistantID }
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
                }
            } catch is CancellationError {
                // Intentionally ignored: cancellation is user-driven.
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
    }

    func clearChat() {
        stopGeneration()
        messages = []
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
            partial + message.content.count
        }

        let systemChars = systemPrompt.count
        return ((contentChars + systemChars) / 4) + (messages.count * 8)
    }

    private func appendSystemMessage(_ content: String) {
        messages.append(ChatMessage(role: .system, content: content))
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
