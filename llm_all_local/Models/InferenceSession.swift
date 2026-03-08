import Foundation

struct InferenceSession: Equatable {
    let modelPath: String
    let modelName: String
    let contextLength: Int32
    let loadedAt: Date
}
