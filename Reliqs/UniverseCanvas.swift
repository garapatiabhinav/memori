
// UniverseCanvas.swift
// Memori
//working version before removing autoplay
import SwiftUI
import SceneKit
import simd
import AVKit

struct UniverseCanvas: View {
    @EnvironmentObject var mediaStore:    MediaStore
    @EnvironmentObject var journalStore:  JournalStore
    @EnvironmentObject var universeStore: UniverseStore
    @EnvironmentObject var collageStore:  CollageStore
    @StateObject private var controller   = UniverseSceneController()
    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasScaleStart: CGFloat = 1.0
    @State private var canvasOffsetStart: CGSize = .zero
    @State private var zoomFocalPoint: CGPoint? = nil
    @State private var isEditingGlobes = false

    @State private var selectedGlobe:    MemoryGlobe?   = nil   // drives sheet(item:)
    @State private var globeToDelete:    MemoryGlobe?   = nil
    @State private var showDeleteAlert   = false
    @State private var showNewGlobeField = false
    @State private var newGlobeName      = ""
    @State private var showingAutoplay   = false
    @State private var autoplaySnippets: [MediaSnippet] = []
    @State private var autoplayStartIndex: Int          = 0
    @State private var selectedSnippet:  MediaSnippet?  = nil
    @State private var showCollage       = false
    @State private var canvasOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var globeDragOffsets: [UUID: CGSize] = [:]

