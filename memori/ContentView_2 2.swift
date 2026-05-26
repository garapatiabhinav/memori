// ContentView.swift
// Memori
// Created by Abhinav Garapati

import SwiftUI
import AVKit
import UIKit
import PhotosUI

// MARK: - UI Card
struct NoteCard: Identifiable {
    let id: UUID
    var date: Date
    var image: UIImage? = nil
    var text: String = ""
    var color: Color = Memori.Color.paperBg
    var videoURL: URL? = nil
}

enum AppSection { case camera, globe, journal }

struct ContentView: View {
    @ObservedObject private var cam = CameraManager.shared
    @StateObject private var journalStore = JournalStore()
    @StateObject private var mediaStore = MediaStore()
    @StateObject private var universeStore = UniverseStore()
    @StateObject private var collageStore = CollageStore()

    @State private var showCalendar = false
    @State private var journalDate = Date()
    @State private var currentCaptureID: UUID?
    @State private var showPermissionAlert = false
    @State private var section: AppSection = .camera
    @State private var openNoteID: UUID?
    @State private var fullScreenNote: NoteCard?
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?
    @State private var showNoteOverlayFromOrb = false
    @State private var flash = false
    @State private var showMediaPicker = false
    @State private var pickedItem: PhotosPickerItem?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Memori.Color.pageBg.ignoresSafeArea()

            // All three views stay alive — never torn down when switching tabs.
            // This prevents state loss (globe nodes, camera session, journal scroll).
            cameraView
                .opacity(section == .camera ? 1 : 0)
                .allowsHitTesting(section == .camera)

            globeView
                .opacity(section == .globe ? 1 : 0)
                .allowsHitTesting(section == .globe)

            journalView
                .opacity(section == .journal ? 1 : 0)
                .allowsHitTesting(section == .journal)

