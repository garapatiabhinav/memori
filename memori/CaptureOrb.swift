// CaptureOrb.swift
// Memori
// Created by Abhinav Garapati

import SwiftUI

struct CaptureOrb: View {
    var onTakePhoto: () -> Void
    var onStartVideo: () -> Void
    var onStopVideo: () -> Void
    var streak: Int

    @State private var isRecording = false
    @State private var recordingProgress: CGFloat = 0
    @State private var timer: Timer?
    @GestureState private var isPressing = false

    private let maxRecordSeconds: CGFloat = 15

    var body: some View {
        ZStack {
            // Outer ring — recording progress
            Circle()
                .trim(from: 0, to: isRecording ? recordingProgress : 0)
                .stroke(Memori.Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 72, height: 72)
                .animation(.linear(duration: 0.1), value: recordingProgress)

            // Core button
            Circle()
                .fill(isRecording ? Color(hex: "#7A3F22") : Memori.Color.accent)
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .strokeBorder(Memori.Color.inkFaint.opacity(0.4), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Memori.Color.inkLight)
                                .frame(width: 16, height: 16)
                        } else {
                            Circle()
                                .fill(Memori.Color.inkLight)
                                .frame(width: 20, height: 20)
                        }
                    }
                )
                .scaleEffect(isRecording ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)

            // Streak badge
            if streak > 1 {
                Text("\(streak)")
                    .font(Memori.Font.sans(9, weight: .medium))
                    .foregroundStyle(Memori.Color.inkLight)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Memori.Color.accentMuted, in: Capsule())
                    .overlay(Capsule().strokeBorder(Memori.Color.accent.opacity(0.6), lineWidth: 0.5))
                    .offset(x: 22, y: -22)
            }
        }
        .frame(width: 72, height: 72)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    startRecording()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    if isRecording {
                        stopRecording()
                    } else {
                        onTakePhoto()
                    }
                }
        )
    }

    private func startRecording() {
        isRecording = true
        recordingProgress = 0
        onStartVideo()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingProgress += 0.1 / maxRecordSeconds
            if recordingProgress >= 1.0 { stopRecording() }
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        recordingProgress = 0
        onStopVideo()
    }
}
