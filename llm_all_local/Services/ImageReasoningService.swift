import Foundation
import UIKit
import Vision

actor ImageReasoningService {
    enum ImageReasoningError: LocalizedError {
        case imageEncodingFailed
        case imageLoadFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                return "Failed to encode image."
            case .imageLoadFailed:
                return "Failed to load image data."
            }
        }
    }

    private let fileManager = FileManager.default

    func createAttachment(from image: UIImage) async throws -> ChatAttachment {
        let imageDirectory = try makeImageDirectory()
        let id = UUID().uuidString

        let originalURL = imageDirectory.appendingPathComponent("\(id).jpg")
        let thumbnailURL = imageDirectory.appendingPathComponent("\(id)-thumb.jpg")

        guard let originalData = image.jpegData(compressionQuality: 0.92) else {
            throw ImageReasoningError.imageEncodingFailed
        }

        try originalData.write(to: originalURL, options: .atomic)

        let thumbnail = makeThumbnail(from: image, maxDimension: 360)
        if let thumbData = thumbnail.jpegData(compressionQuality: 0.82) {
            try thumbData.write(to: thumbnailURL, options: .atomic)
        }

        let analysis = await analyze(image: image)

        return ChatAttachment(
            localPath: originalURL.path,
            thumbnailPath: fileManager.fileExists(atPath: thumbnailURL.path) ? thumbnailURL.path : nil,
            width: Int(image.size.width),
            height: Int(image.size.height),
            analysisText: analysis
        )
    }

    private func makeImageDirectory() throws -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("message-images", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeThumbnail(from image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else {
            return image
        }

        let scale = maxDimension / maxSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func analyze(image: UIImage) async -> String {
        guard let cgImage = image.cgImage else {
            return "Image size: \(Int(image.size.width))x\(Int(image.size.height))."
        }

        let ocrText = recognizeText(cgImage: cgImage)
        let normalizedOCR: String
        if let ocrText, !ocrText.isEmpty {
            normalizedOCR = ocrText.prefix(600).description
        } else {
            normalizedOCR = "No readable text detected."
        }

        return """
        [Image]
        Size: \(Int(image.size.width))x\(Int(image.size.height))
        OCR: \(normalizedOCR)
        """
    }

    private func recognizeText(cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results else {
            return nil
        }

        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }
}
