import SwiftUI

struct GameruleEditorView: View {
    let runtime: ServerRuntime
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var showFavoritesOnly = false

    private var categories: [String] {
        ["All"] + Array(Set(runtime.gamerules.map(\.category))).sorted()
    }

    private var filteredRules: [GameruleEntry] {
        runtime.gamerules.filter { rule in
            (selectedCategory == "All" || rule.category == selectedCategory) &&
            (!showFavoritesOnly || rule.favorite) &&
            (searchText.isEmpty || rule.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionHeader(title: "Gamerule Editor", subtitle: "Search, favorite, validate and apply boolean or integer gamerules.", symbolName: "switch.2")
                Spacer()
                Button("Import", systemImage: "square.and.arrow.down") { runtime.importGamerules() }
                Button("Export", systemImage: "square.and.arrow.up") { runtime.exportGamerules() }
            }
            .padding(24)
            Divider().opacity(0.35)

            HStack(spacing: 16) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 220)
                Toggle("Favorites", isOn: $showFavoritesOnly)
                TextField("Search gamerules", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await runtime.refreshGamerules() } }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            if filteredRules.isEmpty {
                ContentUnavailableView("No Gamerules", systemImage: "switch.2", description: Text("Use rpc.discover and minecraft:gamerules to populate this editor."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredRules) { rule in
                            GameruleRow(runtime: runtime, rule: rule)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

private struct GameruleRow: View {
    let runtime: ServerRuntime
    let rule: GameruleEntry
    @State private var booleanValue = false
    @State private var integerValue: Int = 0
    @State private var stringValue = ""

    var body: some View {
        HStack(spacing: 14) {
            Button { runtime.toggleFavorite(rule) } label: {
                Image(systemName: rule.favorite ? "star.fill" : "star")
                    .foregroundStyle(rule.favorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.headline)
                HStack {
                    Text(rule.category)
                    Text("•")
                    Text(rule.type.label)
                    Text("•")
                    Text("Updated \(rule.updatedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            editor
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.10)))
        .onAppear { syncLocalState() }
        .onChange(of: rule.value) { _, _ in syncLocalState() }
    }

    @ViewBuilder
    private var editor: some View {
        switch rule.type {
        case .boolean:
            Toggle("", isOn: $booleanValue)
                .labelsHidden()
                .onChange(of: booleanValue) { _, newValue in
                    guard newValue != rule.boolValue else { return }
                    runtime.updateGamerule(rule, value: .bool(newValue))
                }
        case .integer:
            HStack {
                Button {
                    integerValue -= 1
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(integerValue == Int.min)

                TextField("Value", value: $integerValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)

                Button {
                    integerValue += 1
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(integerValue == Int.max)

                Button("Apply") { runtime.updateGamerule(rule, value: .number(Double(integerValue))) }
            }
        case .string:
            HStack {
                TextField("Value", text: $stringValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Apply") { runtime.updateGamerule(rule, value: .string(stringValue)) }
            }
        }
    }

    private func syncLocalState() {
        booleanValue = rule.boolValue
        integerValue = rule.intValue
        stringValue = rule.stringValue
    }
}
