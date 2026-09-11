import SourceSortCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 6)

            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 2)
            if model.recent.isEmpty {
                Text("Sorted downloads will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.recent) { RecentRow(entry: $0) }
            }

            Divider().padding(.vertical, 6)
            Group {
                Button("Open SourceSort…") { open(.rules) }.keyboardShortcut("o")
                Button(model.isPaused ? "Resume Sorting" : "Pause Sorting") { model.isPaused.toggle() }
                    .keyboardShortcut("p")
                Divider().padding(.vertical, 4)
                Button("Quit SourceSort") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .buttonStyle(MenuItemButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .frame(width: 340)
        .onAppear { model.openWindowAction = { openWindow(id: "main") } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("SourceSort").font(.headline)
                Text(model.folders.map(\.url.lastPathComponent).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 9)
    }

    private var statusText: String {
        model.isPaused ? "Paused" : model.folders.isEmpty ? "No folders" : "Active"
    }

    private var statusColor: Color {
        model.isPaused ? .orange : model.folders.isEmpty ? .gray : .green
    }

    private func open(_ section: SidebarSection) {
        model.section = section
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate()
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let entry: ActivityEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: entry.icon).resizable().frame(width: 26, height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.fileName).lineLimit(1).truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(entry.outcome == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if entry.canUndo {
                Button("Undo") { model.undo(entry) }
                    .controlSize(.small)
                    .accessibilityLabel("Undo moving \(entry.fileName)")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu { Button("Show in Finder") { entry.revealInFinder() } }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        let parts = [entry.sourceDomain, entry.resultText, entry.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// Full-width rows that highlight on hover, like a native menu.
struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(hovering && isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering && isEnabled ? Color.accentColor : .clear))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
