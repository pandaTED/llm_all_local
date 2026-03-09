import Foundation

struct ResourceSample: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let cpuPercent: Double
    let memoryPercent: Double
    let memoryMB: Double
    let gpuPercent: Double
    let npuPercent: Double
}
