//
//  MediaSnippet.swift
//  Memori
//
//  Created by Abhinav Garapati on 07/12/25.
//


//
//  Memori
//
//  Created by Abhinav Garapati on 02/09/25.
//

//  Mediastore.swift

import Foundation
import SwiftUI

// MARK: - Codable Snippet
struct MediaSnippet: Identifiable, Codable {
    let id: UUID
    var date: Date
    var text: String
    var imageData: Data?
    var videoPath: String?
    var colorHex: String?

    // Convert back to NoteCard
    func toNoteCard() -> NoteCard {
        NoteCard(
            id: id,
            date: date,
            image: imageData.flatMap { UIImage(data: $0) },
            text: text,
            color: Color.fromHex(colorHex) ?? Color(red: 0.98, green: 0.95, blue: 0.55),
            videoURL: videoPath.flatMap { URL(fileURLWithPath: $0) }
        )
    }
}

final class MediaStore: ObservableObject {
    @Published private(set) var snippets: [UUID: MediaSnippet] = [:]

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("MediaSnippets.json")
    }()

    // Background queue for compression/IO
    private let ioQueue = DispatchQueue(label: "MediaStore.io", qos: .utility)

    init() { load() }
    
    // synchronous flush (call from main thread during lifecycle)
    func flushSaveSync() {
        // quick snapshot then synchronous write
        let snapshot = snippets
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }
    func insertSnippet(_ snippet: MediaSnippet) {
        snippets[snippet.id] = snippet
        save()
    }

    // MARK: - Public API (unchanged signatures)

    /// Save or update snippet – now non-blocking for UI.
    func saveSnippet(from card: NoteCard) {
        let id = card.id
        let date = card.date
        let text = card.text
        let videoPath = card.videoURL?.path
        let colorHex = card.color.toHex()
        let image = card.image

        // Do heavy work off-main
        ioQueue.async {
            // Downsample before JPEG to avoid giant Data
            let data: Data? = image
                .map { MediaStore.downsample($0, maxDimension: 2000) }?
                .jpegData(compressionQuality: 0.8)

            let snippet = MediaSnippet(
                id: id,
                date: date,
                text: text,
                imageData: data,
                videoPath: videoPath,
                colorHex: colorHex
            )

            // Publish on main, then persist on background
            DispatchQueue.main.async {
                self.snippets[id] = snippet
                self.save() // this save() is also non-blocking now
            }
        }
    }

    func updateSnippet(from card: NoteCard) {
        // Same as save; keep API identical
        saveSnippet(from: card)
    }

    // MARK: - Persistence

    private func save() {
        // Snapshot on main, encode+write off-main
        let snapshot = snippets
        ioQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: self.saveURL, options: .atomic)
            }
        }
    }

    private func load() {
        // Load off-main, publish on main
        ioQueue.async {
            guard
                let data = try? Data(contentsOf: self.saveURL),
                let decoded = try? JSONDecoder().decode([UUID: MediaSnippet].self, from: data)
            else { return }
            DispatchQueue.main.async {
                self.snippets = decoded
            }
        }
    }
    
    func deleteSnippet(id: UUID) {
        snippets.removeValue(forKey: id)
        save()
    }

    // MARK: - Helpers

    private static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxSide / maxDimension
        let size = CGSize(width: image.size.width / scale, height: image.size.height / scale)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }
}

// MARK: - Color helpers
extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    static func fromHex(_ hex: String?) -> Color? {
        guard let hex = hex else { return nil }
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
