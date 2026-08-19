import SwiftUI
import SwiftData

struct AIInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tutorialManager: TutorialManager

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @Query private var projects: [Project]
    @Query private var merchantProfiles: [MerchantProfile]

    @Bindable var thread: ChatThread

    @State private var inputText = ""
    @State private var generationTask: Task<Void, Never>?
    @State private var evidenceTransactionIDs: [UUID] = []
    @State private var showingDeleteConfirmation = false
    @State private var showingThreadMemory = false
    @FocusState private var isInputFocused: Bool
    
    private var visibleMessages: [ChatMessage] {
        thread.messages
            .filter { $0.status != .superseded }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var isGenerating: Bool {
        generationTask != nil ||
        visibleMessages.contains { $0.status == .pending || $0.status == .streaming }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if visibleMessages.isEmpty {
                            emptyState
                        }

                        ForEach(visibleMessages) { message in
                            PersistentChatBubble(
                                message: message,
                                canRegenerate: canRegenerate(message),
                                onRetry: { retry(message) },
                                onRegenerate: { regenerate(message) },
                                onDelete: { deleteMessage(message) },
                                onShowEvidence: { result in
                                    evidenceTransactionIDs = result.evidence.transactionIDs
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: visibleMessages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: visibleMessages.last?.content) { _, _ in
                    scrollToBottom(proxy, animated: false)
                }
            }

            inputBar
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingThreadMemory = true
                    } label: {
                        Label("Thread Memory", systemImage: "brain.head.profile")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                generationTask?.cancel()
                modelContext.delete(thread)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("The thread and all of its messages will be removed from this device.")
        }
        .sheet(
            isPresented: Binding(
                get: { !evidenceTransactionIDs.isEmpty },
                set: { if !$0 { evidenceTransactionIDs = [] } }
            )
        ) {
            EvidenceTransactionsView(transactionIDs: evidenceTransactionIDs)
        }
        .sheet(isPresented: $showingThreadMemory) {
            ThreadMemoryView(thread: thread)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: thread.mode == .financial ? "sparkles" : "questionmark.bubble.fill")
                .font(.system(size: 42))
                .foregroundStyle(.indigo)

            VStack(spacing: 6) {
                Text(thread.mode == .financial ? "Ask about your finances" : "Ask about Finlytics")
                    .font(.title3.weight(.semibold))
                Text(
                    thread.mode == .financial
                        ? "Totals and comparisons are calculated locally from matched transactions."
                        : "This chat knows the app manual but never receives your financial data."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            if thread.mode == .financial {
                VStack(spacing: 8) {
                    promptChip("How much did I spend on online food delivery apps this month?")
                    promptChip("Compare Food & Dining this month with last month")
                    promptChip("Show my top merchants this month")
                    promptChip("How close am I to my budgets?")
                }
            } else {
                VStack(spacing: 8) {
                    promptChip("How do I hide a project in the Vault?")
                    promptChip("How does Smart Paste work?")
                    promptChip("How do I create a budget?")
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 42)
    }

    private func promptChip(_ prompt: String) -> some View {
        Button {
            sendMessage(prompt)
        } label: {
            Text(prompt)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    thread.mode == .financial ? "Ask about your transactions…" : "Ask how the app works…",
                    text: $inputText,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 18))
                .disabled(isGenerating)

                Button {
                    if isGenerating {
                        cancelGeneration()
                    } else {
                        sendMessage(inputText)
                    }
                } label: {
                    Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            isGenerating || !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.indigo
                                : Color.gray.opacity(0.45),
                            in: Circle()
                        )
                }
                .disabled(!isGenerating && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .tutorialTarget(.aiChat)
        }
        .background(.ultraThinMaterial)
    }

    private func sendMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        isInputFocused = false
        tutorialManager.completeStep(.aiChat)
        
        let userMessage = ChatMessage(
            role: .user,
            content: text,
            status: .completed
        )
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            status: .pending,
            replyToMessageID: userMessage.id
        )
        modelContext.insert(userMessage)
        modelContext.insert(assistantMessage)
        thread.messages.append(userMessage)
        thread.messages.append(assistantMessage)
        thread.touch()
        try? modelContext.save()

        startGeneration(userMessage: userMessage, assistantMessage: assistantMessage)
    }

    private func startGeneration(
        userMessage: ChatMessage,
        assistantMessage: ChatMessage
    ) {
        generationTask = Task { @MainActor in
            await ChatOrchestrator.shared.generateReply(
                thread: thread,
                userMessage: userMessage,
                assistantMessage: assistantMessage,
                transactions: transactions,
                budgets: budgets,
                projects: projects,
                merchantProfiles: merchantProfiles,
                modelContext: modelContext
            )
            generationTask = nil
        }
    }

    private func retry(_ assistantMessage: ChatMessage) {
        guard !isGenerating,
              canRegenerate(assistantMessage),
              let userID = assistantMessage.replyToMessageID,
              let userMessage = thread.messages.first(where: { $0.id == userID }) else {
            return
        }

        assistantMessage.content = ""
        assistantMessage.status = .pending
        assistantMessage.errorCode = nil
        assistantMessage.errorMessage = nil
        try? modelContext.save()
        startGeneration(userMessage: userMessage, assistantMessage: assistantMessage)
    }

    private func regenerate(_ assistantMessage: ChatMessage) {
        guard !isGenerating,
              canRegenerate(assistantMessage),
              assistantMessage.role == .assistant,
              let userID = assistantMessage.replyToMessageID,
              let userMessage = thread.messages.first(where: { $0.id == userID }) else {
            return
        }

        assistantMessage.status = .superseded
        let replacement = ChatMessage(
            role: .assistant,
            content: "",
            status: .pending,
            replyToMessageID: userID,
            regenerationGroupID: assistantMessage.regenerationGroupID ?? assistantMessage.id
        )
        replacement.queryPlan = assistantMessage.queryPlan
        modelContext.insert(replacement)
        thread.messages.append(replacement)
        thread.touch()
        try? modelContext.save()
        startGeneration(userMessage: userMessage, assistantMessage: replacement)
    }

    private func canRegenerate(_ message: ChatMessage) -> Bool {
        message.role == .assistant &&
        visibleMessages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    private func deleteMessage(_ message: ChatMessage) {
        guard !isGenerating else { return }
        if message.role == .user {
            let replies = thread.messages.filter { $0.replyToMessageID == message.id }
            for reply in replies {
                modelContext.delete(reply)
            }
        }
        modelContext.delete(message)
        thread.rollingSummary = ""
        thread.summaryThroughDate = nil
        thread.lastQuery = nil
        thread.touch()
        try? modelContext.save()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastID = visibleMessages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct ThreadMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var thread: ChatThread

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if thread.rollingSummary.isEmpty {
                        Text("No older messages have been summarized yet. Recent messages are used directly within a small context window.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(thread.rollingSummary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Saved Thread Summary")
                } footer: {
                    Text("This summary is stored on this device and contains only explicit conversation facts for continuity. It is never a hidden personality profile.")
                }

                if !thread.rollingSummary.isEmpty || thread.lastQuery != nil {
                    Section {
                        Button("Clear Saved Memory", role: .destructive) {
                            thread.rollingSummary = ""
                            thread.summaryThroughDate = thread.messages
                                .filter { $0.status == .completed }
                                .map(\.createdAt)
                                .max()
                            thread.lastQuery = nil
                            thread.touch()
                            try? modelContext.save()
                        }
                    }
                }
            }
            .navigationTitle("Thread Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PersistentChatBubble: View {
    @Bindable var message: ChatMessage
    let canRegenerate: Bool
    let onRetry: () -> Void
    let onRegenerate: () -> Void
    let onDelete: () -> Void
    let onShowEvidence: (FinanceQueryResult) -> Void
    
    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 42) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 7) {
                if message.status == .pending && message.content.isEmpty {
                    TypingDots()
                } else {
                    ChatMarkdownText(text: message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                            message.role == .user
                                ? Color.indigo
                                : Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                }

                if let evidence = message.evidence, message.role == .assistant {
                    FinanceEvidenceCard(result: evidence) {
                        onShowEvidence(evidence)
                    }
                }

                HStack(spacing: 8) {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if message.status == .streaming {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    if (message.status == .failed || message.status == .cancelled) &&
                        canRegenerate {
                        Button("Retry", action: onRetry)
                            .font(.caption.weight(.semibold))
                    } else if canRegenerate && message.status == .completed {
                        Button(action: onRegenerate) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Regenerate response")
                    }
                }
                .padding(.horizontal, 5)
            }

            if message.role != .user { Spacer(minLength: 42) }
        }
        .contextMenu {
            if canRegenerate && message.status == .completed {
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete Message", systemImage: "trash")
            }
        }
    }
}

