// SnippetFullScreen.swift
// Memori
// Created by Abhinav Garapati

import SwiftUI
import AVKit

struct SnippetFullScreen: View {
    var card: NoteCard
    var onClose: () -> Void
    var onChange: (NoteCard) -> Void
    var onDelete: (UUID) -> Void

    @State private var noteText: String
    @State private var selectedColor: Color
    @State private var showMediaOnly = false
    @GestureState private var dragOffset: CGFloat = 0
    @State private var showDeleteAlert = false

    // Four paper tones the user can choose between
    private let paperColors: [(Color, String)] = [
        (Color(hex: "#F5EFE4"), "cream"),
        (Color(hex: "#E8F0E8"), "sage"),
        (Color(hex: "#F0E8F0"), "lavender"),
        (Color(hex: "#F5EBE0"), "peach"),
    ]

    init(card: NoteCard, onClose: @escaping () -> Void,
         onChange: @escaping (NoteCard) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.card = card; self.onClose = onClose
        self.onChange = onChange; self.onDelete = onDelete
        _noteText = State(initialValue: card.text)
        _selectedColor = State(initialValue: card.color)
    }

    var body: some View {
        ZStack {
            Memori.Color.pageBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Media
                Group {
                    if let img = card.image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.88)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Memori.Color.inkFaint.opacity(0.2), lineWidth: 0.5)
                            )
                            .padding(.top, 24)
                            .onTapGesture { showMediaOnly = true }
                    } else if let url = card.videoURL {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.88,
                                   maxHeight: UIScreen.main.bounds.width * 0.6)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.top, 24)
                    }
                }

                // Color picker + Note editor
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selectedColor)

                    VStack(alignment: .leading, spacing: 0) {
                        // Color swatch row
                        HStack(spacing: 10) {
                            ForEach(paperColors, id: \.1) { color, name in
                                let isActive = color.toHex() == selectedColor.toHex()
                                Circle()
                                    .fill(color)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                isActive ? Memori.Color.inkMid : Memori.Color.inkFaint.opacity(0.4),
                                                lineWidth: isActive ? 1.5 : 0.5
                                            )
                                    )
                                    .scaleEffect(isActive ? 1.15 : 1.0)
                                    .animation(.spring(response: 0.25), value: isActive)
                                    .onTapGesture {
                                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                        selectedColor = color
                                    }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                        // Thin divider
                        Rectangle()
                            .fill(Memori.Color.inkFaint.opacity(0.2))
                            .frame(height: 0.5)
                            .padding(.horizontal, 14)

                        ZStack(alignment: .topLeading) {
                            if noteText.isEmpty {
                                Text("add a note…")
                                    .font(Memori.Font.serif(14))
                                    .foregroundStyle(Memori.Color.inkFaint)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 14)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: $noteText)
                                .scrollContentBackground(.hidden)
                                .font(Memori.Font.serif(15))
                                .foregroundStyle(Memori.Color.inkDark)
                                .padding(10)
                                .background(.clear)
                        }
                    }
                }
                .frame(minHeight: 180)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()
            }
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        if value.translation.height > 0 { state = value.translation.height }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 { onClose() }
                    }
            )
            .animation(.spring(), value: dragOffset)
        }
        .fullScreenCover(isPresented: $showMediaOnly) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let img = card.image {
                    Image(uiImage: img).resizable().scaledToFit().ignoresSafeArea()
                } else if let url = card.videoURL {
                    VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
                }
            }
            .onTapGesture { showMediaOnly = false }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Memori.Color.inkMid)
                        .padding(8)
                        .background(Memori.Color.surfaceMid, in: Circle())
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Button { showDeleteAlert = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Memori.Color.inkMid)
                    }
                    Button {
                        var updated = card; updated.text = noteText; updated.color = selectedColor
                        onChange(updated); onClose()
                    } label: {
                        Text("save")
                            .font(Memori.Font.sans(13, weight: .medium))
                            .foregroundStyle(Memori.Color.inkLight)
                            .tracking(0.5)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 14)
                            .background(Memori.Color.accent, in: Capsule())
                    }
                }
            }
        }
        .alert("Delete this memory?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { onDelete(card.id); onClose() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the photo and its globe pin.")
        }
    }
}
