import Foundation

struct ChatAttachment: Identifiable, Codable, Equatable {
    enum AttachmentType: String, Codable {
        case image
    }

    let id: UUID
    let type: AttachmentType
    var localPath: String
    var thumbnailPath: String?
    var width: Int
    var height: Int
    var analysisText: String?

    init(
        id: UUID = UUID(),
        type: AttachmentType = .image,
        localPath: String,
        thumbnailPath: String? = nil,
        width: Int,
        height: Int,
        analysisText: String? = nil
    ) {
        self.id = id
        self.type = type
        self.localPath = localPath
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.analysisText = analysisText
    }
}
