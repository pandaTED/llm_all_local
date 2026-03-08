import Foundation

struct DeviceCapabilityService {
    static var physicalRAMGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    static var suggestedModelTier: String {
        let ram = physicalRAMGB
        if ram >= 7.5 { return "8B" }
        if ram >= 5.0 { return "4B" }
        return "1.7B"
    }
}
