import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var tutorialManager: TutorialManager
    @Query private var transactions: [Transaction]
    
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    @AppStorage("aiProvider") private var aiProvider: String = "gemini"
    @AppStorage("aiModel") private var aiModel: String = "gemini-flash-lite-latest"
    
    @State private var geminiApiKey: String = ""
    @State private var openAIApiKey: String = ""
    @State private var isSaved: Bool = false
    
    @State private var showAPIKeyHelp = false
    
    var body: some View {
        NavigationView {
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
                                aiModel = "gemini-flash-lite-latest"
                            } else {
                                aiModel = "gpt-4o-mini"
                            }
                        }
                        
                        // AI Config Rows
                        Picker("AI Model", selection: $aiModel) {
                            if aiProvider == "gemini" {
                                Text("Gemini Flash Lite").tag("gemini-flash-lite-latest")
                                Text("Gemini Flash Latest").tag("gemini-flash-latest")
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
                    }
                    
                    Section(header: Text("Help & Support")) {
                        Button {
                            tutorialManager.startTutorial()
                        } label: {
                            Label("Replay Tutorial", systemImage: "play.circle")
                        }
                        
                        NavigationLink {
                             AIInsightsView(isHelpMode: true)
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
}
