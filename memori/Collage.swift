//
//  Collage.swift
//  memori
//
//  Created by Abhinav Garapati on 22/05/26.
//


// CollageView.swift
// Memori
// A curated collage screen. Each collage is a square grid where photo cells
// are filled first; remaining cells each show a hand-drawn SVG-style flower.

import SwiftUI

// MARK: - Model

struct Collage: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isDefault: Bool          // true = "Today" auto-collage
    var snippetIDs: [UUID]       // ordered list of photos in the grid

    static func makeToday() -> Collage {
        Collage(id: UUID(), name: "Today", isDefault: true, snippetIDs: [])
    }
}

// MARK: - Store

final class CollageStore: ObservableObject {
    @Published var collages: [Collage] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("collages.json")
    }()

    init() {
        load()
        if !collages.contains(where: { $0.isDefault }) {
            collages.insert(Collage.makeToday(), at: 0)
            save()
        }
    }

    func addCollage(name: String) {
        collages.append(Collage(id: UUID(), name: name, isDefault: false, snippetIDs: []))
        save()
    }

    func delete(id: UUID) {
        collages.removeAll { $0.id == id && !$0.isDefault }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(collages) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Collage].self, from: data)
        else { return }
        collages = decoded
    }
}

// MARK: - Collage Button (shown in UniverseCanvas HUD)

struct CollageHUDButton: View {
    @Binding var showCollage: Bool

    var body: some View {
        Button { showCollage = true } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Memori.Color.inkFaint)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

// MARK: - Root Collage Screen

struct CollageListScreen: View {
    @ObservedObject var store: CollageStore
    @ObservedObject var mediaStore: MediaStore
    var onClose: () -> Void

    @State private var selectedCollage: Collage? = nil
    @State private var showNewField = false
    @State private var newName = ""

