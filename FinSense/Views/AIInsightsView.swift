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
    @AppStorage("monthlySalary") private var monthlySalary: Double = 0.0
    
    @State private var messages: [Message] = [
        Message(text: "Hello! I'm your Finlytics assistant. How can I help you manage your finances today?", isUser: false)
    ]
    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if isGenerating {
                                TypingIndicator()
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: isGenerating) { _, _ in
                        if isGenerating {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input Area
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask anything...", text: $inputText)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(20)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                    
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(inputText.isEmpty ? .gray : .indigo)
                    }
                    .disabled(inputText.isEmpty || isGenerating)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        messages = [Message(text: "Chat cleared. How can I help?", isUser: false)]
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                    }
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
        
        Task {
            let apiKey = KeychainHelper.shared.read(for: "gemini_api_key") ?? ""
            do {
                let response = try await GeminiService.shared.generateResponse(
                    for: text,
                    context: transactions,
                    budgets: budgets,
                    monthlySalary: monthlySalary,
                    apiKey: apiKey
                )
                
                await MainActor.run {
                    withAnimation {
                        messages.append(Message(text: response, isUser: false))
                        isGenerating = false
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
            if message.isUser { Spacer(minLength: 50) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                FormattedMessageView(content: message.text, isUser: message.isUser)
                    .padding(12)
                    .background(message.isUser ? Color.indigo : Color.gray.opacity(0.1))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !message.isUser { Spacer(minLength: 50) }
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
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(dotCount % 4 > index ? 1 : 0.3)
                    }
                }
                .padding(12)
            }
            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount += 1
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
