// MemoriTheme.swift
// Memori
// Central design tokens. Import this file; never hard-code colours elsewhere.

import SwiftUI

enum Memori {

    // MARK: - Palette
    enum Color {
        // Backgrounds
        static let pageBg       = SwiftUI.Color(hex: "#1C1510")   // deep warm black
        static let surfaceDark  = SwiftUI.Color(hex: "#241A12")   // lifted dark surface
        static let surfaceMid   = SwiftUI.Color(hex: "#2E2118")   // card on dark
        static let paperBg      = SwiftUI.Color(hex: "#F5EFE4")   // cream paper
        static let paperAlt     = SwiftUI.Color(hex: "#EDE4D3")   // slightly darker cream
        static let splashBg     = SwiftUI.Color(hex: "#F5EFE4")   // same as paperBg

        // Ink
        static let inkDark      = SwiftUI.Color(hex: "#2C231A")   // main body text on paper
        static let inkMid       = SwiftUI.Color(hex: "#8C7B68")   // muted text on paper / on dark
        static let inkLight     = SwiftUI.Color(hex: "#F5EFE4")   // text on dark backgrounds
        static let inkFaint     = SwiftUI.Color(hex: "#C4B99A")   // placeholder, grid lines

        // Accent
        static let accent       = SwiftUI.Color(hex: "#A0714F")   // terracotta — primary CTA
        static let accentLight  = SwiftUI.Color(hex: "#D4A882")   // lighter terracotta
        static let accentMuted  = SwiftUI.Color(hex: "#3D2518")   // dark terracotta tint

        // Semantic / globe
        static let globeBg      = SwiftUI.Color(hex: "#120E09")
        static let globeGrid    = SwiftUI.Color(hex: "#C4B99A").opacity(0.14)
        static let globeBorder  = SwiftUI.Color(hex: "#C4B99A").opacity(0.22)
    }

    // MARK: - Typography
    enum Font {
        /// Serif for dates, wordmarks, journal body
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .custom("Georgia", size: size).weight(weight)
        }
        /// System sans for UI chrome
        static func sans(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }

    // MARK: - Mood tags (new feature)
    static let moodTags: [String] = ["calm", "happy", "focused", "tired", "grateful", "anxious", "excited", "reflective"]

    // MARK: - Journal prompts (shown as placeholder when page is blank)
    static let journalPrompts: [String] = [
        "What made today feel different?",
        "What are you grateful for today?",
        "Describe one moment you want to remember.",
        "What did you notice today that you usually overlook?",
        "How does your body feel right now?",
        "What would make tomorrow better?",
        "One word for today:",
    ]
}

// MARK: - Colour hex initialiser
extension SwiftUI.Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >>  8) & 0xFF) / 255
        let b = Double( rgb        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
