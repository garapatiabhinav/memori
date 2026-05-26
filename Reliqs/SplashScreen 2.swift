// SplashScreen.swift
// Memori
// Created by Abhinav Garapati

import SwiftUI
import AVFoundation

struct SplashScreen: View {
    @State private var ringScale: CGFloat  = 0.6
    @State private var ringOpacity: Double = 0
    @State private var wordScale: CGFloat  = 0.88
    @State private var wordOpacity: Double = 0
    @State private var tagOpacity: Double  = 0
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            Memori.Color.splashBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo mark — two concentric rings + terracotta core
                ZStack {
                    Circle()
                        .strokeBorder(Memori.Color.inkFaint, lineWidth: 1)
                        .frame(width: 96, height: 96)

                    Circle()
                        .strokeBorder(Memori.Color.inkFaint.opacity(0.5), lineWidth: 0.5)
                        .frame(width: 72, height: 72)

                    Circle()
                        .fill(Memori.Color.accent)
                        .frame(width: 40, height: 40)

                    Circle()
                        .fill(Memori.Color.splashBg)
                        .frame(width: 18, height: 18)

                    Circle()
                        .strokeBorder(Memori.Color.inkFaint, lineWidth: 1)
                        .frame(width: 18, height: 18)
                }
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

                Spacer().frame(height: 28)

                // Wordmark
                Text("Reliqs")
                    .font(Memori.Font.serif(30))
                    .foregroundStyle(Memori.Color.inkDark)
                    .tracking(4)
                    .scaleEffect(wordScale)
                    .opacity(wordOpacity)

                Spacer().frame(height: 10)

                // Tagline
                Text("Your Visual Journal")
                    .font(Memori.Font.sans(11))
                    .foregroundStyle(Memori.Color.inkMid)
                    .tracking(2)
                    .textCase(.lowercase)
                    .opacity(tagOpacity)

                Spacer()

                // Three dots at bottom
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i == 0 ? Memori.Color.accent : Memori.Color.inkFaint)
                            .frame(width: 5, height: 5)
                    }
                }
                .opacity(wordOpacity)
                .padding(.bottom, 44)
            }
        }
        .onAppear {
            playChord()
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.05)) {
                ringScale   = 1.0
                ringOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.55).delay(0.3)) {
                wordScale   = 1.0
                wordOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.55)) {
                tagOpacity = 1.0
            }
        }
    }

    private func playChord() {
        guard let url = Bundle.main.url(forResource: "Dmajor", withExtension: "wav") else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }
}
