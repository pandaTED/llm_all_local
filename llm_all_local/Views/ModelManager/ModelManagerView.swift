import SwiftUI

struct ModelManagerView: View {
    let onModelSelected: (String, String) -> Void
    let allowsCellularDownloads: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ModelManagerViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = viewModel.errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("关闭") {
                                viewModel.errorMessage = nil
                            }
                            .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Device RAM: \(String(format: "%.1f", DeviceCapabilityService.physicalRAMGB)) GB")
                            .font(.subheadline)
                        Text("Recommended tier: \(DeviceCapabilityService.suggestedModelTier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if let recommendation = viewModel.recommendedModel {
                    Section("Recommended") {
                        ModelRowView(
                            model: recommendation,
                            deviceRAM: DeviceCapabilityService.physicalRAMGB,
                            isDownloading: viewModel.downloadingModelID == recommendation.id,
                            onDownload: {
                                Task {
                                    await viewModel.downloadModel(recommendation, allowsCellularAccess: allowsCellularDownloads)
                                }
                            },
                            onUse: {
                                useModel(recommendation)
                            },
                            onDelete: {
                                viewModel.deleteModel(recommendation)
                            }
                        )
                    }
                }

                Section("All Models") {
                    ForEach(viewModel.models.filter { $0.id != viewModel.recommendedModel?.id }) { model in
                        ModelRowView(
                            model: model,
                            deviceRAM: DeviceCapabilityService.physicalRAMGB,
                            isDownloading: viewModel.downloadingModelID == model.id,
                            onDownload: {
                                Task {
                                    await viewModel.downloadModel(model, allowsCellularAccess: allowsCellularDownloads)
                                }
                            },
                            onUse: {
                                useModel(model)
                            },
                            onDelete: {
                                viewModel.deleteModel(model)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Model Manager")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.refreshDownloadState()
            }
            .sheet(isPresented: Binding(
                get: { viewModel.downloadingModelID != nil },
                set: { value in
                    if !value {
                        ModelDownloadService.shared.cancelAll()
                    }
                }
            )) {
                if let downloadingModel = viewModel.models.first(where: { $0.id == viewModel.downloadingModelID }) {
                    ModelDownloadView(
                        modelName: downloadingModel.name,
                        progress: viewModel.activeDownloadProgress,
                        onCancel: {
                            ModelDownloadService.shared.cancelAll()
                        }
                    )
                }
            }
        }
    }

    private func useModel(_ model: ModelConfig) {
        guard let path = viewModel.localModelPath(for: model) else { return }
        onModelSelected(path, model.name)
    }
}

#Preview {
    ModelManagerView(onModelSelected: { _, _ in }, allowsCellularDownloads: false)
}
