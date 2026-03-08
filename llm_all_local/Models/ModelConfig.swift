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
            id: "qwen3-8b-q4",
            name: "Qwen3-8B (Q4_K_M)",
            filename: "Qwen3-8B-Q4_K_M.gguf",
            fileSizeGB: 4.8,
            ramRequiredGB: 7.5,
            downloadURL: "https://huggingface.co/lm-kit/qwen-3-8b-instruct-gguf/resolve/main/Qwen3-8B-Q4_K_M.gguf"
        ),
        ModelConfig(
            id: "qwen3-4b-q4",
            name: "Qwen3-4B (Q4_K_M, 2507)",
            filename: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
            fileSizeGB: 2.3,
            ramRequiredGB: 4.0,
            downloadURL: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
        ),
        ModelConfig(
            id: "qwen3-1.7b-q4",
            name: "Qwen3-1.7B (Q4_K_M)",
            filename: "Qwen3-1.7B-Q4_K_M.gguf",
            fileSizeGB: 1.2,
            ramRequiredGB: 2.0,
            downloadURL: "https://huggingface.co/lm-kit/qwen-3-1.7b-instruct-gguf/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"
        )
    ]
}
