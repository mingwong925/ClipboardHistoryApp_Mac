import SwiftUI
import AppKit

struct ClipboardHistoryView: View {
    @ObservedObject var manager: ClipboardManager

    var body: some View {
        VStack(spacing: 10) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 360, height: 520)
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.headline)
            Spacer()
            Button("Clear") {
                manager.clearHistory()
            }
            .buttonStyle(.bordered)
            .help("Clear all saved clipboard history")
        }
    }

    private var content: some View {
        Group {
            if manager.entries.isEmpty {
                VStack(spacing: 8) {
                    Text("No clipboard history yet.")
                        .foregroundColor(.secondary)
                    Text("Copy text or images to add entries.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.entries) { entry in
                            Button(action: {
                                manager.copyToPasteboard(entry)
                            }) {
                                rowView(for: entry)
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func rowView(for entry: ClipboardManager.ClipboardHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            icon(for: entry)
                .frame(width: 50, height: 50)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text(title(for: entry.type))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(entry.previewText)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundColor(.primary)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                manager.togglePin(for: entry)
            }) {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .foregroundColor(entry.isPinned ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "Unpin" : "Pin to top")
        }
    }

    private func title(for type: ClipboardManager.ClipboardType) -> String {
        switch type {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .vector:
            return "Vector"
        }
    }

    private func icon(for entry: ClipboardManager.ClipboardHistoryEntry) -> some View {
        switch entry.type {
        case .text:
            if let text = entry.text, let color = ClipboardManager.parseHexColor(from: text) {
                return AnyView(
                    ZStack {
                        Color(color)
                        Text(text)
                            .font(.caption)
                            .foregroundColor(color.isDark ? .white : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(6)
                    }
                )
            }
            return AnyView(
                ZStack {
                    Color(NSColor.textBackgroundColor)
                    Text(entry.previewText)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(6)
                }
            )
        case .image, .vector:
            if let nsImage = entry.image {
                return AnyView(
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                )
            } else {
                return AnyView(Color.gray)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: { copyLatest() }) {
                Text("Copy Latest")
            }
            .buttonStyle(.bordered)
            .disabled(manager.entries.isEmpty)

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit")
            }
            .buttonStyle(.bordered)
        }
    }

    private func copyLatest() {
        guard let entry = manager.entries.first else { return }
        manager.copyToPasteboard(entry)
    }
}
