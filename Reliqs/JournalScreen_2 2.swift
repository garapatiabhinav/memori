// JournalScreen.swift
// Memori

import SwiftUI
import AVKit

struct JournalScreen: View {
    @Binding var date: Date
    @ObservedObject var store: JournalStore
    @ObservedObject var mediaStore: MediaStore
    @StateObject private var keyboard = KeyboardObserver()
    var onOpenCalendar: () -> Void
    var onOpenSnippet: (NoteCard) -> Void

    @FocusState private var isEditorFocused: Bool
    @State private var selectedMoods: Set<String> = []
    @State private var dragOffset: CGFloat = 0
    @State private var paperColor: Color = Color(hex: "#F5EFE4")

    private let paperColors: [(Color, String)] = [
        (Color(hex: "#F5EFE4"), "cream"),
        (Color(hex: "#E8F0E8"), "sage"),
        (Color(hex: "#F0E8F0"), "lavender"),
        (Color(hex: "#F5EBE0"), "peach"),
    ]

    private let paperColorKey = "journal_paperColor"

    private var todayPrompt: String {
        let idx = abs(Calendar.current.component(.day, from: date) - 1)
        return Memori.journalPrompts[idx % Memori.journalPrompts.count]
    }

    private var todaysSnippets: [MediaSnippet] {
        mediaStore.snippets.values
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Memori.Color.pageBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    header(geo: geo)
                    if !todaysSnippets.isEmpty { snippetStrip }
                    moodStrip
                    journalPaper
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .padding(.bottom, keyboard.height)
                .animation(.easeOut(duration: keyboard.animationDuration), value: keyboard.height)
                .ignoresSafeArea(.keyboard)
                .offset(x: dragOffset)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isEditorFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
            .simultaneousGesture(          // also fires when children handle the tap
                TapGesture().onEnded {
                    isEditorFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            )
            .gesture(
                DragGesture()
                    .onChanged { v in
                        let dx = v.translation.width
                        // Only allow going forward if not today
                        if dx < 0 && isToday { return }
                        dragOffset = dx * 0.35 // rubber-band feel
                    }
                    .onEnded { v in
                        let dx = v.translation.width
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                        if dx < -50 && !isToday {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            date = date.addingDays(1)
                        } else if dx > 50 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            date = date.addingDays(-1)
                        }
                    }
            )
        }
        .onAppear {
            selectedMoods = Set(MoodStore.shared.moods(for: date.dayKey))
            if let hex = UserDefaults.standard.string(forKey: paperColorKey) {
                paperColor = Color(hex: hex)
            }
        }
        .onChange(of: date) { _, d in selectedMoods = Set(MoodStore.shared.moods(for: d.dayKey)) }
        .onChange(of: selectedMoods) { _, m in MoodStore.shared.setMoods(Array(m), for: date.dayKey) }
        .onChange(of: paperColor) { _, c in
            UserDefaults.standard.set(c.toHex(), forKey: paperColorKey)
        }
    }

    // MARK: - Header
    private func header(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {

                // Prev day
                Button { date = date.addingDays(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Memori.Color.inkMid)
                        .frame(width: 34, height: 34)
                        .background(Memori.Color.surfaceMid, in: Circle())
                }

                Spacer()

                // Centre — date + streak
                VStack(spacing: 3) {
                    Text(date, format: .dateTime.weekday(.wide).day().month())
                        .font(Memori.Font.serif(15))
                        .foregroundStyle(Memori.Color.inkLight)

                    if store.currentStreak > 1 {
                        streakPill
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onOpenCalendar) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Memori.Color.inkMid)
                            .frame(width: 34, height: 34)
                            .background(Memori.Color.surfaceMid, in: Circle())
                    }

                    Button { date = date.addingDays(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isToday
                                             ? Memori.Color.surfaceMid.opacity(0.4)
                                             : Memori.Color.inkMid)
                            .frame(width: 34, height: 34)
                            .background(Memori.Color.surfaceMid.opacity(isToday ? 0.4 : 1),
                                        in: Circle())
                    }
                    .disabled(isToday)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, topSafeInset(geo) + 14)
            .padding(.bottom, 14)

            // Thin separator
            Rectangle()
                .fill(Memori.Color.inkFaint.opacity(0.12))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
        }
    }

    private func topSafeInset(_ geo: GeometryProxy) -> CGFloat {
        // geo.safeAreaInsets is the most reliable source here since the GeometryReader
        // itself does not ignore safe areas. Fall back to the window inset if it reads
        // zero (can happen on some simulator configurations).
        let geoInset = geo.safeAreaInsets.top
        if geoInset > 1 { return geoInset }
        let windowInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
        return max(windowInset, 44)
    }

    private var streakPill: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.system(size: 10))
            Text("\(store.currentStreak) day streak")
                .font(Memori.Font.sans(10, weight: .medium))
                .foregroundStyle(Memori.Color.accentLight)
                .tracking(0.3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Memori.Color.accentMuted.opacity(0.5))
                .overlay(Capsule().strokeBorder(Memori.Color.accent.opacity(0.3), lineWidth: 0.5))
        )
    }

    // MARK: - Snippet Strip
    private var snippetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(todaysSnippets, id: \.id) { snippet in
                    Button { onOpenSnippet(snippet.toNoteCard()) } label: {
                        snippetThumb(snippet)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(height: 76)
    }

    @ViewBuilder
    private func snippetThumb(_ snippet: MediaSnippet) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let data = snippet.imageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if snippet.videoPath != nil {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Memori.Color.surfaceMid)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Memori.Color.inkMid))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Memori.Color.surfaceMid)
                    .frame(width: 56, height: 56)
            }

            if !snippet.text.isEmpty {
                Text(snippet.text)
                    .font(Memori.Font.sans(7))
                    .foregroundStyle(Memori.Color.inkLight)
                    .lineLimit(2)
                    .padding(3)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
                    .padding(3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Memori.Color.inkFaint.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Mood Strip
    private var moodStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Memori.moodEntries, id: \.tag) { entry in
                    let isSelected = selectedMoods.contains(entry.tag)
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        if isSelected { selectedMoods.remove(entry.tag) }
                        else { selectedMoods.insert(entry.tag) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(entry.emoji)
                                .font(.system(size: 12))
                            Text(entry.tag)
                                .font(Memori.Font.sans(11))
                                .foregroundStyle(isSelected
                                                 ? MoodColour.color(for: entry.tag)
                                                 : Memori.Color.inkMid)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isSelected
                                      ? MoodColour.color(for: entry.tag).opacity(0.12)
                                      : Memori.Color.surfaceMid)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(
                                            isSelected
                                            ? MoodColour.color(for: entry.tag).opacity(0.5)
                                            : Memori.Color.inkFaint.opacity(0.15),
                                            lineWidth: 0.5
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Journal Paper
    private var journalPaper: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(paperColor)

            // Ruling lines
            GeometryReader { g in
                let spacing: CGFloat = 26
                let start:   CGFloat = 48
                ForEach(0..<Int((g.size.height - start) / spacing), id: \.self) { i in
                    Rectangle()
                        .fill(Color(hex: "#C4B99A").opacity(0.25))
                        .frame(height: 0.5)
                        .padding(.horizontal, 18)
                        .offset(y: start + CGFloat(i) * spacing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                // Color picker row
                HStack(spacing: 10) {
                    ForEach(paperColors, id: \.1) { color, name in
                        let isActive = color.toHex() == paperColor.toHex()
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isActive ? Memori.Color.inkMid : Memori.Color.inkFaint.opacity(0.4),
                                        lineWidth: isActive ? 1.5 : 0.5
                                    )
                            )
                            .scaleEffect(isActive ? 1.18 : 1.0)
                            .animation(.spring(response: 0.25), value: isActive)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) { paperColor = color }
                            }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Prompt placeholder
                let body = store.journalBodyBinding(for: date).wrappedValue
                if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(todayPrompt)
                        .font(Memori.Font.serif(14))
                        .foregroundStyle(Memori.Color.inkFaint)
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }

                TextEditor(text: store.journalBodyBinding(for: date))
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .font(Memori.Font.serif(15))
                    .foregroundStyle(Memori.Color.inkDark)
                    .lineSpacing(11)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .background(.clear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .layoutPriority(1)
    }
}

// MARK: - Mood entry model (emoji + tag)
extension Memori {
    struct MoodEntry { let tag: String; let emoji: String }
    static let moodEntries: [MoodEntry] = [
        .init(tag: "calm",       emoji: "🌿"),
        .init(tag: "happy",      emoji: "☀️"),
        .init(tag: "focused",    emoji: "🎯"),
        .init(tag: "tired",      emoji: "🌙"),
        .init(tag: "grateful",   emoji: "🙏"),
        .init(tag: "anxious",    emoji: "🌀"),
        .init(tag: "excited",    emoji: "✨"),
        .init(tag: "reflective", emoji: "💭"),
    ]
}
