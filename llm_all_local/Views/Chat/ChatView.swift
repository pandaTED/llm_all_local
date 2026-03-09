import SwiftUI
import PhotosUI
import UIKit

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showModelManager = false
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var showHistory = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let banner = viewModel.memoryWarningBanner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.orange)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let modelError = viewModel.modelLoadError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.white)
                        Text(modelError)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            viewModel.modelLoadError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                PerformanceHeaderView(
                    generation: viewModel.generationStats,
                    generationSpeedHistory: viewModel.generationSpeedHistory,
                    resourceSamples: viewModel.resourceSamples
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isGenerating,
                               viewModel.messages.last?.role != .assistant {
                                HStack {
                                    TypingIndicatorView()
                                    Spacer(minLength: 60)
                                }
                                .id("typing")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.messages.last?.content) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                Divider()

                InputBarView(
                    text: $viewModel.inputText,
                    pendingAttachments: viewModel.pendingAttachments,
                    isGenerating: viewModel.isGenerating,
                    onSend: viewModel.sendMessage,
                    onStop: viewModel.stopGeneration,
                    onPickFromLibrary: { showPhotoPicker = true },
                    onPickFromCamera: {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showCamera = true
                        } else {
                            showPhotoPicker = true
                        }
                    },
                    onRemoveAttachment: { id in
                        viewModel.removePendingAttachment(id: id)
                    }
                )
            }
            .navigationTitle(viewModel.isModelLoaded ? viewModel.selectedModelName : "LLM Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: viewModel.clearChat) {
                        Image(systemName: "square.and.pencil")
                    }

                    Button(action: { showSettings = true }) {
                        Image(systemName: "slider.horizontal.3")
                    }

                    Button(action: { showModelManager = true }) {
                        Image(systemName: "cpu")
                    }
                }
            }
            .overlay {
                if viewModel.isModelLoading {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading model…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            viewModel.addPendingImage(image)
                        }
                    }
                    await MainActor.run {
                        selectedPhotoItem = nil
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraImagePicker { image in
                    viewModel.addPendingImage(image)
                }
            }
            .sheet(isPresented: $showHistory) {
                ConversationHistoryView(
                    conversations: viewModel.conversations,
                    activeConversationID: viewModel.activeConversationID,
                    onSelect: { id in
                        viewModel.selectConversation(id: id)
                    },
                    onDelete: { id in
                        viewModel.deleteConversation(id: id)
                    },
                    onNewChat: {
                        viewModel.createNewConversation()
                    }
                )
            }
            .sheet(isPresented: $showModelManager) {
                ModelManagerView(onModelSelected: { path, name in
                    Task {
                        await viewModel.loadModel(at: path, displayName: name)
                        showModelManager = false
                    }
                }, allowsCellularDownloads: viewModel.allowsCellularDownloads)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    systemPrompt: Binding(
                        get: { viewModel.systemPrompt },
                        set: { viewModel.updateSystemPrompt($0) }
                    ),
                    contextLength: Binding(
                        get: { viewModel.contextLength },
                        set: { viewModel.updateContextLength($0) }
                    ),
                    temperature: Binding(
                        get: { viewModel.temperature },
                        set: { viewModel.updateTemperature($0) }
                    ),
                    allowsCellularDownloads: Binding(
                        get: { viewModel.allowsCellularDownloads },
                        set: { viewModel.updateAllowsCellularDownloads($0) }
                    )
                )
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(recommendedTier: DeviceCapabilityService.suggestedModelTier) {
                    showOnboarding = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        showModelManager = true
                    }
                    viewModel.markOnboardingCompleted()
                }
            }
            .onChange(of: viewModel.modelLoadError) { _, newValue in
                guard let newValue else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if viewModel.modelLoadError == newValue {
                        viewModel.modelLoadError = nil
                    }
                }
            }
            .onAppear {
                if viewModel.shouldShowOnboarding && !viewModel.isModelLoaded {
                    showOnboarding = true
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct OnboardingView: View {
    let recommendedTier: String
    let onDownloadRecommended: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to On-Device LLM Chat")
                    .font(.title2.bold())

                Text("No model is loaded yet. This app runs fully offline after the model is downloaded.")
                    .foregroundStyle(.secondary)

                Text("Recommended model tier for this device: \(recommendedTier)")
                    .font(.headline)

                Spacer()

                Button(action: onDownloadRecommended) {
                    Text("Download Recommended Model")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .navigationTitle("Get Started")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ChatView()
}
