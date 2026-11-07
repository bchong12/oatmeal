import SwiftUI

/// Settings › MCP: connect Claude, Cursor and other AI tools to your Oatmeal.
struct MCPSettingsTab: View {
    static let url = "http://127.0.0.1:29985/mcp"
    @State private var copied: String?
    @ObservedObject private var server = MCPServer.shared
    @ObservedObject private var claude = NoteWriters.shared

    private var clients: [(name: String, how: String, snippet: String)] {[
        ("Claude Code", "Run in Terminal", "claude mcp add --transport http oatmeal \(Self.url)"),
        ("Claude Desktop", "Settings › Developer › Edit Config, add to mcpServers", "\"oatmeal\": { \"command\": \"npx\", \"args\": [\"-y\", \"mcp-remote\", \"\(Self.url)\"] }"),
        ("Cursor", "~/.cursor/mcp.json, add to mcpServers", "\"oatmeal\": { \"url\": \"\(Self.url)\" }"),
        ("Codex", "~/.codex/config.toml", "[mcp_servers.oatmeal]\nurl = \"\(Self.url)\""),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 16))
                    .frame(width: 36, height: 36).background(DF.wash, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Oatmeal MCP server").font(DF.font(15, .bold))
                    Text("Lets your AI assistant read your day, add and finish tasks, check goals and search meetings. Runs on this Mac only, while Oatmeal is open.")
                        .font(DF.font(13)).foregroundStyle(DF.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(server.isRunning ? DF.thrivingInk : DF.faint).frame(width: 7, height: 7)
                    Text(server.isRunning ? (server.lastClient.map { "Connected · \($0)" } ?? "Running") : "Off").font(DF.font(12, .semibold)).foregroundStyle(DF.muted)
                }
                .padding(.horizontal, 10).frame(height: 26).background(DF.wash, in: Capsule())
            }
            .padding(20).dfCard()
            SettingsRow(icon: "sparkles", title: "Write meeting notes automatically",
                        sub: claude.available
                            ? "When a meeting ends, \(claude.active?.title ?? "your AI") fixes the transcript and writes the notes, on \(claude.active?.plan ?? "your plan")."
                            : "Needs Claude Code, Codex or Gemini CLI on this Mac, signed in with your own plan.",
                        last: true) {
                Toggle("", isOn: Binding(get: { claude.autoEnabled && claude.available }, set: { claude.autoEnabled = $0 }))
                    .toggleStyle(.df).disabled(!claude.available)
            }
            .dfCard()
            VStack(spacing: 0) {
                ForEach(Array(clients.enumerated()), id: \.offset) { i, c in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(c.name).font(DF.font(14, .semibold))
                            Text(c.how).font(DF.font(12)).foregroundStyle(DF.muted)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.snippet, forType: .string)
                                withAnimation(.snappy) { copied = c.name }
                            } label: {
                                Label(copied == c.name ? "Copied" : "Copy", systemImage: copied == c.name ? "checkmark" : "doc.on.doc").font(DF.font(12, .semibold))
                            }
                            .buttonStyle(.plain).foregroundStyle(DF.muted)
                        }
                        Text(c.snippet).font(.system(size: 12, design: .monospaced)).foregroundStyle(DF.ink)
                            .textSelection(.enabled)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(DF.canvas, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .overlay(alignment: .bottom) { if i < clients.count - 1 { Divider().overlay(DF.line).padding(.horizontal, 20) } }
                }
            }
            .dfCard()
        }
    }
}
