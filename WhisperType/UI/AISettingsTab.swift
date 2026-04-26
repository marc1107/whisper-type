import SwiftUI

struct AISettingsTab: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var ollama = OllamaService()
    @State private var apiKey: String = ""
    @State private var newFrom: String = ""
    @State private var newTo: String = ""

    var body: some View {
        Form {
            providerSection
            if settings.llmEnabled {
                promptSection
                dictionarySection
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            apiKey = KeychainHelper.load(key: settings.llmProvider.keychainKey) ?? ""
            Task { await ollama.detect() }
        }
        .onChange(of: settings.llmProvider) { _, _ in
            Task { await ollama.detect() }
        }
    }

    private var providerSection: some View {
        Section(NSLocalizedString("settings.ai.section.provider", comment: "")) {
            Toggle(NSLocalizedString("settings.ai.enable", comment: ""), isOn: Binding(
                get: { settings.llmEnabled },
                set: { settings.llmEnabled = $0 }
            ))

            if settings.llmEnabled {
                Picker(NSLocalizedString("settings.ai.provider", comment: ""), selection: Binding(
                    get: { settings.llmProvider },
                    set: {
                        settings.llmProvider = $0
                        settings.llmModel = ""
                        apiKey = KeychainHelper.load(key: $0.keychainKey) ?? ""
                    }
                )) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                if settings.llmProvider == .ollama {
                    ollamaSection
                } else if settings.llmProvider.requiresAPIKey {
                    SecureField(NSLocalizedString("settings.ai.api_key", comment: ""), text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            KeychainHelper.save(key: settings.llmProvider.keychainKey, value: newValue)
                        }
                }

                TextField(
                    String(format: NSLocalizedString("settings.ai.model_placeholder", comment: ""),
                           settings.llmProvider.defaultModel),
                    text: Binding(
                        get: { settings.llmModel },
                        set: { settings.llmModel = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        if ollama.isInstalled == false {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("settings.ai.ollama_not_installed", comment: ""))
                        .fontWeight(.medium)
                    Text(NSLocalizedString("settings.ai.ollama_install_hint", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("ollama.com/download", destination: URL(string: "https://ollama.com/download")!)
                        .font(.caption)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(NSLocalizedString("settings.ai.ollama_running", comment: ""))
            }

            if !ollama.availableModels.contains(settings.effectiveLLMModel) {
                if ollama.isPulling {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: ollama.pullProgress)
                            .progressViewStyle(.linear)
                        Text(String(format: NSLocalizedString("settings.ai.pulling_model", comment: ""),
                                    settings.effectiveLLMModel))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(NSLocalizedString("settings.ai.pull_model", comment: "")) {
                        Task { try? await ollama.pullModel(settings.effectiveLLMModel) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var promptSection: some View {
        Section(NSLocalizedString("settings.ai.section.prompt", comment: "")) {
            Toggle(NSLocalizedString("settings.ai.use_default_prompt", comment: ""), isOn: Binding(
                get: { settings.llmUseDefaultPrompt },
                set: { settings.llmUseDefaultPrompt = $0 }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Toggle(NSLocalizedString("settings.ai.thinking_mode", comment: ""), isOn: Binding(
                    get: { settings.llmThinkingEnabled },
                    set: { settings.llmThinkingEnabled = $0 }
                ))
                Text(NSLocalizedString("settings.ai.thinking_mode_hint", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("settings.ai.additional_instructions", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: Binding(
                    get: { settings.llmCustomPrompt },
                    set: { settings.llmCustomPrompt = $0 }
                ))
                .font(.system(.caption, design: .default))
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
            }
        }
    }

    private var dictionarySection: some View {
        Section(NSLocalizedString("settings.ai.section.dictionary", comment: "")) {
            ForEach(settings.llmDictionaryEntries) { entry in
                HStack {
                    Text(entry.from.isEmpty ? "—" : entry.from)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(entry.to.isEmpty ? "—" : entry.to)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(role: .destructive) {
                        settings.llmDictionaryEntries = settings.llmDictionaryEntries.filter { $0.id != entry.id }
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField(NSLocalizedString("settings.ai.word_from", comment: ""), text: $newFrom)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField(NSLocalizedString("settings.ai.word_to", comment: ""), text: $newTo)
                    .textFieldStyle(.roundedBorder)
                Button(NSLocalizedString("settings.ai.add_word_pair", comment: "")) {
                    guard !newFrom.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    var entries = settings.llmDictionaryEntries
                    entries.append(DictionaryEntry(
                        from: newFrom.trimmingCharacters(in: .whitespaces),
                        to: newTo.trimmingCharacters(in: .whitespaces)
                    ))
                    settings.llmDictionaryEntries = entries
                    newFrom = ""
                    newTo = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
