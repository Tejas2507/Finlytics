import SwiftUI
import SwiftData

struct ChatThreadListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var allThreads: [ChatThread]

    let mode: ChatMode

    @State private var presentedThread: ChatThread?
    @State private var threadToRename: ChatThread?
    @State private var renameText = ""

    private var threads: [ChatThread] {
        allThreads.filter { !$0.isArchived && $0.mode == mode }
    }

    var body: some View {
        List {
            if threads.isEmpty {
                ContentUnavailableView {
                    Label(
                        mode == .financial ? "No Financial Chats" : "No Help Chats",
                        systemImage: mode == .financial ? "sparkles" : "questionmark.bubble"
                    )
                } description: {
                    Text(
                        mode == .financial
                            ? "Start a thread for verified answers about your transactions."
                            : "Start a thread for step-by-step app guidance."
                    )
                } actions: {
                    Button("New Chat", action: createThread)
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(threads) { thread in
                    NavigationLink {
                        AIInsightsView(thread: thread)
                    } label: {
                        ChatThreadRow(thread: thread)
                    }
                    .contextMenu {
                        Button {
                            beginRename(thread)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(thread)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            delete(thread)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            beginRename(thread)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
                }
            }
        }
        .navigationTitle(mode == .financial ? "AI Chat" : "App Help")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createThread) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { presentedThread != nil },
                set: { if !$0 { presentedThread = nil } }
            )
        ) {
            if let presentedThread {
                AIInsightsView(thread: presentedThread)
            }
        }
        .alert(
            "Rename Chat",
            isPresented: Binding(
                get: { threadToRename != nil },
                set: { if !$0 { threadToRename = nil } }
            )
        ) {
            TextField("Chat title", text: $renameText)
            Button("Cancel", role: .cancel) {
                threadToRename = nil
            }
            Button("Save", action: saveRename)
        }
    }

    private func createThread() {
        let thread = ChatThread(mode: mode)
        modelContext.insert(thread)
        try? modelContext.save()
        presentedThread = thread
    }

    private func beginRename(_ thread: ChatThread) {
        threadToRename = thread
        renameText = thread.title
    }

    private func saveRename() {
        let cleaned = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let threadToRename, !cleaned.isEmpty {
            threadToRename.title = cleaned
            threadToRename.touch()
            try? modelContext.save()
        }
        threadToRename = nil
    }

    private func delete(_ thread: ChatThread) {
        if presentedThread?.id == thread.id {
            presentedThread = nil
        }
        modelContext.delete(thread)
        try? modelContext.save()
    }
}

private struct ChatThreadRow: View {
    let thread: ChatThread

    private var latestMessage: ChatMessage? {
        thread.messages
            .filter { $0.status != .superseded }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    private var previewText: String {
        guard let latestMessage, !latestMessage.content.isEmpty else {
            return "No messages yet"
        }
        return latestMessage.content
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: thread.mode == .financial ? "sparkles" : "questionmark.bubble.fill")
                .foregroundStyle(.indigo)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(thread.updatedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
