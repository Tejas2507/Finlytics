import SwiftUI
import SwiftData
import GoogleGenerativeAI
import Combine

struct Message: Identifiable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

struct AIInsightsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @EnvironmentObject var tutorialManager: TutorialManager
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    
    let isHelpMode: Bool
    
    @State private var messages: [Message]
    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @FocusState private var isInputFocused: Bool
    
    init(isHelpMode: Bool = false) {
        self.isHelpMode = isHelpMode
        let initialText = isHelpMode ? 
            "Hello! I'm here to help you get the most out of Finlytics. Ask me anything about how the app works!" :
            "Hello! I'm your Finlytics assistant. How can I help you manage your finances today?"
        
        _messages = State(initialValue: [Message(text: initialText, isUser: false)])
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isGenerating {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: isGenerating) { _, _ in
                    if isGenerating {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Bar
            VStack(spacing: 0) {
                Divider().opacity(0.3)
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask anything...", text: $inputText, axis: .vertical)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                        .focused($isInputFocused)
                        .lineLimit(1...4)
                    
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                inputText.isEmpty || isGenerating ?
                                AnyShapeStyle(Color.gray.opacity(0.4)) :
                                AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .clipShape(Circle())
                    }
                    .disabled(inputText.isEmpty || isGenerating)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .tutorialTarget(.aiChat)
            }
            .background(.ultraThinMaterial)
        }
        .navigationTitle(isHelpMode ? "App Help Guide" : "Financial Strategist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    messages = [Message(text: "Chat cleared. How can I help?", isUser: false)]
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let userMsg = Message(text: text, isUser: true)
        messages.append(userMsg)
        inputText = ""
        isGenerating = true
        
        // Append User to Chat Memory Buffer
        var buffer = UserDefaults.standard.stringArray(forKey: "chatHistoryBuffer") ?? []
        buffer.append("User: \(text)")
        UserDefaults.standard.set(buffer, forKey: "chatHistoryBuffer")
        
        tutorialManager.completeStep(.aiChat)
        
        Task {
            do {
                let response = try await AIManager.shared.generateResponse(
                    for: text,
                    context: transactions,
                    budgets: budgets,
                    monthlySalary: monthlySalary,
                    isHelpMode: isHelpMode
                )
                
                await MainActor.run {
                    withAnimation {
                        messages.append(Message(text: response, isUser: false))
                        isGenerating = false
                    }
                    
                    // Append AI to Chat Memory Buffer
                    var buffer = UserDefaults.standard.stringArray(forKey: "chatHistoryBuffer") ?? []
                    buffer.append("AI: \(response)")
                    UserDefaults.standard.set(buffer, forKey: "chatHistoryBuffer")
                    
                    // Trigger summarization if we hit 50 messages (25 interactions) to utilize long context
                    if buffer.count >= 50 {
                        AIPersonaEngine.shared.summarizeRecentChats()
                    }
                }
            } catch {
                await MainActor.run {
                    messages.append(Message(text: "Error: \(error.localizedDescription)", isUser: false))
                    isGenerating = false
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 40) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                FormattedMessageView(content: message.text, isUser: message.isUser)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser ?
                        AnyShapeStyle(LinearGradient(colors: [.indigo, .purple.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                        AnyShapeStyle(Color(.systemGray5))
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 6)
            }
            
            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}

// Custom View to parse and render Markdown + Tables
struct FormattedMessageView: View {
    let content: String
    let isUser: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseBlocks(from: content), id: \.self) { block in
                switch block {
                case .text(let string):
                    // Use standard AttributedString for markdown rendering. 
                    // SwiftUI's Text(AttributedString) handles spacing correctly if the source markdown is valid.
                    Text(try! AttributedString(markdown: string, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                        .fixedSize(horizontal: false, vertical: true)
                case .table(let rows):
                    TableView(rows: rows, isUser: isUser)
                }
            }
        }
    }
    
    enum ContentBlock: Hashable {
        case text(String)
        case table([String])
    }
    
    func parseBlocks(from text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentTable: [String] = []
        var currentText = ""
        
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                // Table row detected
                if !currentText.isEmpty {
                    blocks.append(.text(currentText))
                    currentText = ""
                }
                currentTable.append(line)
            } else {
                // Normal text detected
                if !currentTable.isEmpty {
                    blocks.append(.table(currentTable))
                    currentTable = []
                }
                // Preserve the newline explicitly for text blocks
                currentText += line + "\n"
            }
        }
        
        if !currentText.isEmpty { blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines))) }
        if !currentTable.isEmpty { blocks.append(.table(currentTable)) }
        
        return blocks
    }
}

struct TableView: View {
    let rows: [String]
    let isUser: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    let cells = row.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    
                    if !cells.isEmpty && !row.contains("---") {
                        GridRow {
                            ForEach(cells, id: \.self) { cell in
                                // Parse markdown in cells too!
                                Text(try! AttributedString(markdown: cell))
                                    .font(index == 0 ? .headline : .body) // Header bold
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        index == 0 ? Color.indigo.opacity(0.8) : // Header
                                        (isUser ? Color.white.opacity(0.2) : Color.primary.opacity(0.05)) // Rows
                                    )
                                    .foregroundColor(
                                        index == 0 ? .white : // Header Text
                                        (isUser ? .white : .primary) // Row Text
                                    )
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(isUser ? Color.black.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0
    
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.indigo.opacity(0.6))
                        .frame(width: 7, height: 7)
                        .offset(y: sin(phase + Double(index) * 0.8) * 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
            }
            Spacer()
        }
    }
}

struct QuickPrompt: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.indigo.opacity(0.1))
                .foregroundColor(.indigo)
                .cornerRadius(16)
        }
    }
}

#Preview {
    AIInsightsView()
}
