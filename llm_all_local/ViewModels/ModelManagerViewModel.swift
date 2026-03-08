import Foundation
import Combine

@MainActor
final class ModelManagerViewModel: ObservableObject {
    @Published private(set) var models: [ModelConfig] = []
    @Published var errorMessage: String?
    @Published var downloadingModelID: String?
    @Published var activeDownloadProgress: Double = 0

    private let downloadService: ModelDownloadService

    init(downloadService: ModelDownloadService? = nil) {
        self.downloadService = downloadService ?? .shared
        loadCatalog()
    }

    var recommendedModel: ModelConfig? {
        let tier = DeviceCapabilityService.suggestedModelTier
        switch tier {
        case "8B":
            return models.first(where: { $0.name.contains("8B") })
        case "4B":
            return models.first(where: { $0.name.contains("4B") })
        default:
            return models.first(where: { $0.name.contains("1.7B") })
        }
    }

    var isDownloading: Bool {
        downloadingModelID != nil
    }

    func loadCatalog() {
        do {
            if let url = Bundle.main.url(forResource: "models", withExtension: "json") ??
                Bundle.main.url(forResource: "models", withExtension: "json", subdirectory: "Resources") {
                let data = try Data(contentsOf: url)
                models = try JSONDecoder().decode([ModelConfig].self, from: data)
            } else {
                models = ModelConfig.fallbackCatalog
            }
        } catch {
            errorMessage = "Failed to load model catalog. Using built-in defaults."
            models = ModelConfig.fallbackCatalog
        }

        refreshDownloadState()
    }

    func refreshDownloadState() {
        for index in models.indices {
            do {
                let localURL = try ModelDownloadService.localURL(for: models[index])
                let exists = FileManager.default.fileExists(atPath: localURL.path)
                guard exists else {
                    models[index].isDownloaded = false
                    models[index].downloadProgress = 0
                    continue
                }

                let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
                let currentSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let expectedSize = Int64(models[index].fileSizeGB * 1_073_741_824)

                // Filter out corrupted placeholder files (e.g. auth error bodies).
                let isValidModelFile = currentSize > max(10_000_000, expectedSize / 10)
                if !isValidModelFile {
                    try? FileManager.default.removeItem(at: localURL)
                }

                models[index].isDownloaded = isValidModelFile
                models[index].downloadProgress = isValidModelFile ? 1.0 : 0
            } catch {
                models[index].isDownloaded = false
                models[index].downloadProgress = 0
            }
        }
    }

    func localModelPath(for model: ModelConfig) -> String? {
        do {
            let localURL = try ModelDownloadService.localURL(for: model)
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                return nil
            }
            return localURL.path
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func downloadModel(_ model: ModelConfig, allowsCellularAccess: Bool) async {
        downloadingModelID = model.id
        activeDownloadProgress = 0
        setProgress(0, for: model.id)

        do {
            let url = try await downloadService.download(
                model: model,
                allowsCellularAccess: allowsCellularAccess,
                progress: { [weak self] progress in
                    DispatchQueue.main.async { [weak self] in
                        self?.applyProgress(progress, for: model.id)
                    }
                }
            )

            _ = url
            setDownloaded(true, for: model.id)
        } catch {
            errorMessage = error.localizedDescription
            setProgress(0, for: model.id)
        }

        downloadingModelID = nil
        activeDownloadProgress = 0
    }

    func deleteModel(_ model: ModelConfig) {
        do {
            let localURL = try ModelDownloadService.localURL(for: model)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            setDownloaded(false, for: model.id)
            setProgress(0, for: model.id)
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    private func setDownloaded(_ value: Bool, for modelID: String) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        models[index].isDownloaded = value
        models[index].downloadProgress = value ? 1.0 : models[index].downloadProgress
    }

    private func setProgress(_ value: Double, for modelID: String) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        models[index].downloadProgress = value
    }

    private func applyProgress(_ value: Double, for modelID: String) {
        activeDownloadProgress = value
        setProgress(value, for: modelID)
    }
}
