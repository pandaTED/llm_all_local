import Foundation

struct GenerationStats: Equatable {
    var firstTokenLatencyMs: Double?
    var tokensPerSecond: Double
    var generatedTokenCount: Int
    var lastUpdatedAt: Date?

    static let empty = GenerationStats(
        firstTokenLatencyMs: nil,
        tokensPerSecond: 0,
        generatedTokenCount: 0,
        lastUpdatedAt: nil
    )
}
