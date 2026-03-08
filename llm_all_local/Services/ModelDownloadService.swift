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

    private struct RemoteProbe {
        let finalURL: URL
        let contentLength: Int64
        let supportsRanges: Bool
    }

    private struct SegmentSpec {
        let index: Int
        let start: Int64
        let end: Int64

        var expectedLength: Int64 {
            end - start + 1
        }
    }

    private struct SegmentResult {
        let index: Int
        let fileURL: URL
        let byteCount: Int64
    }

    static let shared = ModelDownloadService()

    private let multipartMinFileSize: Int64 = 64 * 1024 * 1024
    private let multipartMaxThreads = 6

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

        let probe = try await probeRemoteFile(url: remoteURL, allowsCellularAccess: allowsCellularAccess)

        if probe.supportsRanges && probe.contentLength >= multipartMinFileSize {
            do {
                return try await downloadMultipart(
                    from: probe.finalURL,
                    destination: destination,
                    contentLength: probe.contentLength,
                    allowsCellularAccess: allowsCellularAccess,
                    progress: progress
                )
            } catch let known as DownloadError {
                switch known {
                case .authenticationRequired, .resourceNotFound, .invalidURL:
                    throw known
                default:
                    return try await downloadSingle(
                        from: probe.finalURL,
                        destination: destination,
                        allowsCellularAccess: allowsCellularAccess,
                        progress: progress
                    )
                }
            } catch {
                return try await downloadSingle(
                    from: probe.finalURL,
                    destination: destination,
                    allowsCellularAccess: allowsCellularAccess,
                    progress: progress
                )
            }
        }

        return try await downloadSingle(
            from: probe.finalURL,
            destination: destination,
            allowsCellularAccess: allowsCellularAccess,
            progress: progress
        )
    }

    func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    private func downloadSingle(
        from remoteURL: URL,
        destination: URL,
        allowsCellularAccess: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let request = makeBaseRequest(url: remoteURL, allowsCellularAccess: allowsCellularAccess)
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

    private func downloadMultipart(
        from remoteURL: URL,
        destination: URL,
        contentLength: Int64,
        allowsCellularAccess: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let segments = makeSegments(for: contentLength)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "llm-download-\(UUID().uuidString)",
            isDirectory: true
        )

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        var orderedPartURLs: [URL?] = Array(repeating: nil, count: segments.count)
        var completedBytes: Int64 = 0

        progress(0)

        try await withThrowingTaskGroup(of: SegmentResult.self) { group in
            for segment in segments {
                let request = makeRangeRequest(
                    url: remoteURL,
                    start: segment.start,
                    end: segment.end,
                    allowsCellularAccess: allowsCellularAccess
                )

                group.addTask {
                    try await Self.downloadSegment(request: request, index: segment.index, outputDirectory: tempDirectory)
                }
            }

            for try await result in group {
                orderedPartURLs[result.index] = result.fileURL
                completedBytes += result.byteCount
                let ratio = min(0.98, max(0, Double(completedBytes) / Double(contentLength)))
                progress(ratio)
            }
        }

        let finalParts: [URL] = try orderedPartURLs.enumerated().map { index, url in
            guard let url else {
                throw DownloadError.filesystem(NSError(
                    domain: "ModelDownloadService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing segment at index \(index)"]
                ))
            }
            return url
        }

        do {
            try merge(segmentFiles: finalParts, into: destination)
            try markExcludedFromBackup(url: destination)
            progress(1.0)
            return destination
        } catch {
            throw DownloadError.filesystem(error)
        }
    }

    private func probeRemoteFile(url: URL, allowsCellularAccess: Bool) async throws -> RemoteProbe {
        var request = makeBaseRequest(url: url, allowsCellularAccess: allowsCellularAccess)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return RemoteProbe(finalURL: response.url ?? url, contentLength: max(response.expectedContentLength, 0), supportsRanges: false)
            }

            switch http.statusCode {
            case 200...299:
                break
            case 401, 403:
                throw DownloadError.authenticationRequired
            case 404:
                throw DownloadError.resourceNotFound
            case 400, 405:
                return RemoteProbe(finalURL: response.url ?? url, contentLength: -1, supportsRanges: false)
            default:
                throw DownloadError.invalidHTTPStatus(http.statusCode)
            }

            let headerLength = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? "") ?? response.expectedContentLength
            let contentLength = max(headerLength, -1)
            let acceptRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased()
            let supportsRanges = acceptRanges.contains("bytes")

            return RemoteProbe(finalURL: response.url ?? url, contentLength: contentLength, supportsRanges: supportsRanges)
        } catch {
            if let known = error as? DownloadError {
                throw known
            }
            return RemoteProbe(finalURL: url, contentLength: -1, supportsRanges: false)
        }
    }

    private static func downloadSegment(
        request: URLRequest,
        index: Int,
        outputDirectory: URL
    ) async throws -> SegmentResult {
        let (temporaryFile, response) = try await URLSession.shared.download(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.missingDestination
        }

        switch http.statusCode {
        case 206:
            break
        case 401, 403:
            throw DownloadError.authenticationRequired
        case 404:
            throw DownloadError.resourceNotFound
        default:
            throw DownloadError.invalidHTTPStatus(http.statusCode)
        }

        let targetFile = outputDirectory.appendingPathComponent("part-\(index).gguf")
        if FileManager.default.fileExists(atPath: targetFile.path) {
            try FileManager.default.removeItem(at: targetFile)
        }
        try FileManager.default.moveItem(at: temporaryFile, to: targetFile)

        let attrs = try FileManager.default.attributesOfItem(atPath: targetFile.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        return SegmentResult(index: index, fileURL: targetFile, byteCount: size)
    }

    private func makeSegments(for contentLength: Int64) -> [SegmentSpec] {
        let threadCount = computeThreadCount(for: contentLength)
        let chunkSize = contentLength / Int64(threadCount)

        var segments: [SegmentSpec] = []
        segments.reserveCapacity(threadCount)

        for index in 0..<threadCount {
            let start = Int64(index) * chunkSize
            let end: Int64
            if index == threadCount - 1 {
                end = contentLength - 1
            } else {
                end = start + chunkSize - 1
            }
            segments.append(SegmentSpec(index: index, start: start, end: end))
        }

        return segments
    }

    private func computeThreadCount(for contentLength: Int64) -> Int {
        let bySize = max(2, Int(contentLength / (256 * 1024 * 1024)))
        return min(multipartMaxThreads, bySize)
    }

    private func makeBaseRequest(url: URL, allowsCellularAccess: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        request.allowsCellularAccess = allowsCellularAccess
        request.timeoutInterval = 60 * 60 * 24
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("LLMChat/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func makeRangeRequest(url: URL, start: Int64, end: Int64, allowsCellularAccess: Bool) -> URLRequest {
        var request = makeBaseRequest(url: url, allowsCellularAccess: allowsCellularAccess)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        return request
    }

    private func merge(segmentFiles: [URL], into destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)

        let writer = try FileHandle(forWritingTo: destination)
        defer {
            try? writer.close()
        }

        for segmentURL in segmentFiles {
            let reader = try FileHandle(forReadingFrom: segmentURL)
            defer {
                try? reader.close()
            }

            while true {
                let data = try reader.read(upToCount: 1_048_576) ?? Data()
                if data.isEmpty {
                    break
                }
                try writer.write(contentsOf: data)
            }
        }
    }

    private func markExcludedFromBackup(url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
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
                try self.markExcludedFromBackup(url: destination)
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
