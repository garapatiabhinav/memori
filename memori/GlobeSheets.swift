// GlobeSheets.swift
// Memori

import SwiftUI
import AVKit
import PhotosUI

// MARK: - Globe Detail Sheet

struct GlobeDetailSheet: View {
    let globe:       MemoryGlobe
    var allSnippets: [MediaSnippet] = []
    var onAutoplay:  ([MediaSnippet], Int) -> Void
    var onDelete:    (() -> Void)? = nil
    var onAdd:       ((MediaSnippet) -> Void)? = nil
    var onRemove:    ((MediaSnippet) -> Void)? = nil

    var onSnippetChange: ((NoteCard) -> Void)? = nil
    var onSnippetDelete: ((UUID) -> Void)? = nil

    @ObservedObject var mediaStore: MediaStore

    // ── FIX: track snippet IDs in @State so additions/removals are immediately visible ──
    // `globe` is a `let` constant frozen at sheet-open time; its `snippetIDs` never
    // updates while the sheet is open. Mirroring it into @State and updating it inside
    // the add/remove wrappers below makes `liveSnippets` reactive.
    @State private var snippetIDs: [UUID] = []

    private var liveSnippets: [MediaSnippet] {
        if globe.isDaily {
            return mediaStore.snippets.values
                .filter { Calendar.current.isDateInToday($0.date) }
                .sorted { $0.date < $1.date }
        }
        return snippetIDs.compactMap { mediaStore.snippets[$0] }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSnippet: MediaSnippet? = nil

    private enum ActiveSheet: Identifiable {
        case photoPicker, addPicker
        var id: Int { hashValue }
    }
    @State private var activeSheet: ActiveSheet? = nil

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Memori.Color.pageBg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(globe.name)
                            .font(Memori.Font.serif(20))
                            .foregroundStyle(Memori.Color.inkLight)
                        Text("\(liveSnippets.count) \(liveSnippets.count == 1 ? "memory" : "memories")")
                            .font(Memori.Font.sans(11))
                            .foregroundStyle(Memori.Color.inkMid)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        if !globe.isDaily {
                            Button { activeSheet = .photoPicker } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Memori.Color.inkLight)
                                    .frame(width: 32, height: 32)
                                    .background(Memori.Color.accent, in: Circle())
                            }
                        }
                        if let onDelete, !globe.isDaily {
                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Memori.Color.inkMid)
                                    .frame(width: 32, height: 32)
                                    .background(Memori.Color.surfaceMid, in: Circle())
                            }
                        }
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Memori.Color.inkMid)
                                .frame(width: 32, height: 32)
                                .background(Memori.Color.surfaceMid, in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Grid / empty state
                if liveSnippets.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(Memori.Color.inkMid.opacity(0.4))
                        Text("No memories yet")
                            .font(Memori.Font.serif(15))
                            .foregroundStyle(Memori.Color.inkMid)
                        if !globe.isDaily {
                            Button { activeSheet = .photoPicker } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("Add memories")
                                }
                                .font(Memori.Font.sans(13, weight: .medium))
                                .foregroundStyle(Memori.Color.inkLight)
                                .padding(.vertical, 10).padding(.horizontal, 20)
                                .background(Memori.Color.accent, in: Capsule())
                            }
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 2) {
                            ForEach(Array(liveSnippets.enumerated()), id: \.element.id) { _, snippet in
                                Button { selectedSnippet = snippet } label: {
                                    SnippetThumb(snippet: snippet).aspectRatio(1, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                        guard !globe.isDaily else { return }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        removeSnippet(snippet)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        // Seed snippetIDs from globe on first appear
        .onAppear {
            snippetIDs = globe.snippetIDs
        }
        .fullScreenCover(item: $selectedSnippet) { snippet in
            SnippetFullScreen(
                card: snippet.toNoteCard(),
                onClose: { selectedSnippet = nil },
                onChange: { onSnippetChange?($0) },
                onDelete: { id in onSnippetDelete?(id); selectedSnippet = nil }
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .photoPicker:
                PhotoLibraryPicker { picked in
                    picked.forEach { addSnippet($0) }
                }
            case .addPicker:
                AddToGlobeSheet(
                    alreadyInGlobe: Set(liveSnippets.map { $0.id }),
                    allSnippets: allSnippets,
                    onSelect: { addSnippet($0) }
                )
            }
        }
        .presentationDetents([.large, .medium])
        .presentationCornerRadius(24)
    }

    // MARK: - Helpers that update local state AND call the external handler

    private func addSnippet(_ snippet: MediaSnippet) {
        // Insert into mediaStore + universeStore via the external handler
        onAdd?(snippet)
        // Immediately reflect in local state so liveSnippets recomputes
        if !snippetIDs.contains(snippet.id) {
            snippetIDs.append(snippet.id)
        }
    }

    private func removeSnippet(_ snippet: MediaSnippet) {
        onRemove?(snippet)
        snippetIDs.removeAll { $0 == snippet.id }
    }
}

// MARK: - Add To Globe Picker

struct AddToGlobeSheet: View {
    let alreadyInGlobe: Set<UUID>
    let allSnippets: [MediaSnippet]
    var onSelect: (MediaSnippet) -> Void
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var available: [MediaSnippet] {
        allSnippets.filter { !alreadyInGlobe.contains($0.id) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            Memori.Color.pageBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to Globe")
                            .font(Memori.Font.serif(18))
                            .foregroundStyle(Memori.Color.inkLight)
                        Text("Tap to add · Long-press in globe to remove")
                            .font(Memori.Font.sans(10))
                            .foregroundStyle(Memori.Color.inkMid)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Memori.Color.inkMid)
                            .frame(width: 32, height: 32)
                            .background(Memori.Color.surfaceMid, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

                if available.isEmpty {
                    Spacer()
                    Text("All memories are already in this globe.")
                        .font(Memori.Font.serif(14))
                        .foregroundStyle(Memori.Color.inkMid)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 2) {
                            ForEach(available, id: \.id) { snippet in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onSelect(snippet)
                                    dismiss()
                                } label: {
                                    SnippetThumb(snippet: snippet).aspectRatio(1, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }
}

// MARK: - Autoplay Slideshow

struct AutoplaySlideshow: View {
    let snippets:   [MediaSnippet]
    let startIndex: Int
    let onDismiss:  () -> Void

    @State private var current: Int    = 0
    @State private var opacity: Double = 1
    @State private var timer:   Timer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !snippets.isEmpty {
                mediaView.opacity(opacity)
                captionView.opacity(opacity)
                progressDots
                closeButton
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if      v.translation.width < -30 { go(to: (current + 1) % snippets.count) }
            else if v.translation.width >  30 { go(to: (current - 1 + snippets.count) % snippets.count) }
            else if v.translation.height > 80 { stopTimer(); onDismiss() }
        })
        .onAppear    { current = max(0, min(startIndex, snippets.count - 1)); startTimer() }
        .onDisappear { stopTimer() }
    }

    @ViewBuilder
    private var mediaView: some View {
        let s = snippets[current]
        if let d = s.imageData, let img = UIImage(data: d) {
            Image(uiImage: img).resizable().scaledToFit().ignoresSafeArea()
        } else if let path = s.videoPath {
            VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: path))).ignoresSafeArea()
        } else {
            Memori.Color.pageBg.ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var captionView: some View {
        let s = snippets[current]
        VStack {
            Spacer()
            if !s.text.isEmpty {
                Text(s.text)
                    .font(Memori.Font.serif(17))
                    .foregroundStyle(Memori.Color.inkLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
            }
        }
    }

    private var progressDots: some View {
        VStack {
            HStack(spacing: 5) {
                ForEach(0..<snippets.count, id: \.self) { i in
                    Capsule()
                        .fill(i == current ? Memori.Color.inkLight : Memori.Color.inkMid.opacity(0.4))
                        .frame(width: i == current ? 20 : 6, height: 4)
                        .animation(.spring(response: 0.3), value: current)
                }
            }
            .padding(.top, 60)
            Spacer()
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { stopTimer(); onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Memori.Color.inkLight)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 56)
                .padding(.trailing, 20)
            }
            Spacer()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in advance() }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func advance() {
        withAnimation(.easeInOut(duration: 0.4)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            current = (current + 1) % snippets.count
            withAnimation(.easeInOut(duration: 0.4)) { opacity = 1 }
        }
    }
    private func go(to i: Int) {
        stopTimer()
        withAnimation(.easeInOut(duration: 0.3)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            current = max(0, min(snippets.count - 1, i))
            withAnimation(.easeInOut(duration: 0.3)) { opacity = 1 }
            startTimer()
        }
    }
}

// MARK: - Snippet Thumb

struct SnippetThumb: View {
    let snippet: MediaSnippet

    var body: some View {
        ZStack {
            Memori.Color.surfaceDark
            if let d = snippet.imageData, let img = UIImage(data: d) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else if snippet.videoPath != nil {
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Memori.Color.inkMid)
            } else {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundStyle(Memori.Color.inkMid.opacity(0.5))
            }
        }
        .clipShape(Rectangle())
    }
}

// MARK: - Photo Library Picker

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPick: ([MediaSnippet]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0
        config.filter         = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            var images: [UIImage] = []
            let group = DispatchGroup()

            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { images.append(img) }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let snippets = images.compactMap { img -> MediaSnippet? in
                    guard let data = img.jpegData(compressionQuality: 0.82) else { return nil }
                    return MediaSnippet(id: UUID(), date: Date(), text: "", imageData: data)
                }
                self.parent.onPick(snippets)
            }
        }
    }
}
