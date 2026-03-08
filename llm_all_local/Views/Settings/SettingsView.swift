import SwiftUI

struct SettingsView: View {
    @Binding var systemPrompt: String
    @Binding var contextLength: Int
    @Binding var temperature: Double
    @Binding var allowsCellularDownloads: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("System Prompt") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 120)
                }

                Section("Inference") {
                    Stepper(value: $contextLength, in: 1024...8192, step: 512) {
                        Text("Context Length: \(contextLength)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", temperature))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: $temperature, in: 0...2, step: 0.05)
                    }
                }

                Section("Downloads") {
                    Toggle("Allow Cellular Download", isOn: $allowsCellularDownloads)
                    Text("Large model downloads are Wi-Fi only by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(
        systemPrompt: .constant("You are a helpful assistant."),
        contextLength: .constant(4096),
        temperature: .constant(0.7),
        allowsCellularDownloads: .constant(false)
    )
}
