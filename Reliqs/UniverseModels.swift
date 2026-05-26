//
//  UniverseModels.swift
//  Memori
//
//  Data models for the Universe canvas:
//  - MemoryGlobe  (Daily auto-globe + user custom globes)
//  - StarNode     (a single day on the canvas)
//  - WeekCluster  (7 stars grouped)
//  - MonthGalaxy  (4-5 clusters grouped)
//  - Mood colour mapping

import SwiftUI
import Foundation

// MARK: - Mood colours
// Maps the mood tag strings from JournalScreen to a star colour.
// Stars with no mood → warm white.
enum MoodColour {
    static func color(for mood: String?) -> Color {
        switch mood {
        case "calm":       return Color(hex: "#A8C4D4")   // cool blue-grey
        case "happy":      return Color(hex: "#F5C97A")   // warm amber
        case "focused":    return Color(hex: "#A0D4B4")   // mint green
        case "tired":      return Color(hex: "#8C8FA8")   // muted violet
        case "grateful":   return Color(hex: "#D4A882")   // terracotta warm
        case "anxious":    return Color(hex: "#C4A0A0")   // dusty rose
        case "excited":    return Color(hex: "#F5A060")   // orange glow
        case "reflective": return Color(hex: "#B0A8C8")   // soft lavender
        default:           return Color(hex: "#E8C99A")   // no mood: warm star white
        }
    }

    // Blend multiple moods — used when a day has more than one tag.
    // Strategy: most recently added mood wins (caller passes last element of array).
    static func dominant(from moods: [String]) -> String? {
        moods.last
    }
}

// MARK: - StarNode  (one day)
struct StarNode: Identifiable, Equatable {
    static func == (lhs: StarNode, rhs: StarNode) -> Bool { lhs.id == rhs.id && lhs.snippets.count == rhs.snippets.count }
    let id: String          // dayKey "yyyy-MM-dd"
    let date: Date
    var snippets: [MediaSnippet]    // captures for this day (may be empty)
    var journalText: String         // first line of journal entry
    var moods: [String]             // mood tags from journal
    var position: CGPoint           // position on infinite canvas (logical coords)

    // Visual properties derived from data
    var starColor: Color {
        MoodColour.color(for: MoodColour.dominant(from: moods))
    }
    // Brightness scales with capture count (1 snippet → dim, 5+ → bright)
    var brightness: Double {
        let base = 0.55
        let bonus = min(Double(snippets.count) * 0.09, 0.45)
        return base + bonus
    }
    // Stars with no captures are tiny dim dots
    var hasCaptures: Bool { !snippets.isEmpty }

    // Grid layout for the tap card
    // Always 2×2 minimum; grows to 2×3 for 5-6 items.
    var gridColumns: Int { 2 }
    var gridRows: Int {
        let count = max(snippets.count, 1)
        return count <= 4 ? 2 : 3
    }
    var gridCellCount: Int { gridColumns * gridRows }
}

// MARK: - WeekCluster  (one calendar week)
struct WeekCluster: Identifiable, Equatable {
    static func == (lhs: WeekCluster, rhs: WeekCluster) -> Bool { lhs.id == rhs.id && lhs.stars == rhs.stars }
    let id: String          // "yyyy-Www"
    var stars: [StarNode]
    var centroid: CGPoint   // average position of contained stars
    var dominantMood: String? {
        let all = stars.flatMap { $0.moods }
        return MoodColour.dominant(from: all)
    }
}

// MARK: - MonthGalaxy  (one calendar month)
struct MonthGalaxy: Identifiable, Equatable {
    static func == (lhs: MonthGalaxy, rhs: MonthGalaxy) -> Bool { lhs.id == rhs.id && lhs.clusters == rhs.clusters }
    let id: String          // "yyyy-MM"
    var clusters: [WeekCluster]
    var centroid: CGPoint
    var dominantMood: String? {
        let all = clusters.compactMap { $0.dominantMood }
        return MoodColour.dominant(from: all)
    }
    var totalCaptures: Int {
        clusters.flatMap { $0.stars }.map { $0.snippets.count }.reduce(0, +)
    }
}

