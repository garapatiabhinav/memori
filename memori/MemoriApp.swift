// MemoriApp.swift
// Memori
// Created by Abhinav Garapati

import SwiftUI

@main
struct MemoriApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashScreen()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    showSplash = false
                                }
                            }
                        }
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