    var body: some View {
        ZStack {
            Memori.Color.pageBg.ignoresSafeArea()
            sceneLayer
            ZStack {
                badgeGlobeLayer
                customGlobesLayer
            }
            .scaleEffect(canvasScale, anchor: .center)
            .offset(canvasOffset)
            hudLayer
            if showNewGlobeField {
                newGlobeOverlay.transition(.opacity).zIndex(20)
            }
            // Edit mode overlay — sits above everything, handles xmark + tap-outside + drag
            if isEditingGlobes {
                editModeOverlay
                    .zIndex(30)
            }
        }
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard value.startLocation != value.location else { return }
                canvasOffset = CGSize(
                    width:  dragStartOffset.width  + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                dragStartOffset = canvasOffset
                universeStore.saveOffset(canvasOffset, for: "global")
                let dist = sqrt(canvasOffset.width * canvasOffset.width + canvasOffset.height * canvasOffset.height)
                if dist > 600 {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        canvasOffset = .zero
                        dragStartOffset = .zero
                    }
                }
            }
        )
        .simultaneousGesture(mapZoomGesture)
        .task {
            refreshMemoryBadges(mediaStore.snippets)
            let saved = universeStore.offset(for: "global")
            if saved != .zero {
                canvasOffset = saved
                dragStartOffset = saved
            }
        }
        .onReceive(mediaStore.$snippets) { snippets in
            refreshMemoryBadges(snippets)
        }
        // sheet(item:) — no race condition, globe is always non-nil when sheet renders
        .sheet(item: $selectedGlobe) { globe in
            GlobeDetailSheet(
                globe: globe,
                allSnippets: Array(mediaStore.snippets.values),
                onAutoplay: { _, _ in },
                onDelete: {
                    selectedGlobe  = nil
                    globeToDelete  = globe
                    showDeleteAlert = true
                },
                onAdd: { snippet in
                    mediaStore.insertSnippet(snippet)
                    universeStore.assignSnippet(snippet.id, to: globe.id)
                },
                onRemove: { snippet in
                    universeStore.removeSnippet(snippet.id, from: globe.id)
                },
                onSnippetChange: { mediaStore.updateSnippet(from: $0) },
                onSnippetDelete: { id in mediaStore.deleteSnippet(id: id) },
                mediaStore: mediaStore
            )
        }
        .fullScreenCover(isPresented: $showingAutoplay) {
            AutoplaySlideshow(snippets: autoplaySnippets,
                              startIndex: autoplayStartIndex,
                              onDismiss: { showingAutoplay = false })
        }
        .fullScreenCover(item: $selectedSnippet) { snippet in
            SnippetFullScreen(
                card: snippet.toNoteCard(),
                onClose: { selectedSnippet = nil },
                onChange: { mediaStore.updateSnippet(from: $0) },
                onDelete: { id in
                    mediaStore.deleteSnippet(id: id)
                    selectedSnippet = nil
                }
            )
        }
        .alert("Delete Globe",
               isPresented: $showDeleteAlert,
               presenting: globeToDelete) { g in
            Button("Delete Globe Only", role: .destructive) {
                controller.removeGlobeNode(id: g.id)
                universeStore.deleteGlobe(id: g.id, deleteMemories: false, mediaStore: mediaStore)
            }
            Button("Delete Globe + Memories", role: .destructive) {
                controller.removeGlobeNode(id: g.id)
                universeStore.deleteGlobe(id: g.id, deleteMemories: true, mediaStore: mediaStore)
            }
            Button("Cancel", role: .cancel) {}
        } message: { g in
            Text("What would you like to do with \"\(g.name)\"?")
        }
    }

    // MARK: - Layers

    private var sceneLayer: some View {
        UniverseSceneView(
            controller: controller,
            onDailyTapped: { /* badges handle their own taps */ },
            onGlobeTapped: { id in
                guard let g = universeStore.globes.first(where: { $0.id == id && !$0.isDaily })
                else { return }
                let screenSize = UIScreen.main.bounds.size
                let pos = stableScreenPosition(for: g.id.uuidString, in: screenSize)
                let cx = screenSize.width / 2
                let cy = screenSize.height / 2 - screenSize.height * 0.04
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    canvasOffset = CGSize(width: cx - pos.x, height: cy - pos.y)
                    dragStartOffset = canvasOffset
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selectedGlobe = g
                }
            }
        )
        .ignoresSafeArea()
    }

    private var mapZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomFocalPoint == nil {
                    canvasScaleStart = canvasScale
                    canvasOffsetStart = canvasOffset
                    zoomFocalPoint = v.startLocation
                }
                let newScale = max(0.3, min(4.0, canvasScaleStart * v.magnification))
                let k = newScale / canvasScaleStart
                let midX = UIScreen.main.bounds.width / 2
                let midY = UIScreen.main.bounds.height / 2
                let fX = zoomFocalPoint!.x
                let fY = zoomFocalPoint!.y
                let newOffsetX = canvasOffsetStart.width * k + (fX - midX) * (1 - k)
                let newOffsetY = canvasOffsetStart.height * k + (fY - midY) * (1 - k)
                canvasScale = newScale
                canvasOffset = CGSize(width: newOffsetX, height: newOffsetY)
            }
            .onEnded { _ in
                zoomFocalPoint = nil
                canvasScaleStart = canvasScale
                dragStartOffset = canvasOffset
            }
    }

    private var badgeGlobeLayer: some View {
        BadgeGlobeView(
            snippets: Array(mediaStore.snippets.values),
            onBadgeTap: { selectedSnippet = $0 },
            onBadgeDelete: { snippet in
                mediaStore.deleteSnippet(id: snippet.id)
            }
        )
        .ignoresSafeArea()
        .zIndex(2)
    }

    private var hudLayer: some View {
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
        let tabBarHeight: CGFloat = 54 + bottomInset + 12

        return VStack {
            Spacer()
            HStack(alignment: .bottom) {
                if isEditingGlobes {
                    Button {
                        withAnimation { isEditingGlobes = false }
                        globeDragOffsets.removeAll()
                    } label: {
                        Text("Done")
                            .font(Memori.Font.sans(14, weight: .bold))
                            .foregroundStyle(Memori.Color.paperBg)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(Memori.Color.accent, in: Capsule())
                    }
                } else {
                    CollageHUDButton(showCollage: $showCollage)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        canvasOffset = .zero
                        dragStartOffset = .zero
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Memori.Color.inkFaint)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                addGlobeButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, tabBarHeight)
        }
        .zIndex(5)
        .sheet(isPresented: $showCollage) {
            CollageListScreen(
                store: collageStore,
                mediaStore: mediaStore,
                onClose: { showCollage = false }
            )
        }
    }

    // MARK: - HUD buttons

    private var resetButton: some View {
        Button { controller.resetView(animated: true) } label: {
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Memori.Color.inkFaint)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var addGlobeButton: some View {
        Button { withAnimation(.spring()) { showNewGlobeField = true } } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .medium))
                Text("New Globe")
                    .font(Memori.Font.sans(13, weight: .medium))
            }
            .foregroundStyle(Memori.Color.inkLight)
            .padding(.vertical, 9)
            .padding(.horizontal, 15)
            .background(Memori.Color.accent.opacity(0.85), in: Capsule())
        }
    }

    private var newGlobeOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { withAnimation { showNewGlobeField = false } }
            VStack(spacing: 20) {
                Text("Name Your Globe")
                    .font(Memori.Font.serif(18))
                    .foregroundStyle(Memori.Color.inkLight)
                TextField("e.g. Japan 2025, Family…", text: $newGlobeName)
                    .font(Memori.Font.sans(15))
                    .foregroundStyle(Memori.Color.inkDark)
                    .padding(12)
                    .background(Memori.Color.paperBg, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                HStack(spacing: 16) {
                    Button("Cancel") {
                        newGlobeName = ""
                        withAnimation { showNewGlobeField = false }
                    }
                    .font(Memori.Font.sans(14))
                    .foregroundStyle(Memori.Color.inkMid)

                    Button("Create") {
                        let name = newGlobeName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        let g = universeStore.addGlobe(name: name)
                        controller.addGlobeNode(globe: g)
                        newGlobeName = ""
                        withAnimation { showNewGlobeField = false }

                        let screenSize = UIScreen.main.bounds.size
                        let cx = screenSize.width  / 2
                        let cy = screenSize.height / 2 - screenSize.height * 0.04

                        // Place the new globe at a fixed canvas-space offset so it always
                        // appears distinctly away from the daily globe.
                        let spawnCanvasX: CGFloat = 340
                        let spawnCanvasY: CGFloat = -60
                        let basePos = stableScreenPosition(for: g.id.uuidString, in: screenSize)
                        let neededOffset = CGSize(
                            width:  (cx + spawnCanvasX) - basePos.x,
                            height: (cy + spawnCanvasY) - basePos.y
                        )
                        universeStore.saveOffset(neededOffset, for: g.id.uuidString)

                        // Animate canvas to center on the new globe and zoom in
                        let targetScale: CGFloat = 1.6
                        let newOffsetX = (canvasOffset.width - spawnCanvasX) * targetScale / max(canvasScale, 0.01)
                        let newOffsetY = (canvasOffset.height - spawnCanvasY) * targetScale / max(canvasScale, 0.01)

                        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                            canvasScale      = targetScale
                            canvasScaleStart = targetScale
                            canvasOffset     = CGSize(width: newOffsetX, height: newOffsetY)
                            dragStartOffset  = canvasOffset
                        }
                        universeStore.saveOffset(canvasOffset, for: "global")
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

    // MARK: - Helpers

    // MARK: - Edit mode overlay (xmark badges + drag + tap-outside)
    private var editModeOverlay: some View {
        GeometryReader { geo in
            let customGlobes = universeStore.globes.filter { !$0.isDaily }
            // The customGlobesLayer sits inside .scaleEffect(canvasScale).offset(canvasOffset).
            // The overlay is in screen space, so we must apply the same transform to
            // match globe positions: screenPt = canvasPt * canvasScale + canvasOffset
            let midX = geo.size.width  / 2
            let midY = geo.size.height / 2

            ZStack {
                // Tap-outside: TapGesture only — DragGesture falls through to canvas
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        withAnimation { isEditingGlobes = false }
                        globeDragOffsets.removeAll()
                    })

                ForEach(customGlobes, id: \.id) { globe in
                    let basePos    = stableScreenPosition(for: globe.id.uuidString, in: geo.size)
                    let savedOff   = universeStore.offset(for: globe.id.uuidString)
                    let liveOff    = globeDragOffsets[globe.id] ?? .zero
                    // Canvas-space position of the globe centre
                    let canvasX    = basePos.x + savedOff.width  + liveOff.width
                    let canvasY    = basePos.y + savedOff.height + liveOff.height
                    // Convert to screen space (same math as .scaleEffect + .offset)
                    let screenX    = (canvasX - midX) * canvasScale + midX + canvasOffset.width
                    let screenY    = (canvasY - midY) * canvasScale + midY + canvasOffset.height
                    let screenPos  = CGPoint(x: screenX, y: screenY)
                    // Xmark sits 36pt above-right at native scale (not canvas scale)
                    let xmarkX     = screenX + 36
                    let xmarkY     = screenY - 36

                    // Invisible drag handle centred on the globe in screen space
                    Color.clear
                        .frame(width: 100, height: 100)
                        .contentShape(Rectangle())
                        .position(x: screenPos.x, y: screenPos.y)
                        .gesture(DragGesture(minimumDistance: 4)
                            .onChanged { v in
                                // Drag translation is in screen pts; divide by scale to get canvas pts
                                globeDragOffsets[globe.id] = CGSize(
                                    width:  v.translation.width  / canvasScale,
                                    height: v.translation.height / canvasScale
                                )
                            }
                            .onEnded { v in
                                let current = universeStore.offset(for: globe.id.uuidString)
                                universeStore.saveOffset(
                                    CGSize(
                                        width:  current.width  + v.translation.width  / canvasScale,
                                        height: current.height + v.translation.height / canvasScale
                                    ),
                                    for: globe.id.uuidString
                                )
                                globeDragOffsets[globe.id] = nil
                            }
                        )

                    // Xmark button — follows the globe in screen space
                    Button {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        globeToDelete = globe
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.red, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .position(x: xmarkX, y: xmarkY)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private var customGlobesLayer: some View {
        GeometryReader { geo in
            let customGlobes = universeStore.globes.filter { !$0.isDaily }
            ZStack {
                ForEach(customGlobes, id: \.id) { globe in
                    let globeSnippets = globe.snippetIDs.compactMap { mediaStore.snippets[$0] }
                    let basePos = stableScreenPosition(for: globe.id.uuidString, in: geo.size)
                    let savedOffset = universeStore.offset(for: globe.id.uuidString)
                    let liveOffset = globeDragOffsets[globe.id] ?? .zero
                    let pos = CGPoint(
                        x: basePos.x + savedOffset.width + liveOffset.width,
                        y: basePos.y + savedOffset.height + liveOffset.height
                    )
                    MiniGlobeView(
                        name: globe.name,
                        snippets: globeSnippets,
                        isEditing: $isEditingGlobes,
                        onPositionChange: { _ in },  // drag handled by editModeOverlay
                        onTap: { selectedGlobe = globe },
                        onDelete: {
                            globeToDelete = globe
                            showDeleteAlert = true
                        }
                    )
                    .position(pos)
                }
            }
        }
        .ignoresSafeArea()
        .zIndex(4)
    }

    /// Deterministic screen position per globe ID, spread well outside the main globe
    private func stableScreenPosition(for key: String, in size: CGSize) -> CGPoint {
        var h: UInt64 = 14695981039346656037
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let angle = Double(h & 0xFFFF) / 65535.0 * 2.0 * Double.pi
        let r    = 280.0 + Double((h >> 16) & 0xFFFF) / 65535.0 * 140.0
        let cx   = size.width  / 2
        let cy   = size.height / 2 - size.height * 0.04
        return CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
    }

    private func refreshMemoryBadges(_ snippets: [UUID: MediaSnippet]) {
        universeStore.rebuild(snippets: snippets, journal: journalStore.entries)
        controller.updatePhotoPins(snippets: Array(snippets.values))
    }
}
