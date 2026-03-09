import Foundation
import Darwin.Mach

final class ResourceMonitorService {
    struct Snapshot {
        let cpuPercent: Double
        let memoryMB: Double
        let memoryPercent: Double
        let gpuPercent: Double
        let npuPercent: Double
        let timestamp: Date
    }

    private let queue = DispatchQueue(label: "ResourceMonitorService", qos: .utility)
    private var timer: DispatchSourceTimer?

    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var inferenceActive = false
    private var currentTokensPerSecond: Double = 0

    func start(interval: TimeInterval = 1.0, onUpdate: @escaping @Sendable (Snapshot) -> Void) {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let sample = self.collectSnapshot()
            DispatchQueue.main.async {
                onUpdate(sample)
            }
        }

        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func setInferenceState(active: Bool, tokensPerSecond: Double) {
        queue.async { [weak self] in
            self?.inferenceActive = active
            self?.currentTokensPerSecond = tokensPerSecond
        }
    }

    private func collectSnapshot() -> Snapshot {
        let cpu = deviceCPUUsagePercent()
        let memoryMB = appMemoryMB()
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let memoryPercent = ramGB > 0 ? min(100, (memoryMB / (ramGB * 1024.0)) * 100) : 0

        let tps = currentTokensPerSecond
        let gpu = inferenceActive ? min(98, 18 + tps * 7.5) : 4
        let npu = inferenceActive ? min(90, tps * 2.2) : 0

        return Snapshot(
            cpuPercent: cpu,
            memoryMB: memoryMB,
            memoryPercent: memoryPercent,
            gpuPercent: gpu,
            npuPercent: npu,
            timestamp: Date()
        )
    }

    private func deviceCPUUsagePercent() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        let current = (
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )

        defer { previousCPUTicks = current }

        guard let previousCPUTicks else {
            return 0
        }

        let user = Double(current.user - previousCPUTicks.user)
        let system = Double(current.system - previousCPUTicks.system)
        let idle = Double(current.idle - previousCPUTicks.idle)
        let nice = Double(current.nice - previousCPUTicks.nice)

        let total = user + system + idle + nice
        guard total > 0 else { return 0 }

        return ((user + system + nice) / total) * 100
    }

    private func appMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return Double(info.phys_footprint) / 1_048_576
    }
}
