// CalendarScreen.swift
// Memori

import SwiftUI

struct CalendarScreen: View {
    @State var monthAnchor: Date
    @Binding var selectedDate: Date
    @ObservedObject var store: JournalStore
    @ObservedObject var mediaStore: MediaStore
    var onClose: () -> Void
    @State private var revealedBadgeKeys: Set<String> = []

    private var streakDays: Set<String> { store.streakDayKeys }

    // Pre-build a flat list of days so the streak bridge can look ahead/behind.
    private var monthDays: [Date?] { daysInMonth(monthAnchor) }

    var body: some View {
        ZStack {
            Memori.Color.paperBg.ignoresSafeArea()

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    // Handle
                    Capsule()
                        .fill(Memori.Color.inkFaint.opacity(0.35))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)

                    // Month nav
                    monthHeader
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    // Stats bar
                    streakSummaryBar
                        .padding(.bottom, 14)

                    // Weekday labels — use enumerated indices as IDs to avoid duplicate-key crash
                    weekdayLabels
                        .padding(.bottom, 8)

                    // Day grid
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
                    LazyVGrid(columns: cols, spacing: 4) {
                        ForEach(Array(monthDays.enumerated()), id: \.offset) { idx, day in
                            let thumb = thumbnail(on: day)
                            let key = day?.dayKey ?? ""
                            DayCell(
                                day:          day,
                                isSelected:   sameDay(day, selectedDate),
                                isToday:      sameDay(day, Date()),
                                hasJournal:   hasJournal(on: day),
                                thumbnail:    thumb,
                                isBadgeRevealed: thumb == nil || revealedBadgeKeys.contains(key),
                                streakState:  streakState(for: idx),
                                dominantMood: mood(on: day)
                            ) {
                                if let d = day {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedDate = d
                                    onClose()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)

                    Spacer(minLength: 12)

                    Button(action: onClose) {
                        Text("done")
                            .font(Memori.Font.sans(14))
                            .foregroundStyle(Memori.Color.accent)
                            .tracking(1)
                    }
                    .padding(.bottom, 28)
                }
                .padding(.top, max(44, proxy.safeAreaInsets.top + 22))
            }
        }
        .presentationDetents([.fraction(0.78)])
        .presentationCornerRadius(24)
        .onAppear { revealPhotoBadgesSequentially() }
        .onChange(of: monthAnchor) { _, _ in revealPhotoBadgesSequentially() }
        .onChange(of: mediaStore.snippets.count) { _, _ in revealPhotoBadgesSequentially() }
    }

