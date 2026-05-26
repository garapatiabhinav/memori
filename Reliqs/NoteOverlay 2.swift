// NoteOverlay.swift
// Memori
// Created by Abhinav Garapati

import SwiftUI
import AVKit

struct NoteOverlay: View {
    var card: NoteCard
    var onChange: (NoteCard) -> Void
    var onDismiss: (NoteCard) -> Void
    var onOpenFullScreen: () -> Void
    var onDelete: ((UUID) -> Void)? = nil
    @ObservedObject var mediaStore: MediaStore

    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var keyboard = KeyboardObserver()
    @State private var showMediaOnly = false
    @State private var draft = ""
    @State private var dragY: CGFloat = 0
    @State private var showDeleteConfirm = false
    @FocusState private var isDraftFocused: Bool

    private let closeDistance: CGFloat = 120
    // Image takes roughly 46% of screen; note gets the rest
    private let imageFraction: CGFloat = 0.46

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Memori.Color.pageBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    let keyboardOffset = keyboard.height
                    // Image shrinks proportionally as keyboard rises
                    let imageSlot = (geo.size.height - keyboardOffset) * imageFraction
                    let imageD = min(imageSlot * 0.82, geo.size.width * 0.78)

                    mediaPreview(diameter: imageD)
                        .animation(.easeOut(duration: keyboard.animationDuration), value: keyboard.height)

                    // Note fills every remaining pixel
                    noteEditor
                        .animation(.easeOut(duration: keyboard.animationDuration), value: keyboard.height)
                }
                .padding(.bottom, keyboard.height)
                .animation(.easeOut(duration: keyboard.animationDuration), value: keyboard.height)
                .offset(y: dragY)
                .gesture(dragGesture)

                topBar(geo: geo)
            }
            .onAppear { draft = card.text }
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showMediaOnly) {
            FullScreenMediaView(image: card.image, videoURL: card.videoURL, onDone: { showMediaOnly = false })
        }
        .alert("Delete this memory?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete?(card.id)
                var updated = card; updated.text = draft
                onDismiss(updated)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the photo and its globe pin.")
        }
    }

    // MARK: - Top bar
    private func topBar(geo: GeometryProxy) -> some View {
        VStack {
            HStack {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Memori.Color.inkMid)
                        .padding(10)
                        .background(Memori.Color.surfaceMid, in: Circle())
                }

                Spacer()

                Button {
                    var updated = card
                    updated.text = draft
                    onChange(updated)
                    onDismiss(updated)
                } label: {
                    Text("done")
                        .font(Memori.Font.sans(13, weight: .medium))
                        .foregroundStyle(Memori.Color.inkLight)
                        .tracking(1)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Memori.Color.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, geo.size.height * 0.02)
            Spacer()
        }
        .zIndex(20)
        .allowsHitTesting(true)
    }

    // MARK: - Media preview — diameter driven by caller
    private func mediaPreview(diameter: CGFloat) -> some View {
        Group {
            if let url = card.videoURL {
                AutoLoopingVideoView(url: url)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Memori.Color.inkFaint.opacity(0.4), lineWidth: 1.5))
                    .onTapGesture { openFullscreen() }
            } else if let img = card.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Memori.Color.inkFaint.opacity(0.4), lineWidth: 1.5))
                    .onTapGesture { openFullscreen() }
            }
        }
        .padding(.top, 56)
        .frame(maxWidth: .infinity)
    }

    private func openFullscreen() {
        if presentationMode.wrappedValue.isPresented { showMediaOnly = true }
        else { onOpenFullScreen() }
    }

    // MARK: - Note editor — expands to fill remaining space
    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("add a note")
                    .font(Memori.Font.sans(12))
                    .foregroundStyle(Memori.Color.inkMid)
                    .tracking(0.8)
                Spacer()
                Text(card.date, format: .dateTime.hour().minute())
                    .font(Memori.Font.sans(11))
                    .foregroundStyle(Memori.Color.inkMid)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Memori.Color.paperBg)

                if draft.isEmpty {
                    Text("what does this moment mean to you?")
                        .font(Memori.Font.serif(14))
                        .foregroundStyle(Memori.Color.inkFaint)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draft)
                    .focused($isDraftFocused)
                    .scrollContentBackground(.hidden)
                    .font(Memori.Font.serif(15))
                    .foregroundStyle(Memori.Color.inkDark)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .background(.clear)
            }
            .frame(maxHeight: .infinity)   // fill all available height
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .layoutPriority(1)                 // claim remaining space after image
    }

    // MARK: - Drag to dismiss
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 { dragY = value.translation.height }
            }
            .onEnded { value in
                if value.translation.height > closeDistance || value.predictedEndTranslation.height > 400 {
                    var updated = card; updated.text = draft
                    onDismiss(updated)
                } else {
                    withAnimation(.spring()) { dragY = 0 }
                }
            }
    }
}

// MARK: - AutoLoopingVideoView
struct AutoLoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        LoopingPlayerView(url: url)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? LoopingPlayerView)?.updateFrame()
    }
}

final class LoopingPlayerView: UIView {
    private let player: AVPlayer
    private let playerLayer: AVPlayerLayer

    init(url: URL) {
        player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        layer.addSublayer(playerLayer)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        player.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFrame()
    }

    func updateFrame() { playerLayer.frame = bounds }
}

// MARK: - FullScreenMediaView
struct FullScreenMediaView: View {
    let image: UIImage?
    let videoURL: URL?
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if let url = videoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }

            VStack {
                Spacer()
                Button(action: onDone) {
                    Text("done")
                        .font(Memori.Font.sans(14, weight: .medium))
                        .foregroundStyle(Memori.Color.inkLight)
                        .tracking(1)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                        .background(Color.black.opacity(0.55), in: Capsule())
                }
                .padding(.bottom, 40)
            }
        }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 120 { onDone() }
            }
        )
    }
}
