import Foundation

final class ModelDownloadService: NSObject {
    enum DownloadError: LocalizedError {
        case invalidURL
        case authenticationRequired
        case resourceNotFound
        case invalidHTTPStatus(Int)
        case missingDestination
        case filesystem(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Model URL is invalid."
            case .authenticationRequired:
                return "Model source requires authentication (401/403). Please switch to a public model URL or provide access token."
            case .resourceNotFound:
                return "Model file not found at the download URL (404)."
            case .invalidHTTPStatus(let code):
                return "Download failed with HTTP status \(code)."
            case .missingDestination:
                return "Download destination is unavailable."
            case .filesystem(let error):
                return "Failed to save model file: \(error.localizedDescription)"
            }
        }
    }

    static let shared = ModelDownloadService()

    private let stateQueue = DispatchQueue(label: "ModelDownloadService.state")
    private var continuationByTask: [Int: CheckedContinuation<URL, Error>] = [:]
    private var destinationByTask: [Int: URL] = [:]
    private var progressByTask: [Int: @Sendable (Double) -> Void] = [:]
    private var completionURLByTask: [Int: URL] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 60 * 60 * 24
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    static func modelsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func localURL(for model: ModelConfig) throws -> URL {
        try modelsDirectory().appendingPathComponent(model.filename)
    }

    func download(
        model: ModelConfig,
        allowsCellularAccess: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = try Self.localURL(for: model)
        if FileManager.default.fileExists(atPath: destination.path) {
            progress(1.0)
            return destination
        }

        guard let remoteURL = URL(string: model.downloadURL) else {
            throw DownloadError.invalidURL
        }

        var request = URLRequest(url: remoteURL)
        request.allowsCellularAccess = allowsCellularAccess
        request.timeoutInterval = 60 * 60 * 24
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("LLMChat/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request)

        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                self.continuationByTask[task.taskIdentifier] = continuation
                self.destinationByTask[task.taskIdentifier] = destination
                self.progressByTask[task.taskIdentifier] = progress
                task.resume()
            }
        }
    }

    func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    private func finish(taskID: Int, result: Result<URL, Error>) {
        stateQueue.async {
            let continuation = self.continuationByTask.removeValue(forKey: taskID)
            self.destinationByTask.removeValue(forKey: taskID)
            self.progressByTask.removeValue(forKey: taskID)
            self.completionURLByTask.removeValue(forKey: taskID)
            continuation?.resume(with: result)
        }
    }
}

extension ModelDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        switch http.statusCode {
        case 200...299:
            completionHandler(.allow)
        case 401, 403:
            finish(taskID: task.taskIdentifier, result: .failure(DownloadError.authenticationRequired))
            completionHandler(.cancel)
        case 404:
            finish(taskID: task.taskIdentifier, result: .failure(DownloadError.resourceNotFound))
            completionHandler(.cancel)
        default:
            finish(taskID: task.taskIdentifier, result: .failure(DownloadError.invalidHTTPStatus(http.statusCode)))
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))

        stateQueue.async {
            let callback = self.progressByTask[downloadTask.taskIdentifier]
            callback?(value)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        stateQueue.async {
            guard let destination = self.destinationByTask[downloadTask.taskIdentifier] else {
                self.finish(taskID: downloadTask.taskIdentifier, result: .failure(DownloadError.missingDestination))
                return
            }

            do {
                let folder = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }

                try FileManager.default.moveItem(at: location, to: destination)
                var backupValues = URLResourceValues()
                backupValues.isExcludedFromBackup = true
                var mutableDestination = destination
                try mutableDestination.setResourceValues(backupValues)
                self.completionURLByTask[downloadTask.taskIdentifier] = destination
            } catch {
                self.finish(taskID: downloadTask.taskIdentifier, result: .failure(DownloadError.filesystem(error)))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(taskID: task.taskIdentifier, result: .failure(error))
            return
        }

        stateQueue.async {
            guard let finalURL = self.completionURLByTask[task.taskIdentifier] else {
                self.finish(taskID: task.taskIdentifier, result: .failure(DownloadError.missingDestination))
                return
            }

            self.finish(taskID: task.taskIdentifier, result: .success(finalURL))
        }
    }
}