// MARK: - MemoryGlobe
struct MemoryGlobe: Identifiable, Codable, Equatable {
    static func == (lhs: MemoryGlobe, rhs: MemoryGlobe) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.snippetIDs == rhs.snippetIDs
    }
    let id: UUID
    var name: String
    var isDaily: Bool           // true = the built-in Daily globe
    var position: CGPoint       // position on canvas
    var snippetIDs: [UUID]      // IDs of snippets assigned to this globe

    // Daily globe is a filter, not a store — snippetIDs unused for Daily.
    static func makeDaily() -> MemoryGlobe {
        MemoryGlobe(id: UUID(), name: "Daily", isDaily: true,
                    position: CGPoint(x: 0, y: -160), snippetIDs: [])
    }

    // Codable support for CGPoint
    enum CodingKeys: String, CodingKey {
        case id, name, isDaily, posX, posY, snippetIDs
    }
    init(id: UUID, name: String, isDaily: Bool, position: CGPoint, snippetIDs: [UUID]) {
        self.id = id; self.name = name; self.isDaily = isDaily
        self.position = position; self.snippetIDs = snippetIDs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,    forKey: .id)
        name       = try c.decode(String.self,  forKey: .name)
        isDaily    = try c.decode(Bool.self,    forKey: .isDaily)
        snippetIDs = try c.decode([UUID].self,  forKey: .snippetIDs)
        let x      = try c.decode(Double.self,  forKey: .posX)
        let y      = try c.decode(Double.self,  forKey: .posY)
        position   = CGPoint(x: x, y: y)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(name,       forKey: .name)
        try c.encode(isDaily,    forKey: .isDaily)
        try c.encode(snippetIDs, forKey: .snippetIDs)
        try c.encode(position.x, forKey: .posX)
        try c.encode(position.y, forKey: .posY)
    }
}

// MARK: - Zoom levels
enum ZoomLevel {
    case galaxy     // far out — month blobs
    case cluster    // mid — week star groups
    case star       // close — individual day stars
}

// MARK: - UniverseStore
// Builds the star/cluster/galaxy hierarchy from MediaStore + JournalStore.
// Also manages globes.

final class UniverseStore: ObservableObject {

    @Published var galaxies: [MonthGalaxy] = []
    @Published var globes: [MemoryGlobe] = []
    @Published var selectedStar: StarNode? = nil
    @Published var showingAutoplay: Bool = false
    @Published var autoplaySnippets: [MediaSnippet] = []
    @Published var autoplayStartIndex: Int = 0

    // Persisted canvas offsets keyed by globe ID string
    @Published var canvasOffsets: [String: CGPoint] = [:]

