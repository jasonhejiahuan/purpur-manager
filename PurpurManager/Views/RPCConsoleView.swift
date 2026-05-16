import SwiftUI

struct RPCConsoleView: View {
    let runtime: ServerRuntime
    @State private var rawRequest = "{\n  \"jsonrpc\": \"2.0\",\n  \"id\": 1,\n  \"method\": \"minecraft:server/status\"\n}"
    @State private var responseText = ""
    @State private var selectedMethod: RPCMethodDescriptor?
    @State private var methodSearch = ""
    @State private var isSending = false

    private var filteredMethods: [RPCMethodDescriptor] {
        guard !methodSearch.isEmpty else { return runtime.methods }
        return runtime.methods.filter { $0.method.localizedCaseInsensitiveContains(methodSearch) || $0.summary.localizedCaseInsensitiveContains(methodSearch) }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "JSON-RPC Console", subtitle: "Send raw requests, replay history, save snippets and inspect discovered schemas.", symbolName: "terminal.fill")
                HStack {
                    Button("Format", systemImage: "wand.and.stars") { formatJSON() }
                    Button("Save Snippet", systemImage: "star") { saveSnippet() }
                    Button("Send", systemImage: "paperplane.fill") { send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSending)
                    if isSending { ProgressView().controlSize(.small) }
                }
                TextEditor(text: $rawRequest)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.10)))
                GroupBox("Response") {
                    ScrollView {
                        Text(responseText.isEmpty ? "Responses appear here." : responseText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 160)
                }
            }
            .padding(24)
            .frame(minWidth: 520)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Search methods", text: $methodSearch)
                    .textFieldStyle(.roundedBorder)
                List(selection: $selectedMethod) {
                    Section("Schema Explorer") {
                        ForEach(filteredMethods) { method in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(method.method).font(.caption.monospaced().weight(.semibold))
                                Text(method.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .tag(method as RPCMethodDescriptor?)
                            .contextMenu {
                                Button("Insert Request") { insert(method) }
                                Button("Copy Method") { copy(method.method) }
                            }
                        }
                    }
                    if !runtime.rpcHistory.isEmpty {
                        Section("History") {
                            ForEach(runtime.rpcHistory, id: \.self) { item in
                                Button { rawRequest = item } label: {
                                    Text(item.replacingOccurrences(of: "\n", with: " "))
                                        .lineLimit(1)
                                        .font(.caption.monospaced())
                                }
                            }
                        }
                    }
                    if !runtime.savedSnippets.isEmpty {
                        Section("Snippets") {
                            ForEach(runtime.savedSnippets, id: \.self) { item in
                                Button { rawRequest = item } label: { Text(item).lineLimit(1).font(.caption.monospaced()) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                if let selectedMethod {
                    GroupBox("Documentation") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedMethod.method).font(.headline.monospaced())
                            Text(selectedMethod.summary).foregroundStyle(.secondary)
                            if let schema = selectedMethod.paramsSchema {
                                Text("Params").font(.caption.weight(.bold))
                                Text(schema.prettyPrinted).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .frame(minWidth: 320)
            .background(.thinMaterial)
        }
    }

    private func send() {
        isSending = true
        responseText = "Sending…"
        Task {
            do {
                try await runtime.sendRaw(rawRequest)
                responseText = "Raw frame sent. Responses and events are visible in the WebSocket inspector."
            } catch {
                responseText = error.localizedDescription
            }
            isSending = false
        }
    }

    private func insert(_ method: RPCMethodDescriptor) {
        let request = RPCRequest(id: .int(Int.random(in: 1...9999)), method: method.method, params: method.paramsSchema == nil ? nil : .object([:]))
        if let data = try? JSONEncoder.pretty.encode(request), let text = String(data: data, encoding: .utf8) { rawRequest = text }
    }

    private func formatJSON() {
        guard let data = rawRequest.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let formatted = String(data: (try? JSONEncoder.pretty.encode(value)) ?? Data(), encoding: .utf8) else { return }
        rawRequest = formatted
    }

    private func saveSnippet() {
        runtime.savedSnippets.insert(rawRequest, at: 0)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