private struct ChatMarkdownText: View {
    let text: String
    
    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                        .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TypingDots: View {
    @State private var opacity = 0.35

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { _ in
                Circle()
                    .fill(Color.indigo)
                    .frame(width: 6, height: 6)
            }
        }
        .opacity(opacity)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                opacity = 1
            }
        }
    }
}

private struct FinanceEvidenceCard: View {
    let result: FinanceQueryResult
    let showTransactions: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Verified locally", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Text(result.evidence.periodLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let amount = result.primaryAmount {
                Text(formattedValue(amount))
                    .font(.title3.weight(.bold))
            }

            if let previous = result.comparisonAmount,
               let label = result.evidence.comparisonPeriodLabel {
                Text("\(label): \(formattedValue(previous))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !result.groups.isEmpty {
                Divider()
                ForEach(result.groups.prefix(4)) { group in
                    HStack {
                        Text(group.label)
                            .lineLimit(1)
                        Spacer()
                        Text(formattedValue(group.amount))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
            }

            Button(action: showTransactions) {
                Label(
                    "View \(result.evidence.primaryCount) matched \(result.evidence.primaryCount == 1 ? "transaction" : "transactions")",
                    systemImage: "list.bullet.rectangle"
                )
                .font(.caption.weight(.semibold))
            }
            .disabled(result.evidence.transactionIDs.isEmpty)

            Text(result.evidence.calculation)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func currency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "₹0"
    }

    private func formattedValue(_ amount: Decimal) -> String {
        guard result.query.metric == .transactionCount else {
            return currency(amount)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }
}

private struct EvidenceTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    let transactionIDs: [UUID]

    private var transactions: [Transaction] {
        let idSet = Set(transactionIDs)
        return allTransactions.filter { idSet.contains($0.id) && !$0.isHidden }
    }
    
    var body: some View {
        NavigationStack {
            List(transactions) { transaction in
                HStack(spacing: 12) {
                    Image(systemName: Category.icon(for: transaction.category))
                        .foregroundStyle(Category.color(for: transaction.category))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(transaction.merchant)
                            .fontWeight(.medium)
                        Text("\(transaction.category) · \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(transaction.amount, format: .currency(code: "INR").precision(.fractionLength(0)))
                        .fontWeight(.semibold)
                }
            }
            .navigationTitle("Matched Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
