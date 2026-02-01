import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var tutorialManager: TutorialManager
    @Query private var transactions: [Transaction]
    
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    @AppStorage("appTheme") private var appTheme: String = "System"
    @AppStorage("aiModel") private var aiModel: String = "gemini-flash-lite-latest"
    
    @State private var apiKey: String = ""
    @State private var isSaved: Bool = false
    @State private var isImporting: Bool = false
    @State private var showImportAlert: Bool = false
    @State private var importMessage: String = ""
    
    @State private var showAPIKeyHelp = false
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                Form {
                    Section("Appearance") {
                        Picker("Theme", selection: $appTheme) {
                            Text("System").tag("System")
                            Text("Light").tag("Light")
                            Text("Dark").tag("Dark")
                        }
                        .pickerStyle(.segmented)
                    }
                    

                // Account & AI Setup (Unified Section for Tutorial)
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
                    .tutorialTarget(.settingsSetup)
                    
                    // AI Config Rows
                    Picker("AI Model", selection: $aiModel) {
                        Text("Gemini Flash Lite").tag("gemini-flash-lite-latest")
                        Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                    }
                    .tutorialTarget(.settingsSetup)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gemini API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("Paste API Key here", text: $apiKey)
                            .textContentType(.password)
                    }
                    .tutorialTarget(.settingsSetup)
                    
                    Button("Save Configuration") {
                        let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        KeychainHelper.shared.save(cleanedKey, for: "gemini_api_key")
                        apiKey = cleanedKey
                        isSaved = true
                        
                        if monthlySalary > 0 {
                            tutorialManager.completeStep(.settingsSetup)
                        }
                    }
                    .disabled(apiKey.isEmpty)
                    .tutorialTarget(.settingsSetup)
                }
                .id("settingsTop")
                
                Section("Data Management") {
                    ShareLink(item: generateExportFile(), preview: SharePreview("Finlytics Data", image: Image(systemName: "tablecells"))) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }
                }
                
                Section("Help") {
                    Button {
                        tutorialManager.startTutorial()
                    } label: {
                        Label("Run Tutorial", systemImage: "play.circle")
                    }
                }
                
                Section("About") {
                    Text("Finlytics Local-First v1.0")
                }
            }
                .onAppear {
                    // Auto-scroll to top when tutorial is active
                    if tutorialManager.currentStep == .settingsSetup {
                        withAnimation {
                            proxy.scrollTo("settingsTop", anchor: .top)
                        }
                    }
                }
                .onChange(of: tutorialManager.currentStep) { step in
                    if step == .settingsSetup {
                        withAnimation {
                            proxy.scrollTo("settingsTop", anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if let key = KeychainHelper.shared.read(for: "gemini_api_key") {
                    apiKey = key
                }
            }
            .alert("Configuration Saved", isPresented: $isSaved) {
                Button("OK", role: .cancel) { }
            }
            .alert("How to Get API Key", isPresented: $showAPIKeyHelp) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("1. Go to aistudio.google.com\n2. Sign in with Google\n3. Click 'Get API Key'\n4. Copy and paste here")
            }
            .alert("Import Result", isPresented: $showImportAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importMessage)
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                switch result {
                case .success(let url):
                    importData(from: url)
                case .failure(let error):
                    importMessage = "Import failed: \(error.localizedDescription)"
                    showImportAlert = true
                }
            }
        }
    }
    
    // Helpers
    @MainActor
    private func generateExportFile() -> URL {
        let csv = CSVManager.shared.generateCSV(from: transactions)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Finlytics_Export_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).csv")
        try? csv.write(to: temp, atomically: true, encoding: .utf8)
        return temp
    }
    
    private func importData(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importMessage = "Permission denied to access file."
            showImportAlert = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let transactions = try CSVManager.shared.parseCSV(from: url)
            var count = 0
            for tx in transactions {
                modelContext.insert(tx)
                count += 1
            }
            importMessage = "Successfully imported \(count) transactions."
            showImportAlert = true
        } catch {
            importMessage = "Error parsing CSV: \(error.localizedDescription)"
            showImportAlert = true
        }
    }
    

}

#Preview {
    SettingsView()
}
