import SwiftUI
import SwiftData

struct MerchantProfilesView: View {
    @Query(sort: \MerchantProfile.displayName) private var profiles: [MerchantProfile]
    @Query private var transactions: [Transaction]
    @State private var searchText = ""

    private var visibleProfiles: [MerchantProfile] {
        var keys = Set(
            transactions
                .filter { !$0.isHidden }
                .compactMap(\.canonicalMerchantKey)
        )
        for transaction in transactions where !transaction.isHidden {
            if let key = MerchantResolver.shared.resolveKey(
                for: transaction.merchant,
                profiles: profiles
            ) {
                keys.insert(key)
            }
        }
        return profiles.filter { keys.contains($0.canonicalKey) }
    }

    private var filteredProfiles: [MerchantProfile] {
        guard !searchText.isEmpty else { return visibleProfiles }
        return visibleProfiles.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.aliases.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredProfiles) { profile in
                    NavigationLink {
                        MerchantProfileEditor(profile: profile)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(profile.displayName)
                                    .font(.headline)
                                if profile.isUserOverride {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.indigo)
                                }
                            }
                            Text(
                                profile.tags.isEmpty
                                    ? "Unclassified"
                                    : profile.tags.map(tagLabel).joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(profile.tags.isEmpty ? Color.secondary : Color.indigo)
                        }
                        .padding(.vertical, 3)
                    }
                }
            } footer: {
                Text("Merchant groups power questions such as “food delivery apps.” Corrections stay on this device and always override AI classification.")
            }
        }
        .navigationTitle("Merchant Groups")
        .searchable(text: $searchText, prompt: "Search merchants")
    }

    private func tagLabel(_ tag: String) -> String {
        tag
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }
}

private struct MerchantProfileEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: MerchantProfile
    @State private var aliasesText: String

    private let availableTags = Array(
        Set(MerchantResolver.seedProfiles.flatMap(\.tags))
    ).sorted()

    init(profile: MerchantProfile) {
        self.profile = profile
        _aliasesText = State(initialValue: profile.aliases.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section("Merchant") {
                TextField("Display name", text: $profile.displayName)
                TextField("Aliases, separated by commas", text: $aliasesText, axis: .vertical)
            }

            Section {
                ForEach(availableTags, id: \.self) { tag in
                    Toggle(
                        tagLabel(tag),
                        isOn: Binding(
                            get: { profile.tags.contains(tag) },
                            set: { enabled in
                                if enabled {
                                    if !profile.tags.contains(tag) {
                                        profile.tags.append(tag)
                                    }
                                } else {
                                    profile.tags.removeAll { $0 == tag }
                                }
                                markOverridden()
                            }
                        )
                    )
                }
            } header: {
                Text("Semantic Groups")
            } footer: {
                Text("Remove all groups when this merchant should not be included in any semantic merchant query.")
            }

            Section("Default Category") {
                Picker(
                    "Category",
                    selection: Binding(
                        get: { profile.defaultCategory ?? "Other" },
                        set: {
                            profile.defaultCategory = $0
                            markOverridden()
                        }
                    )
                ) {
                    ForEach(Category.expenseCategories, id: \.self) {
                        Text($0).tag($0)
                    }
                }
            }
        }
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile.displayName) { _, _ in
            markOverridden()
        }
        .onChange(of: aliasesText) { _, newValue in
            profile.aliases = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            markOverridden()
        }
    }

    private func markOverridden() {
        profile.isUserOverride = true
        profile.confidence = 1
        profile.updatedAt = Date()
        try? modelContext.save()
    }

    private func tagLabel(_ tag: String) -> String {
        tag
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }
}
