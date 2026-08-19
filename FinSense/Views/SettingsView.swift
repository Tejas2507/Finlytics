import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var tutorialManager: TutorialManager
    
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    @AppStorage("aiProvider") private var aiProvider: String = "gemini"
    @AppStorage("aiModel") private var aiModel: String = "gemini-3.1-flash-lite"
    
    @State private var geminiApiKey: String = ""
    @State private var openAIApiKey: String = ""
    @State private var isSaved: Bool = false
    
    @State private var showAPIKeyHelp = false
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    // Account & AI Setup
                    Section(header: HStack {
                        Text("Account & Configuration")
                        Spacer()
                        Button {
                            showAPIKeyHelp = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                    }) {
                        // Income Row
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Monthly Income")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Salary / Regular Income", value: $monthlySalary, format: .number)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") {
                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        }
                                    }
                                }
                                #endif
                        }
                        
                        // Provider Toggle
                        Picker("AI Provider", selection: $aiProvider) {
                            Text("Google Gemini").tag("gemini")
                            Text("OpenAI").tag("openai")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: aiProvider) { newValue in
                            if newValue == "gemini" {
                                aiModel = GeminiRESTClient.defaultModel
                            } else {
                                aiModel = "gpt-4o-mini"
                            }
                        }
                        
                        // AI Config Rows
                        Picker("AI Model", selection: $aiModel) {
                            if aiProvider == "gemini" {
                                Text("Gemini 3.1 Flash Lite").tag("gemini-3.1-flash-lite")
                            } else {
                                Text("GPT 4o Mini").tag("gpt-4o-mini")
                                Text("GPT 4o").tag("gpt-4o")
                                Text("GPT 5 Nano").tag("gpt-5-nano")
                                Text("GPT 3.5 Turbo").tag("gpt-3.5-turbo")
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(aiProvider == "gemini" ? "Gemini" : "OpenAI") API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if aiProvider == "gemini" {
                                SecureField("Paste Gemini API Key", text: $geminiApiKey)
                                    .textContentType(.password)
                            } else {
                                SecureField("Paste OpenAI API Key", text: $openAIApiKey)
                                    .textContentType(.password)
                            }
                        }
                        
                        Button("Save Configuration") {
                            let cleanedGemini = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            KeychainHelper.shared.save(cleanedGemini, for: "gemini_api_key")
                            geminiApiKey = cleanedGemini
                            
                            let cleanedOpenAI = openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            KeychainHelper.shared.save(cleanedOpenAI, for: "openai_api_key")
                            openAIApiKey = cleanedOpenAI
                            
                            isSaved = true
                        }
                        .disabled(aiProvider == "gemini" ? geminiApiKey.isEmpty : openAIApiKey.isEmpty)
                    }
                    .id("settingsTop")
                    
                    Section {
                        NavigationLink {
                            HiddenTransactionsView()
                        } label: {
                            Label("Vault", systemImage: "lock.fill")
                                .foregroundColor(.purple)
                        }

                        NavigationLink {
                            MerchantProfilesView()
                        } label: {
                            Label("Merchant Groups", systemImage: "building.2.crop.circle")
                        }
                    }

                    Section("AI & Privacy") {
                        Label("Your API key stays in Keychain", systemImage: "key.fill")
                        VStack(alignment: .leading, spacing: 5) {
                            Text("What the AI provider receives")
                                .font(.subheadline.weight(.medium))
                            Text("Your question and a compact query schema. For advice, only the locally verified result and recent thread context are sent—not a bulk transaction history or Vault items. Unknown merchant names can be sent once for grouping, older thread messages can be summarized, Smart Paste sends clipboard text when invoked, and optional dashboard/budget AI features send compact aggregate summaries.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Google may use free-tier prompts and outputs to improve its products. Use a paid API tier if you require different data-use terms.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Section(header: Text("Help & Support")) {
                        Button {
                            tutorialManager.startTutorial()
                        } label: {
                            Label("Replay Tutorial", systemImage: "play.circle")
                        }
                        
                        NavigationLink {
                            ChatThreadListView(mode: .help)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Ask AI how to use this app", systemImage: "sparkles")
                                Text("I know every feature and can guide you step-by-step.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section("About") {
                        HStack {
                            Text("Finlytics")
                                .fontWeight(.medium)
                            Spacer()
                            Text("v1.2.1")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Settings")
            .onAppear {
                if aiProvider == "gemini" {
                    aiModel = GeminiRESTClient.normalizedModel(aiModel)
                }
                if let gKey = KeychainHelper.shared.read(for: "gemini_api_key") {
                    geminiApiKey = gKey
                }
                if let oKey = KeychainHelper.shared.read(for: "openai_api_key") {
                    openAIApiKey = oKey
                }
            }
            .alert("Configuration Saved", isPresented: $isSaved) {
                Button("OK", role: .cancel) { }
            }
            .alert("How to Get API Key", isPresented: $showAPIKeyHelp) {
                Button("OK", role: .cancel) { }
            } message: {
                if aiProvider == "gemini" {
                    Text("1. Go to aistudio.google.com\n2. Sign in with Google\n3. Click 'Get API Key'\n4. Copy and paste here")
                } else {
                    Text("1. Go to platform.openai.com\n2. Sign in or create an account\n3. Go to API Keys\n4. Generate new secret key and paste here")
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(
            for: [
                Transaction.self,
                Budget.self,
                Project.self,
                Insight.self,
                MerchantProfile.self,
                ChatThread.self,
                ChatMessage.self
            ],
            inMemory: true
        )
        .environmentObject(TutorialManager.shared)
}
