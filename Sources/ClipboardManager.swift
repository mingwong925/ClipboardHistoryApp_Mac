import AppKit
import SwiftUI

final class ClipboardManager: ObservableObject {
    enum ClipboardType {
        case text
        case image
        case vector
    }

    struct StoredPasteboardItem: Equatable {
        let dataByType: [(type: NSPasteboard.PasteboardType, data: Data)]

        static func ==(lhs: StoredPasteboardItem, rhs: StoredPasteboardItem) -> Bool {
            guard lhs.dataByType.count == rhs.dataByType.count else { return false }
            return zip(lhs.dataByType, rhs.dataByType).allSatisfy { left, right in
                left.type == right.type && left.data == right.data
            }
        }
    }

    struct ClipboardHistoryEntry: Identifiable, Equatable {
        let id = UUID()
        let type: ClipboardType
        let text: String?
        let image: NSImage?
        let imagePNGData: Data?
        let pasteboardItems: [StoredPasteboardItem]
        let timestamp: Date
        var isPinned: Bool = false

        var previewText: String {
            switch type {
            case .text:
                return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            case .image:
                return "Image copied"
            case .vector:
                return "Illustrator vector copied"
            }
        }

        static func ==(lhs: ClipboardHistoryEntry, rhs: ClipboardHistoryEntry) -> Bool {
            guard lhs.type == rhs.type else { return false }
            switch (lhs.type, lhs.text, rhs.text, lhs.image, rhs.image, lhs.imagePNGData, rhs.imagePNGData, lhs.pasteboardItems, rhs.pasteboardItems) {
            case (.text, let left, let right, _, _, _, _, _, _):
                return left == right
            case (.image, _, _, let leftImage, let rightImage, let leftPNG, let rightPNG, _, _):
                if let leftPNG, let rightPNG {
                    return leftPNG == rightPNG
                }
                guard let leftData = leftImage?.tiffRepresentation,
                      let rightData = rightImage?.tiffRepresentation else {
                    return false
                }
                return leftData == rightData
            case (.vector, _, _, _, _, _, _, let leftItems, let rightItems):
                return leftItems == rightItems
            }
        }
    }

    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var currentColor: NSColor? = nil

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let maxEntries = 20
    private let maxVectorPayloadBytes = 16 * 1024 * 1024
    private let maxVectorDataPerTypeBytes = 8 * 1024 * 1024
    private let illustratorVectorTypeNames = [
        "com.adobe.illustrator.aicb",
        "com.adobe.illustrator.ai",
        "Adobe Illustrator Artwork"
    ]

    func startMonitoring() {
        refreshCurrentColorFromClipboard()
        timer = Timer(timeInterval: 0.6, target: self, selector: #selector(timerFired(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshCurrentColorFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            currentColor = ClipboardManager.parseHexColor(from: string)
        } else {
            currentColor = nil
        }
    }

    @objc private func timerFired(_ timer: Timer) {
        checkClipboard()
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        let isIllustratorVector = pasteboardContainsIllustratorVector(pasteboard)

        if isIllustratorVector,
           let pasteboardItems = storedVectorItems(from: pasteboard) {
            let previewPNGData = pasteboard.data(forType: .png)
            let previewImage = previewPNGData.flatMap(NSImage.init(data:))
            currentColor = nil
            let entry = ClipboardHistoryEntry(type: .vector, text: nil, image: previewImage, imagePNGData: previewPNGData, pasteboardItems: pasteboardItems, timestamp: Date())
            addClipboardItem(entry)
            return
        }

        if isIllustratorVector {
            // 大向量只保留影像預覽，避免同步抓取過大向量 payload 造成來源 App 卡住
            if let pngData = pasteboard.data(forType: .png), let image = NSImage(data: pngData) {
                currentColor = nil
                let entry = ClipboardHistoryEntry(type: .image, text: nil, image: image, imagePNGData: pngData, pasteboardItems: [], timestamp: Date())
                addClipboardItem(entry)
                return
            }

            if let image = NSImage(pasteboard: pasteboard) {
                currentColor = nil
                let entry = ClipboardHistoryEntry(type: .image, text: nil, image: image, imagePNGData: nil, pasteboardItems: [], timestamp: Date())
                addClipboardItem(entry)
                return
            }
        }

        // 优先检查图片，因为复制图片时剪贴板可能同时包含文本和图片
        // 優先讀取 PNG 格式以保留透明度（避免 Photoshop 複製圖層產生白邊）
        if let pngData = pasteboard.data(forType: .png), let image = NSImage(data: pngData) {
            currentColor = nil
            let entry = ClipboardHistoryEntry(type: .image, text: nil, image: image, imagePNGData: pngData, pasteboardItems: [], timestamp: Date())
            addClipboardItem(entry)
            return
        }

        // 退而求其次使用通用方式（無透明度的一般圖片）
        if let image = NSImage(pasteboard: pasteboard) {
            currentColor = nil
            let entry = ClipboardHistoryEntry(type: .image, text: nil, image: image, imagePNGData: nil, pasteboardItems: [], timestamp: Date())
            addClipboardItem(entry)
            return
        }
        
        // 然后再检查文本
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            currentColor = ClipboardManager.parseHexColor(from: string)
            let entry = ClipboardHistoryEntry(type: .text, text: string, image: nil, imagePNGData: nil, pasteboardItems: [], timestamp: Date())
            addClipboardItem(entry)
            return
        }

