import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    @AppStorage("appTheme") private var appTheme: String = "System"
    @AppStorage("aiModel") private var aiModel: String = "gemini-2.5-flash"
    
    @State private var apiKey: String = ""
    @State private var isSaved: Bool = false
    @State private var isImporting: Bool = false
    @State private var showImportAlert: Bool = false
    @State private var importMessage: String = ""
    
    // Demo Data
    @State private var isSeeding = false
    @State private var showAPIKeyHelp = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        Text("System").tag("System")
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Monthly Income") {
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
                    
                    if monthlySalary > 0 {
                        Text("₹\(Int(monthlySalary).formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: HStack {
                    Text("AI Configuration")
                    Spacer()
                    Button {
                        showAPIKeyHelp = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                }) {
                    Picker("Model", selection: $aiModel) {
                        Text("Flash (Fast)").tag("gemini-2.5-flash")
                        Text("Pro (Smart)").tag("gemini-2.5-pro")
                    }
                    
                    SecureField("Gemini API Key", text: $apiKey)
                        .textContentType(.password)
                    
                    Button("Save Key") {
                        KeychainHelper.shared.save(apiKey, for: "gemini_api_key")
                        isSaved = true
                    }
                    .disabled(apiKey.isEmpty)
                }
                
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
                
                Section("Developer Options") {
                    Button(action: seedDemoData) {
                        HStack {
                            Text("Generate Demo Data (3 Months)")
                            if isSeeding {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSeeding)
                }
                
                Section("About") {
                    Text("Finlytics Local-First v1.0")
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
    
    private func seedDemoData() {
        isSeeding = true
        Task {
            DataSeeder.shared.generateDemoData(modelContext: modelContext)
            await MainActor.run {
                importMessage = "Added 3 months of test data!"
                showImportAlert = true
                isSeeding = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