    private let globesURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("universeGlobes.json")
    }()

    private let offsetsURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("universeOffsets.json")
    }()

    // Random but stable seed per dayKey so positions don't jump on rebuild
    private var positionCache: [String: CGPoint] = [:]

    init() {
        loadGlobes()
        loadOffsets()
    }

    // MARK: - Build hierarchy from stores
    func rebuild(snippets: [UUID: MediaSnippet], journal: [String: JournalEntry]) {
        // 1. Collect all day keys from both stores
        let allDayKeys = Set(snippets.values.map { $0.date.dayKey })
            .union(journal.keys)

        // 2. Build StarNodes
        let stars: [StarNode] = allDayKeys.compactMap { key -> StarNode? in
            guard let date = date(from: key) else { return nil }
            let daySnippets = snippets.values
                .filter { $0.date.dayKey == key }
                .sorted { $0.date < $1.date }
            let journalEntry = journal[key]
            let firstLine = journalEntry?.notes.first?.text
                .components(separatedBy: .newlines).first ?? ""
            // moods would come from JournalEntry if we persist them —
            // for now we read from a parallel MoodStore key (see JournalScreen)
            let moods = MoodStore.shared.moods(for: key)
            return StarNode(
                id: key,
                date: date,
                snippets: Array(daySnippets),
                journalText: firstLine,
                moods: moods,
                position: stablePosition(for: key)
            )
        }
        .sorted { $0.date < $1.date }

        // 3. Group into weeks
        let weekGroups = Dictionary(grouping: stars) { star -> String in
            let cal = Calendar.current
            let week = cal.component(.weekOfYear, from: star.date)
            let year = cal.component(.yearForWeekOfYear, from: star.date)
            return "\(year)-W\(String(format: "%02d", week))"
        }
        let clusters: [WeekCluster] = weekGroups.map { key, stars in
            WeekCluster(id: key, stars: stars, centroid: centroid(of: stars.map { $0.position }))
        }.sorted { $0.id < $1.id }

        // 4. Group weeks into months (regroup by the month of each cluster's first star)
        let clustersByMonth = Dictionary(grouping: clusters) { cluster -> String in
            cluster.stars.first.map { String($0.id.prefix(7)) } ?? cluster.id
        }

        let newGalaxies: [MonthGalaxy] = clustersByMonth.map { monthKey, cls in
            let gCentroid = centroid(of: cls.map { $0.centroid })
            return MonthGalaxy(id: monthKey, clusters: cls, centroid: gCentroid)
        }.sorted { $0.id < $1.id }

        DispatchQueue.main.async {
            self.galaxies = newGalaxies
        }
    }

    // MARK: - Globe management

    func addGlobe(name: String) -> MemoryGlobe {
        let g = MemoryGlobe(id: UUID(), name: name, isDaily: false,
                            position: .zero, snippetIDs: [])
        globes.append(g)
        saveGlobes()
        return g
    }

    func addGlobe(name: String, at position: CGPoint) {
        let g = MemoryGlobe(id: UUID(), name: name, isDaily: false,
                            position: position, snippetIDs: [])
        globes.append(g)
        saveGlobes()
    }

    func deleteGlobe(id: UUID, deleteMemories: Bool, mediaStore: MediaStore) {
        guard let idx = globes.firstIndex(where: { $0.id == id }) else { return }
        if deleteMemories {
            globes[idx].snippetIDs.forEach { mediaStore.deleteSnippet(id: $0) }
        }
        globes.remove(at: idx)
        saveGlobes()
    }

    func assignSnippet(_ snippetID: UUID, to globeID: UUID) {
        guard let idx = globes.firstIndex(where: { $0.id == globeID }) else { return }
        if !globes[idx].snippetIDs.contains(snippetID) {
            globes[idx].snippetIDs.append(snippetID)
            saveGlobes()
        }
    }

    func removeSnippet(_ snippetID: UUID, from globeID: UUID) {
        guard let idx = globes.firstIndex(where: { $0.id == globeID }) else { return }
        globes[idx].snippetIDs.removeAll { $0 == snippetID }
        saveGlobes()
    }

    // Daily globe: snippets from the last 7 days
    func dailySnippets(from snippets: [UUID: MediaSnippet]) -> [MediaSnippet] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return snippets.values.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    // MARK: - Autoplay
    func openAutoplay(snippets: [MediaSnippet], startAt index: Int = 0) {
        autoplaySnippets = snippets
        autoplayStartIndex = index
        showingAutoplay = true
    }

    // MARK: - Helpers
    private func stablePosition(for dayKey: String) -> CGPoint {
        if let cached = positionCache[dayKey] { return cached }
        // Use a simple deterministic hash spread within ±400pt of centre
        // Swift's Hasher is randomised per-run, so use a manual LCG instead
        let bytes = Array(dayKey.utf8)
        var h: UInt64 = 14695981039346656037
        for b in bytes { h = (h ^ UInt64(b)) &* 1099511628211 }
        let x = CGFloat(h & 0xFFFF) / 65535.0 * 800 - 400
        let y = CGFloat((h >> 16) & 0xFFFF) / 65535.0 * 800 - 400
        let pt = CGPoint(x: x, y: y)
        positionCache[dayKey] = pt
        return pt
    }

    private func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint.zero }
        let sum = points.reduce(CGPoint.zero) { acc, pt in CGPoint(x: acc.x + pt.x, y: acc.y + pt.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func date(from dayKey: String) -> Date? {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dayKey)
    }

    func saveOffset(_ offset: CGSize, for globeID: String) {
        canvasOffsets[globeID] = CGPoint(x: offset.width, y: offset.height)
        saveOffsets()
    }

    func offset(for globeID: String) -> CGSize {
        guard let pt = canvasOffsets[globeID] else { return .zero }
        return CGSize(width: pt.x, height: pt.y)
    }

    private func saveGlobes() {
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(self.globes) {
                try? data.write(to: self.globesURL, options: .atomic)
            }
        }
    }

    private func saveOffsets() {
        // Encode as [String: [String: Double]] for Codable simplicity
        let raw = canvasOffsets.mapValues { ["x": Double($0.x), "y": Double($0.y)] }
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(raw) {
                try? data.write(to: self.offsetsURL, options: .atomic)
            }
        }
    }

    private func loadOffsets() {
        guard let data = try? Data(contentsOf: offsetsURL),
              let raw = try? JSONDecoder().decode([String: [String: Double]].self, from: data)
        else { return }
        canvasOffsets = raw.compactMapValues { d in
            guard let x = d["x"], let y = d["y"] else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    private func loadGlobes() {
        if let data = try? Data(contentsOf: globesURL),
           let decoded = try? JSONDecoder().decode([MemoryGlobe].self, from: data) {
            globes = decoded
        }
        // Always ensure Daily exists
        if !globes.contains(where: { $0.isDaily }) {
            globes.insert(MemoryGlobe.makeDaily(), at: 0)
        }
    }
}

// MARK: - MoodStore
// Lightweight singleton that persists mood tags per dayKey.
// JournalScreen writes here; UniverseStore reads here.
final class MoodStore: ObservableObject {
    static let shared = MoodStore()
    @Published private(set) var moodsByDay: [String: [String]] = [:]

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("moodStore.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            moodsByDay = decoded
        }
    }

    func moods(for dayKey: String) -> [String] {
        moodsByDay[dayKey] ?? []
    }

    func setMoods(_ moods: [String], for dayKey: String) {
        moodsByDay[dayKey] = moods
        save()
        objectWillChange.send()
    }

    private func save() {
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(self.moodsByDay) {
                try? data.write(to: self.url, options: .atomic)
            }
        }
    }
}
