import SwiftUI
import SwiftData

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.dateCreated, order: .reverse) private var projects: [Project]
    @Query private var transactions: [Transaction]
    
    @State private var showingAdd = false
    @State private var showArchived = false
    @State private var searchText = ""
    
    var activeProjects: [Project] {
        let filtered = projects.filter { !$0.isArchived && !$0.isHidden }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var archivedProjects: [Project] {
        let filtered = projects.filter { $0.isArchived && !$0.isHidden }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    func totalSpent(for project: Project) -> Double {
        transactions
            .filter { $0.projectNames.contains(project.name) && $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        List {
            if activeProjects.isEmpty && archivedProjects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects Yet", systemImage: "tray.2.fill")
                } description: {
                    Text("Create a project to track spending on trips, events, etc.")
                } actions: {
                    Button("Create Project") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                }
            }
            
            if !activeProjects.isEmpty {
                Section("Active") {
                    ForEach(activeProjects) { project in
                        NavigationLink(destination: ProjectDetailView(project: project)) {
                            ProjectRowView(project: project, spent: totalSpent(for: project))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                withAnimation { project.isArchived = true }
                            } label: {
                                Label("Archive", systemImage: "archivebox.fill")
                            }
                            .tint(.orange)
                            
                            Button(role: .destructive) {
                                modelContext.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                withAnimation { project.isHidden = true }
                            } label: {
                                Label("Hide", systemImage: "eye.slash.fill")
                            }
                            .tint(.purple)
                        }
                    }
                }
            }
            
            if !archivedProjects.isEmpty {
                Section("Archived") {
                    ForEach(archivedProjects) { project in
                        NavigationLink(destination: ProjectDetailView(project: project)) {
                            ProjectRowView(project: project, spent: totalSpent(for: project))
                                .opacity(0.6)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                withAnimation { project.isArchived = false }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                // Also untag transactions
                                for tx in transactions where tx.projectNames.contains(project.name) {
                                    tx.projectNames.removeAll { $0 == project.name }
                                }
                                modelContext.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            
            Section {
                Button {
                    showingAdd = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.indigo)
                        Text("Create New Project")
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Projects")
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddProjectView()
        }
    }
}

// MARK: - Project Row
struct ProjectRowView: View {
    let project: Project
    let spent: Double
    
    var progress: Double {
        guard project.targetBudget > 0 else { return 0 }
        return min(spent / project.targetBudget, 1.0)
    }
    
    var progressColor: Color {
        if project.targetBudget <= 0 { return .indigo }
        if spent > project.targetBudget { return .red }
        if spent > project.targetBudget * 0.8 { return .orange }
        return .green
    }
    
    var body: some View {
        HStack(spacing: 14) {
            Text(project.emoji)
                .font(.title)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if project.targetBudget > 0 {
                    HStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [progressColor.opacity(0.7), progressColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(geo.size.width * progress, 4), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(spent, format: .currency(code: "INR"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if project.targetBudget > 0 {
                        Text("/ \(project.targetBudget, format: .currency(code: "INR"))")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Project Sheet
struct AddProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var emoji = "🎯"
    @State private var targetBudget: Double = 0
    
    let emojis = ["🎯", "✈️", "🏠", "💒", "🎓", "🎉", "🏖️", "🚗", "💻", "🎁", "🏥", "🍽️", "🛍️", "🏋️", "📱", "🎵"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Project Name") {
                    TextField("e.g. Goa Trip, Wedding", text: $name)
                }
                
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(emoji == e ? Color.indigo.opacity(0.3) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { emoji = e }
                        }
                    }
                }
                
                Section {
                    TextField("Target Budget (optional)", value: $targetBudget, format: .currency(code: "INR"))
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } header: {
                    Text("Budget Limit")
                } footer: {
                    Text("Set a spending limit to track progress. Leave empty or set to 0 for no limit.")
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let project = Project(name: name, emoji: emoji, targetBudget: targetBudget)
                        modelContext.insert(project)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