            if let id = openNoteID, let snippet = mediaStore.snippets[id] {
                NoteOverlay(
                    card: snippet.toNoteCard(),
                    onChange: { updated in mediaStore.updateSnippet(from: updated) },
                    onDismiss: { finalCard in
                        openNoteID = nil
                        mediaStore.saveSnippet(from: finalCard)
                    },
                    onOpenFullScreen: { fullScreenNote = snippet.toNoteCard() },
                    mediaStore: mediaStore
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            bottomTabBar
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showNoteOverlayFromOrb) {
            if let id = currentCaptureID {
                let baseCard = mediaStore.snippets[id]?.toNoteCard()
                    ?? NoteCard(id: id, date: Date(), image: capturedImage, videoURL: capturedVideoURL)
                NoteOverlay(
                    card: baseCard,
                    onChange: { mediaStore.updateSnippet(from: $0) },
                    onDismiss: { finalCard in
                        showNoteOverlayFromOrb = false
                        mediaStore.saveSnippet(from: finalCard)
                    },
                    onOpenFullScreen: { fullScreenNote = mediaStore.snippets[id]?.toNoteCard() },
                    mediaStore: mediaStore
                )
            }
        }
        .onChange(of: showNoteOverlayFromOrb) { _, isShowing in
            if isShowing {
                CameraManager.shared.stop()
            } else {
                // Resume camera whenever the sheet fully closes,
                // whether via the Done button or a swipe-down dismiss.
                if section == .camera {
                    CameraManager.shared.start()
                }
            }
        }
        .fullScreenCover(item: $fullScreenNote) { card in
            SnippetFullScreen(
                card: card,
                onClose: { fullScreenNote = nil },
                onChange: { mediaStore.updateSnippet(from: $0) },
                onDelete: { id in
                    mediaStore.deleteSnippet(id: id)
                    fullScreenNote = nil
                }
            )
        }
        .sheet(isPresented: $showCalendar) {
            CalendarScreen(
                monthAnchor: journalDate,
                selectedDate: $journalDate,
                store: journalStore,
                mediaStore: mediaStore,
                onClose: { showCalendar = false }
            )
        }
        .onChange(of: cam.lastPhoto) { _, image in
            guard let image else { return }
            // If a note overlay is already open (rapid shutter), just save silently —
            // don't open another sheet on top.
            let id = UUID()
            let newCard = NoteCard(id: id, date: Date(), image: image.upright())
            mediaStore.saveSnippet(from: newCard)
            guard !showNoteOverlayFromOrb else { return }
            capturedImage = image
            capturedVideoURL = nil
            currentCaptureID = id
            showNoteOverlayFromOrb = true
            withAnimation(.easeOut(duration: 0.18)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeIn(duration: 0.18)) { flash = false }
            }
        }
        .onAppear { }
        .onReceive(mediaStore.$snippets) { _ in }
        .onReceive(CameraManager.shared.$permissionDeniedFor) { p in
            showPermissionAlert = (p != .none)
        }
        .alert("Permission needed", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let p = CameraManager.shared.permissionDeniedFor
            switch p {
            case .camera:
                Text("Memori needs camera access to capture moments. Enable it in Settings.")
            case .microphone:
                Text("Memori needs microphone access to record videos. Enable it in Settings.")
            case .both:
                Text("Memori needs camera and microphone access. Enable both in Settings.")
            case .none:
                Text("")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                mediaStore.flushSaveSync()
                journalStore.flushSaveSync()
            }
        }
        .onChange(of: section) { _, newSection in
            if newSection == .camera && !showNoteOverlayFromOrb {
                CameraManager.shared.start()
            } else {
                CameraManager.shared.stop()
            }
        }
    }

    // MARK: - Camera View
    private var cameraView: some View {
        ZStack {
            CameraPreviewView()
                .ignoresSafeArea()
                .onAppear { CameraManager.shared.start() }

            // Flash
            if flash {
                Color.white.opacity(0.6).ignoresSafeArea()
            }

            // Import from library button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Memori.Color.inkFaint)
                            .padding(14)
                            .background(Memori.Color.surfaceDark.opacity(0.7), in: Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 110)
                }
            }
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    let id = UUID()
                    currentCaptureID = id
                    capturedImage = image
                    capturedVideoURL = nil
                    let card = NoteCard(id: id, date: Date(), image: image)
                    mediaStore.saveSnippet(from: card)
                    showNoteOverlayFromOrb = true
                }
            }
        }
    }

    // MARK: - Globe View
    private var globeView: some View {
        UniverseCanvas()
            .environmentObject(mediaStore)
            .environmentObject(journalStore)
            .environmentObject(universeStore)
            .environmentObject(collageStore)
            .ignoresSafeArea()
    }

    // MARK: - Journal View
    private var journalView: some View {
        JournalScreen(
            date: $journalDate,
            store: journalStore,
            mediaStore: mediaStore,
            onOpenCalendar: { showCalendar = true },
            onOpenSnippet: { card in fullScreenNote = card }
        )
        .fullScreenCover(item: $fullScreenNote) { card in
            MediaFullScreen(card: card, onClose: { fullScreenNote = nil }, onChange: { _ in })
        }
        .ignoresSafeArea()
        .onChange(of: journalDate) { _, newValue in
            let today = Calendar.current.startOfDay(for: Date())
            if newValue > today { journalDate = today }
        }
    }

    // MARK: - Tab Bar
    private var bottomTabBar: some View {
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0

        return ZStack(alignment: .bottom) {
            // Bar background
            Rectangle()
                .fill(Memori.Color.pageBg.opacity(0.97))
                .frame(height: 54 + bottomInset)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Memori.Color.inkFaint.opacity(0.15))
                        .frame(height: 0.5)
                }

            HStack(alignment: .bottom) {
                // Globe
                tabButton(
                    icon: "globe",
                    label: "world",
                    isActive: section == .globe
                ) { section = .globe }

                Spacer()

                // Capture (center floating)
                captureTabButton
                    .offset(y: -(bottomInset > 0 ? 12 : 8))

                Spacer()

                // Journal
                tabButton(
                    icon: "book.closed",
                    label: "journal",
                    isActive: section == .journal
                ) { section = .journal }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, bottomInset + 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func tabButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? Memori.Color.accent : Memori.Color.inkMid)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var captureTabButton: some View {
        if section == .camera {
            CaptureOrb(
                onTakePhoto: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    CameraManager.shared.capturePhoto()
                },
                onStartVideo: {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    CameraManager.shared.startRecording()
                },
                onStopVideo: {
                    CameraManager.shared.stopRecording { url in
                        guard let url else { return }
                        capturedVideoURL = url
                        capturedImage = generateThumbnail(from: url)
                        let id = UUID()
                        currentCaptureID = id
                        let card = NoteCard(id: id, date: Date(), image: capturedImage, videoURL: url)
                        mediaStore.saveSnippet(from: card)
                        showNoteOverlayFromOrb = true
                    }
                },
                streak: journalStore.currentStreak
            )
            .frame(width: 52, height: 52)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                section = .camera
            } label: {
                ZStack {
                    Circle()
                        .fill(Memori.Color.accent)
                        .frame(width: 46, height: 46)
                        .overlay(
                            Circle()
                                .strokeBorder(Memori.Color.inkFaint.opacity(0.3), lineWidth: 1)
                        )
                    Image(systemName: "camera.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Memori.Color.inkLight)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