    // MARK: - Sub-views

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    monthAnchor = Calendar.current.date(byAdding: .month, value: -1, to: monthAnchor)!
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Memori.Color.inkMid)
                    .frame(width: 34, height: 34)
                    .background(Memori.Color.paperAlt, in: Circle())
            }

            Spacer()

            Text(monthAnchor.formatted(.dateTime.year().month(.wide)))
                .font(Memori.Font.serif(17))
                .foregroundStyle(Memori.Color.inkDark)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) {
                    monthAnchor = Calendar.current.date(byAdding: .month, value: 1, to: monthAnchor)!
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Memori.Color.inkMid)
                    .frame(width: 34, height: 34)
                    .background(Memori.Color.paperAlt, in: Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    private var streakSummaryBar: some View {
        HStack(spacing: 0) {
            statBadge(icon: "🔥", value: "\(store.currentStreak)", label: "streak")
            divider
            statBadge(icon: "📝", value: "\(store.writtenEntryCount)", label: "entries")
            divider
            statBadge(icon: "📸", value: "\(mediaStore.snippets.count)", label: "captures")
            divider
            statBadge(icon: "⭐️", value: "\(store.longestStreak)", label: "best")
        }
        .padding(.vertical, 10)
        .background(Memori.Color.paperAlt, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(Memori.Color.inkFaint.opacity(0.25))
            .frame(width: 0.5, height: 28)
    }

    private func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(icon).font(.system(size: 11))
                Text(value)
                    .font(Memori.Font.sans(15, weight: .medium))
                    .foregroundStyle(Memori.Color.inkDark)
            }
            Text(label)
                .font(Memori.Font.sans(9))
                .foregroundStyle(Memori.Color.inkMid)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayLabels: some View {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(Memori.Font.sans(11))
                    .foregroundStyle(Memori.Color.inkMid)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Streak bridge logic

    /// Describes how this cell participates in the current streak chain.
    enum StreakState {
        case none
        case single                 // streak day but alone (no neighbours)
        case start                  // first day of a run (bridge extends right)
        case middle                 // in the middle of a run
        case end                    // last day of a run (bridge extends left) + flame
    }

    private func streakState(for idx: Int) -> StreakState {
        guard let day = monthDays[idx], isStreakDay(day) else { return .none }

        // Look at the adjacent cells in the flat array.
        // A cell at column 0 has no left neighbour in the same row.
        let col   = idx % 7
        let prevDay = (idx > 0 && col > 0) ? monthDays[idx - 1] : nil
        let nextDay = (idx < monthDays.count - 1 && col < 6) ? monthDays[idx + 1] : nil

        let prevStreak = prevDay != nil && isStreakDay(prevDay!)
        let nextStreak = nextDay != nil && isStreakDay(nextDay!)

        switch (prevStreak, nextStreak) {
        case (false, false): return .single
        case (false, true):  return .start
        case (true,  true):  return .middle
        case (true,  false): return .end
        }
    }

    // MARK: - Data helpers

    private func sameDay(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }

    private func isStreakDay(_ day: Date) -> Bool {
        streakDays.contains(day.dayKey)
    }

    private func hasJournal(on day: Date?) -> Bool {
        guard let d = day else { return false }
        guard let notes = store.entries[d.dayKey]?.notes else { return false }
        return notes.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Returns the first photo thumbnail for the day, if any.
    private func thumbnail(on day: Date?) -> UIImage? {
        guard let d = day else { return nil }
        let snippet = mediaStore.snippets.values
            .filter { Calendar.current.isDate($0.date, inSameDayAs: d) }
            .sorted { $0.date < $1.date }
            .first
        guard let data = snippet?.imageData else { return nil }
        return UIImage(data: data)
    }

    private func revealPhotoBadgesSequentially() {
        let keys = monthDays.compactMap { day -> String? in
            guard thumbnail(on: day) != nil else { return nil }
            return day?.dayKey
        }

        revealedBadgeKeys.removeAll()
        for (index, key) in keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.045) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    _ = revealedBadgeKeys.insert(key)
                }
            }
        }
    }

    private func mood(on day: Date?) -> String? {
        guard let d = day else { return nil }
        return MoodStore.shared.moods(for: d.dayKey).last
    }

    private func daysInMonth(_ anchor: Date) -> [Date?] {
        var cal = Calendar.current
        cal.firstWeekday = 1
        let start = cal.date(from: cal.dateComponents([.year, .month], from: anchor))!
        let range = cal.range(of: .day, in: .month, for: start)!
        let firstWeekday = cal.component(.weekday, from: start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var arr: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            arr.append(cal.date(byAdding: .day, value: d - 1, to: start)!)
        }
        return arr
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let day:          Date?
    let isSelected:   Bool
    let isToday:      Bool
    let hasJournal:   Bool
    let thumbnail:    UIImage?
    let isBadgeRevealed: Bool
    let streakState:  CalendarScreen.StreakState
    let dominantMood: String?
    let onSelect:     () -> Void

    private var moodColor: Color { MoodColour.color(for: dominantMood) }
    private var isStreakDay: Bool { streakState != .none }

    var body: some View {
        Button(action: onSelect) {
            GeometryReader { geo in
                let w = geo.size.width
                let cellH = geo.size.height
                let circleD: CGFloat = w - 4   // photo/number circle diameter
                let hasPhotoBadge = thumbnail != nil && isBadgeRevealed

                ZStack {
                    // ── Streak bridge (horizontal pill behind adjacent cells) ──────
                    streakBridge(w: w, h: cellH, circleD: circleD)

                    // ── Main circle ───────────────────────────────────────────────
                    ZStack {
                        if let img = thumbnail, isBadgeRevealed {
                            // Photo badge
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: circleD, height: circleD)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isSelected
                                                ? Memori.Color.accent
                                                : isStreakDay
                                                    ? Memori.Color.accent.opacity(0.55)
                                                    : Memori.Color.inkFaint.opacity(0.3),
                                            lineWidth: isSelected ? 2.5 : 1.5
                                        )
                                )
                                .transition(.scale(scale: 0.72).combined(with: .opacity))
                        } else {
                            // No photo — plain circle background
                            Circle()
                                .fill(
                                    isSelected
                                        ? Memori.Color.accent
                                        : isStreakDay
                                            ? Memori.Color.accentMuted.opacity(0.5)
                                            : Memori.Color.paperAlt
                                )
                                .frame(width: circleD, height: circleD)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isToday && !isSelected
                                                ? Memori.Color.accent.opacity(0.8)
                                                : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }

                        // Day number
                        if let d = day {
                            Text("\(Calendar.current.component(.day, from: d))")
                                .font(Memori.Font.sans(hasPhotoBadge ? 13 : 12,
                                                       weight: isToday || isSelected || hasPhotoBadge ? .semibold : .regular))
                                .foregroundStyle(dateTextColor(hasPhotoBadge: hasPhotoBadge))
                                .shadow(color: dateShadowColor(hasPhotoBadge: hasPhotoBadge),
                                        radius: hasPhotoBadge ? 2.5 : 0,
                                        x: 0,
                                        y: hasPhotoBadge ? 1 : 0)
                        }
                    }
                    .frame(width: circleD, height: circleD)
                    .scaleEffect(thumbnail != nil && !isBadgeRevealed ? 0.82 : 1)
                    .opacity(thumbnail != nil && !isBadgeRevealed ? 0.55 : 1)

                    // ── Journal dot (bottom of circle) ────────────────────────────
                    if hasJournal && thumbnail == nil {
                        Circle()
                            .fill(dominantMood != nil ? moodColor : Memori.Color.inkMid.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .offset(y: circleD * 0.5 + 3)
                    }

                    // ── Flame badge on streak end / single ────────────────────────
                    if streakState == .end || streakState == .single {
                        Text("🔥")
                            .font(.system(size: 10))
                            .offset(x: circleD * 0.32, y: -(circleD * 0.32))
                    }
                }
                .frame(width: w, height: cellH)
            }
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
        .frame(height: 52)
    }

    private func dateTextColor(hasPhotoBadge: Bool) -> Color {
        guard hasPhotoBadge, let thumbnail else {
            if isSelected { return Memori.Color.inkLight }
            if isToday { return Memori.Color.accent }
            return Memori.Color.inkDark
        }

        return thumbnail.memoriAverageLuminance > 0.58
            ? Memori.Color.inkDark
            : Color.white
    }

    private func dateShadowColor(hasPhotoBadge: Bool) -> Color {
        guard hasPhotoBadge, let thumbnail else { return .clear }
        return thumbnail.memoriAverageLuminance > 0.58
            ? Color.white.opacity(0.42)
            : Color.black.opacity(0.62)
    }

    // The horizontal bridge that visually connects streak days across a row.
    @ViewBuilder
    private func streakBridge(w: CGFloat, h: CGFloat, circleD: CGFloat) -> some View {
        let barH: CGFloat  = circleD * 0.72
        let bridgeColor    = Memori.Color.accentMuted.opacity(0.55)
        let halfCell       = w / 2

        switch streakState {
        case .none, .single:
            EmptyView()
        case .start:
            // Bridge from centre → right edge
            Rectangle()
                .fill(bridgeColor)
                .frame(width: halfCell + 1, height: barH)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: barH / 2,
                        bottomLeadingRadius: barH / 2,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
                .offset(x: halfCell / 2)
        case .middle:
            Rectangle()
                .fill(bridgeColor)
                .frame(width: w, height: barH)
        case .end:
            // Bridge from left edge → centre
            Rectangle()
                .fill(bridgeColor)
                .frame(width: halfCell + 1, height: barH)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: barH / 2,
                        topTrailingRadius: barH / 2
                    )
                )
                .offset(x: -(halfCell / 2))
        }
    }
}

// MARK: - JournalStore streak day keys

extension JournalStore {
    var streakDayKeys: Set<String> {
        var result = Set<String>()
        let cal = Calendar.current
        var day = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for _ in 0..<currentStreak {
            result.insert(fmt.string(from: day))
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return result
    }
}

private extension UIImage {
    var memoriAverageLuminance: CGFloat {
        guard let input = cgImage else { return 0.5 }

        let width = 1
        let height = 1
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        context?.interpolationQuality = .medium
        context?.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))

        let r = CGFloat(pixel[0]) / 255
        let g = CGFloat(pixel[1]) / 255
        let b = CGFloat(pixel[2]) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