    var body: some View {
        ZStack {
            Memori.Color.pageBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Memori.Color.inkFaint.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                // Header
                HStack {
                    Text("collages")
                        .font(Memori.Font.serif(20))
                        .foregroundStyle(Memori.Color.inkLight)
                    Spacer()
                    Button { showNewField = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Memori.Color.inkMid)
                            .frame(width: 32, height: 32)
                            .background(Memori.Color.surfaceMid, in: Circle())
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Memori.Color.inkMid)
                            .frame(width: 32, height: 32)
                            .background(Memori.Color.surfaceMid, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.collages) { collage in
                            let snippets = resolvedSnippets(for: collage)
                            CollageThumbnailRow(collage: collage, snippets: snippets) {
                                selectedCollage = collage
                            } onDelete: {
                                store.delete(id: collage.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }

            if showNewField {
                newCollageOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(item: $selectedCollage) { collage in
            CollageDetailScreen(
                collage: collage,
                snippets: resolvedSnippets(for: collage),
                onClose: { selectedCollage = nil }
            )
        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationCornerRadius(24)
    }

    private func resolvedSnippets(for collage: Collage) -> [MediaSnippet] {
        if collage.isDefault {
            // "Today" = all photos captured today, newest first
            return mediaStore.snippets.values
                .filter { Calendar.current.isDateInToday($0.date) }
                .sorted { $0.date > $1.date }
        }
        return collage.snippetIDs.compactMap { mediaStore.snippets[$0] }
    }

    private var newCollageOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { showNewField = false }
            VStack(spacing: 20) {
                Text("Name Your Collage")
                    .font(Memori.Font.serif(18))
                    .foregroundStyle(Memori.Color.inkLight)
                TextField("e.g. Weekend, Trip…", text: $newName)
                    .font(Memori.Font.sans(15))
                    .foregroundStyle(Memori.Color.inkDark)
                    .padding(12)
                    .background(Memori.Color.paperBg, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                HStack(spacing: 16) {
                    Button("Cancel") { newName = ""; showNewField = false }
                        .font(Memori.Font.sans(14))
                        .foregroundStyle(Memori.Color.inkMid)
                    Button("Create") {
                        let n = newName.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        store.addCollage(name: n)
                        newName = ""; showNewField = false
                    }
                    .font(Memori.Font.sans(14, weight: .semibold))
                    .foregroundStyle(Memori.Color.inkLight)
                    .padding(.vertical, 10).padding(.horizontal, 20)
                    .background(Memori.Color.accent, in: Capsule())
                }
            }
            .padding(28)
            .background(Color(hex: "#241A12"), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Collage Thumbnail Row

private struct CollageThumbnailRow: View {
    let collage: Collage
    let snippets: [MediaSnippet]
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Mini 2×2 preview
                miniGrid
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(collage.name)
                        .font(Memori.Font.serif(16))
                        .foregroundStyle(Memori.Color.inkLight)
                    Text("\(snippets.count) \(snippets.count == 1 ? "photo" : "photos")")
                        .font(Memori.Font.sans(11))
                        .foregroundStyle(Memori.Color.inkMid)
                }

                Spacer()

                if !collage.isDefault {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Memori.Color.inkMid.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Memori.Color.surfaceDark, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var miniGrid: some View {
        let cols = 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: cols), spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                if i < snippets.count, let data = snippets[i].imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    FlowerCell(seed: i, size: 36)
                }
            }
        }
        .background(Memori.Color.surfaceMid)
    }
}

// MARK: - Full Collage Detail Screen

struct CollageDetailScreen: View {
    let collage: Collage
    let snippets: [MediaSnippet]
    var onClose: () -> Void

    @State private var selectedSnippet: MediaSnippet? = nil

    // Grid side: smallest N where N² ≥ count, minimum 2
    private var gridSide: Int {
        let count = max(snippets.count, 1)
        var n = 2
        while n * n < count { n += 1 }
        return n
    }

    private var totalCells: Int { gridSide * gridSide }

    var body: some View {
        ZStack {
            Memori.Color.pageBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collage.name)
                            .font(Memori.Font.serif(20))
                            .foregroundStyle(Memori.Color.inkLight)
                        Text("\(snippets.count) \(snippets.count == 1 ? "photo" : "photos") · \(gridSide)×\(gridSide) grid")
                            .font(Memori.Font.sans(11))
                            .foregroundStyle(Memori.Color.inkMid)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Memori.Color.inkMid)
                            .frame(width: 32, height: 32)
                            .background(Memori.Color.surfaceMid, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Square grid
                GeometryReader { geo in
                    let spacing: CGFloat = 3
                    let totalSpacing = spacing * CGFloat(gridSide - 1)
                    let cellSize = (geo.size.width - totalSpacing) / CGFloat(gridSide)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: gridSide),
                        spacing: spacing
                    ) {
                        ForEach(0..<totalCells, id: \.self) { i in
                            if i < snippets.count {
                                let snippet = snippets[i]
                                photoCell(snippet: snippet, size: cellSize)
                            } else {
                                FlowerCell(seed: i, size: cellSize)
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                .padding(.horizontal, 3)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .fullScreenCover(item: $selectedSnippet) { snippet in
            SnippetFullScreen(
                card: snippet.toNoteCard(),
                onClose: { selectedSnippet = nil },
                onChange: { _ in },
                onDelete: { _ in selectedSnippet = nil }
            )
        }
        .presentationDetents([.large])
        .presentationCornerRadius(24)
    }

    private func photoCell(snippet: MediaSnippet, size: CGFloat) -> some View {
        Button { selectedSnippet = snippet } label: {
            Group {
                if let data = snippet.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Memori.Color.surfaceMid
                    Image(systemName: "photo")
                        .foregroundStyle(Memori.Color.inkMid.opacity(0.4))
                }
            }
            .frame(width: size, height: size)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flower Cell
// Draws a simple 5-petal flower in SwiftUI Canvas. Each cell gets a unique
// warm background and contrasting flower colour derived from its seed index.

struct FlowerCell: View {
    let seed: Int
    let size: CGFloat

    // Warm background palettes — background and petal are always different
    private static let backgrounds: [Color] = [
        Color(hex: "#3D2010"),  // dark amber
        Color(hex: "#2A1A0E"),  // deep brown
        Color(hex: "#1E1408"),  // near-black brown
        Color(hex: "#321808"),  // burnt sienna dark
        Color(hex: "#28180C"),  // chestnut dark
        Color(hex: "#1C1209"),  // espresso
    ]

    private static let petalColors: [Color] = [
        Color(hex: "#E8954A"),  // tangerine
        Color(hex: "#D4714F"),  // terracotta
        Color(hex: "#C98B3A"),  // golden amber
        Color(hex: "#B85C3C"),  // burnt orange
        Color(hex: "#DFA050"),  // warm saffron
        Color(hex: "#C26040"),  // rust
        Color(hex: "#E8B86D"),  // honey
        Color(hex: "#A04830"),  // brick
    ]

    private static let centerColors: [Color] = [
        Color(hex: "#F5D080"),  // warm yellow
        Color(hex: "#EEC86A"),  // golden
        Color(hex: "#F0C050"),  // sunflower
        Color(hex: "#E8D890"),  // pale gold
    ]

    private var bg: Color { Self.backgrounds[seed % Self.backgrounds.count] }
    private var petal: Color {
        // offset from bg index so they never match
        Self.petalColors[(seed + 2) % Self.petalColors.count]
    }
    private var center: Color { Self.centerColors[seed % Self.centerColors.count] }

    // Stable per-seed rotation and slight size variation
    private var rotation: Double { Double(seed * 37 % 360) }
    private var petalScale: CGFloat { 0.82 + CGFloat(seed % 5) * 0.038 }

    var body: some View {
        ZStack {
            bg

            Canvas { ctx, sz in
                let cx = sz.width / 2
                let cy = sz.height / 2
                let petalL = sz.width * 0.28 * petalScale   // petal long axis
                let petalW = sz.width * 0.13 * petalScale   // petal short axis
                let petalOff = sz.width * 0.16 * petalScale // distance from centre

                // 5 petals
                for i in 0..<5 {
                    let angle = (Double(i) * 72 + rotation) * .pi / 180
                    var path = Path(ellipseIn: CGRect(
                        x: cx - petalW / 2,
                        y: cy - petalL - petalOff,
                        width: petalW,
                        height: petalL
                    ))
                    // Rotate petal around centre
                    let xform = CGAffineTransform(translationX: cx, y: cy)
                        .rotated(by: angle)
                        .translatedBy(x: -cx, y: -cy)
                    path = path.applying(xform)
                    ctx.fill(path, with: .color(petal))
                }

                // Centre dot
                let dotR = sz.width * 0.085
                let dotPath = Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
                ctx.fill(dotPath, with: .color(center))
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

