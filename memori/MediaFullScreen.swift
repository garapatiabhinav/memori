//
//  MediaFullScreen.swift
//  Memori
//
//  Created by Abhinav Garapati on 07/12/25.
//


//
//  MediaFullScreen.swift
//  Memori
//
//  Created by Abhinav Garapati on 30/08/25.
//
//MediaFullScreen

import SwiftUI
import AVKit

struct MediaFullScreen: View {
    var card: NoteCard
    var onClose: () -> Void
    var onChange: (NoteCard) -> Void

    @State private var player: AVPlayer?
    @State private var oneLine: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if let url = card.videoURL {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        let p = AVPlayer(url: url)
                        player = p
                        p.actionAtItemEnd = .none
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: p.currentItem,
                            queue: .main
                        ) { _ in
                            p.seek(to: .zero)
                            p.play()
                        }
                        p.play()
                    }
            } else if let img = card.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .background(Color.black)
                    .ignoresSafeArea()
            }
            //else {
              //  Color.black.ignoresSafeArea()
            //}


            VStack {
                Spacer()
                HStack(spacing: 8) {
                    TextField("Add a quick note…", text: $oneLine)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)
                        .onSubmit { saveAndClose() }

                    Button { saveAndClose() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
            }
        }
        .onAppear { oneLine = card.text }
    }

    private func saveAndClose() {
        var up = card; up.text = oneLine
        onChange(up); onClose(); dismiss()
    }
}
