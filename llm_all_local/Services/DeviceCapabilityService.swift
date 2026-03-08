import Foundation

struct DeviceCapabilityService {
    static var physicalRAMGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    static var suggestedModelTier: String {
        let ram = physicalRAMGB
        if ram >= 7.5 { return "4B" }
        if ram >= 5.0 { return "2B" }
        return "0.8B"
    }
}
