

//
//  DayNote.swift
//  Memori
//
//  Created by Abhinav Garapati on 07/12/25.
//


//

//  Memori
//
//  Created by Abhinav Garapati on 03/09/25.
//  DayNote.swift
import Foundation
import Combine
import SwiftUI

// MARK: - Models

struct DayNote: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

final class JournalEntry: Identifiable, ObservableObject, Codable, Equatable {
    var id: String { dayKey }
    let dayKey: String
    @Published var notes: [DayNote]

    init(dayKey: String, notes: [DayNote]) {
        self.dayKey = dayKey
        self.notes = notes
    }

    // Codable
    enum CodingKeys: String, CodingKey { case dayKey, notes }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        notes  = try c.decode([DayNote].self, forKey: .notes)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(notes,  forKey: .notes)
    }

    static func == (lhs: JournalEntry, rhs: JournalEntry) -> Bool {
        lhs.dayKey == rhs.dayKey && lhs.notes == rhs.notes
    }
}

// MARK: - Store

final class JournalStore: ObservableObject {
    @Published private(set) var entries: [String: JournalEntry] = [:]
    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0

    /// Days that have at least one non-empty note — used for the calendar counter.
    var writtenEntryCount: Int {
        entries.values.filter { entry in
            entry.notes.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.count
    }

    private var saver: AnyCancellable?
    private var entryCancellables: [String: AnyCancellable] = [:]

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let d = dir.appendingPathComponent("Journal")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("entries.json")
    }()

    init() {
        // Load
        if let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([String: JournalEntry].self, from: data) {
            entries = map
        }

        // Save when the dictionary itself changes (add/remove days, etc.)
        saver = $entries
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveNow() }

        // Also save when any entry’s notes change
        attachObserversForAllEntries()
    }

    // MARK: - Access

    func entry(for date: Date) -> JournalEntry {
        let k = date.dayKey
        if let e = entries[k] { return e }
        let e = JournalEntry(dayKey: k, notes: [DayNote()])
        entries[k] = e
        observeEntry(e) // start listening to notes changes
        return e
    }

    // MARK: - Mutations

    func addNote(for date: Date, text: String = "") {
        let e = entry(for: date)
        // Reassign the array to guarantee @Published on `notes` fires
        var newNotes = e.notes
        newNotes.append(DayNote(text: text))
        e.notes = newNotes

        updateStreaks()
    }

    func updateNote(for date: Date, id: UUID, text: String) {
        let e = entry(for: date)
        guard let idx = e.notes.firstIndex(where: { $0.id == id }) else { return }

        // Reassign the array so @Published `notes` definitely emits
        var newNotes = e.notes
        newNotes[idx].text = text
        e.notes = newNotes

        // Auto-add a new blank note if editing the last one and it’s non-empty
        if idx == e.notes.count - 1,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newNotes.append(DayNote())
            e.notes = newNotes
        }
    }

    // MARK: - Observing & Saving

    private func attachObserversForAllEntries() {
        entryCancellables.removeAll()
        for entry in entries.values { observeEntry(entry) }
    }

    private func observeEntry(_ entry: JournalEntry) {
        // Save and forward changes whenever this day's notes change
        entryCancellables[entry.dayKey] = entry.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send() // update SwiftUI views
                self.saveNow()               // persist edits
            }
    }
    
    // synchronous flush (call from main thread during lifecycle)
    func flushSaveSync() {
        let meaningful = entries.filter { _, entry in
            entry.notes.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let data = try? JSONEncoder().encode(meaningful) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func saveNow() {
        // Drop ghost entries (days opened but never written to) before persisting
        let meaningful = entries.filter { _, entry in
            entry.notes.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard let data = try? JSONEncoder().encode(meaningful) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Streaks

    private func updateStreaks() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let days = entries.values.map { $0.dayKey }.compactMap { dayKey in
            fmt.date(from: dayKey)
        }.sorted()

        var streak = 0, longest = 0, prev: Date? = nil
        for day in days {
            if let p = prev, Calendar.current.date(byAdding: .day, value: 1, to: p) == day {
                streak += 1
            } else {
                streak = 1
            }
            longest = max(longest, streak)
            prev = day
        }
        currentStreak = streak
        longestStreak = longest
    }
}

// MARK: - Date Helpers

extension Date {
    var dayKey: String {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
    func addingDays(_ d: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: d, to: self) ?? self
    }
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func timeString() -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: self)
    }
}

// MARK: - Binding helper (optional; unchanged)

extension JournalStore {
    func notesBinding(for date: Date) -> Binding<[DayNote]> {
        let key = date.dayKey
        if entries[key] == nil {
            entries[key] = JournalEntry(dayKey: key, notes: [DayNote()])
            observeEntry(entries[key]!) // observe newly created entry
        }
        return Binding(
            get: { self.entries[key]?.notes ?? [] },
            set: { self.entries[key]?.notes = $0 }
        )
    }
}
// In JournalStore.swift (keep your existing code; just add this at the bottom)

extension JournalStore {
    /// Binding to the "journal body" for a given day, backed by notes[0].
    func journalBodyBinding(for date: Date) -> Binding<String> {
        let key = date.dayKey
        if entries[key] == nil {
            entries[key] = JournalEntry(dayKey: key, notes: [DayNote()]) // ensure at least one note
            // if you have observeEntry(_:) in your store, call it here too
            // observeEntry(entries[key]!)
        }
        if entries[key]!.notes.isEmpty {
            entries[key]!.notes = [DayNote()]
        }
        return Binding<String>(
            get: { self.entries[key]!.notes[0].text },
            set: { newText in
                // Reassign array to trigger @Published on `notes`
                var notes = self.entries[key]!.notes
                notes[0].text = newText
                self.entries[key]!.notes = notes
            }
        )
    }
}
