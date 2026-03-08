import Foundation

struct ModelConfig: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let filename: String
    let fileSizeGB: Double
    let ramRequiredGB: Double
    let downloadURL: String
    var isDownloaded: Bool = false
    var downloadProgress: Double = 0

    static let fallbackCatalog: [ModelConfig] = [
        ModelConfig(
            id: "qwen35-4b-q4",
            name: "Qwen3.5-4B (Q4_K_M)",
            filename: "Qwen3.5-4B-Q4_K_M.gguf",
            fileSizeGB: 2.6,
            ramRequiredGB: 5.5,
            downloadURL: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf"
        ),
        ModelConfig(
            id: "qwen35-2b-q4",
            name: "Qwen3.5-2B (Q4_K_M)",
            filename: "Qwen3.5-2B-Q4_K_M.gguf",
            fileSizeGB: 1.2,
            ramRequiredGB: 3.2,
            downloadURL: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf"
        ),
        ModelConfig(
            id: "qwen35-08b-q4",
            name: "Qwen3.5-0.8B (Q4_K_M)",
            filename: "Qwen3.5-0.8B-Q4_K_M.gguf",
            fileSizeGB: 0.5,
            ramRequiredGB: 1.8,
            downloadURL: "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf"
        )
    ]
}