        currentColor = nil
    }

    private func addClipboardItem(_ entry: ClipboardHistoryEntry) {
        if let first = entries.first, first == entry {
            return
        }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            // 优先删除最后的未PIN项目
            if let lastUnpinnedIndex = entries.lastIndex(where: { !$0.isPinned }) {
                entries.remove(at: lastUnpinnedIndex)
            } else {
                entries.removeLast()
            }
        }
        sortEntries()
    }

    static func parseHexColor(from string: String) -> NSColor? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexString: String
        if trimmed.hasPrefix("#") {
            hexString = String(trimmed.dropFirst())
        } else {
            hexString = trimmed
        }

        guard hexString.count == 6 else { return nil }
        let validHex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hexString.rangeOfCharacter(from: validHex.inverted) == nil else { return nil }

        var rgbValue: UInt64 = 0
        let scanner = Scanner(string: hexString)
        guard scanner.scanHexInt64(&rgbValue) else { return nil }

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0
        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    func copyToPasteboard(_ entry: ClipboardHistoryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.type {
        case .text:
            if let text = entry.text {
                pasteboard.setString(text, forType: .string)
                currentColor = ClipboardManager.parseHexColor(from: text)
            } else {
                currentColor = nil
            }
        case .image:
            if let pngData = entry.imagePNGData {
                pasteboard.setData(pngData, forType: .png)
            } else if let image = entry.image, let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            currentColor = nil
        case .vector:
            let pasteboardItems = entry.pasteboardItems.map { storedItem in
                let pasteboardItem = NSPasteboardItem()
                for itemData in storedItem.dataByType {
                    pasteboardItem.setData(itemData.data, forType: itemData.type)
                }
                return pasteboardItem
            }
            if !pasteboardItems.isEmpty {
                pasteboard.writeObjects(pasteboardItems)
            } else if let image = entry.image, let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            currentColor = nil
        }

        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(for entry: ClipboardHistoryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            var updatedEntry = entries[index]
            updatedEntry.isPinned.toggle()
            entries[index] = updatedEntry
            sortEntries()
        }
    }

    func clearHistory() {
        // 只删除未被PIN的项目
        entries.removeAll { !$0.isPinned }
    }

    private func sortEntries() {
        // PIN的项目始终在顶部
        entries.sort { lhs, rhs in
            if lhs.isPinned == rhs.isPinned {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.isPinned && !rhs.isPinned
        }
    }

    private func pasteboardContainsIllustratorVector(_ pasteboard: NSPasteboard) -> Bool {
        let typeNames = pasteboard.types?.map { $0.rawValue } ?? []
        return typeNames.contains { typeName in
            illustratorVectorTypeNames.contains(typeName)
        }
    }

    private func storedVectorItems(from pasteboard: NSPasteboard) -> [StoredPasteboardItem]? {
        guard let pasteboardItems = pasteboard.pasteboardItems else { return nil }

        var totalPayloadBytes = 0
        var result: [StoredPasteboardItem] = []

        for item in pasteboardItems {
            var dataByType: [(type: NSPasteboard.PasteboardType, data: Data)] = []

            for type in item.types {
                guard let data = item.data(forType: type), !data.isEmpty else { continue }

                if data.count > maxVectorDataPerTypeBytes {
                    return nil
                }

                if totalPayloadBytes + data.count > maxVectorPayloadBytes {
                    return nil
                }

                totalPayloadBytes += data.count
                dataByType.append((type, data))
            }

            if !dataByType.isEmpty {
                result.append(StoredPasteboardItem(dataByType: dataByType))
            }
        }

        return result.isEmpty ? nil : result
    }
}
