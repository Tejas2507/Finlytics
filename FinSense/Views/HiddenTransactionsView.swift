import SwiftUI
import SwiftData
import LocalAuthentication

struct HiddenTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Project.dateCreated, order: .reverse) private var allProjects: [Project]
    
    @State private var isAuthenticated = false
    @State private var authError: String?
    @State private var showAuthError = false
    
    var hiddenTransactions: [Transaction] {
        allTransactions.filter { $0.isHidden }
    }
    
    var hiddenProjects: [Project] {
        allProjects.filter { $0.isHidden }
    }
    
    var body: some View {
        Group {
            if isAuthenticated {
                authenticatedView
            } else {
                lockScreenView
            }
        }
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Authentication Failed", isPresented: $showAuthError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authError ?? "Unable to verify your identity.")
        }
    }
    
    // MARK: - Lock Screen
    private var lockScreenView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Protected Area")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Authenticate to view hidden items")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                authenticate()
            } label: {
                HStack {
                    Image(systemName: "faceid")
                    Text("Unlock")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: 200)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            
            Spacer()
            Spacer()
        }
        .onAppear {
            authenticate()
        }
    }
    
    // MARK: - Authenticated Content
    private var authenticatedView: some View {
        Group {
            if hiddenTransactions.isEmpty && hiddenProjects.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "eye.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No hidden items")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Swipe right on transactions or projects to hide them")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
            } else {
                List {
                    // Hidden Projects
                    if !hiddenProjects.isEmpty {
                        Section(header: Text("Hidden Projects"), footer: Text("Swipe to unhide. Transactions inside a hidden project remain visible.")) {
                            ForEach(hiddenProjects) { project in
                                HStack(spacing: 12) {
                                    Text(project.emoji)
                                        .font(.title2)
                                        .frame(width: 36, height: 36)
                                        .background(Color(.systemGray5))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(project.dateCreated.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if project.targetBudget > 0 {
                                        Text(project.targetBudget, format: .currency(code: "INR"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        withAnimation { project.isHidden = false }
                                    } label: {
                                        Label("Unhide", systemImage: "eye.fill")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    }
                    
                    // Hidden Transactions
                    if !hiddenTransactions.isEmpty {
                        Section(footer: Text("Swipe left to unhide a transaction. Hidden items are still included in all calculations and analytics.")) {
                            ForEach(hiddenTransactions) { transaction in
                                HStack {
                                    Image(systemName: Category.icon(for: transaction.category))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Category.color(for: transaction.category))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(transaction.merchant)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(transaction.amount, format: .currency(code: "INR"))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(transaction.type == .income ? .green : .primary)
                                }
                                .padding(.vertical, 2)
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        withAnimation {
                                            transaction.isHidden = false
                                        }
                                    } label: {
                                        Label("Unhide", systemImage: "eye.fill")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    // MARK: - Biometric / Passcode Auth
    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Access hidden transactions") { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isAuthenticated = true
                        }
                    } else {
                        authError = authenticationError?.localizedDescription ?? "Authentication failed"
                        showAuthError = true
                    }
                }
            }
        } else {
            // No biometrics/passcode — show error
            authError = "Your device doesn't have a passcode or biometric authentication set up."
            showAuthError = true
        }
    }
}

#Preview {
    NavigationView {
        HiddenTransactionsView()
            .modelContainer(for: Transaction.self, inMemory: true)
    }
}
