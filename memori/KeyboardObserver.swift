//
//  KeyboardObserver.swift
//  Memori
//
//  Created by Abhinav Garapati on 12/12/25.
//


import SwiftUI
import Combine

final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    @Published var animationDuration: TimeInterval = 0.25
    // optional: expose the keyboard's animation curve as an Int if you want to map it later
    @Published var animationCurve: Int = 0

    private var center = NotificationCenter.default

    init() {
        center.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let screenHeight = UIScreen.main.bounds.height
        let newHeight = max(0, screenHeight - endFrame.origin.y)

        // Grab animation info
        if let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval {
            DispatchQueue.main.async {
                self.animationDuration = duration
            }
        }
        if let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int {
            DispatchQueue.main.async {
                self.animationCurve = curve
            }
        }

        // Publish height on main thread
        DispatchQueue.main.async {
            self.height = newHeight
        }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        DispatchQueue.main.async {
            self.height = 0
        }
    }

    deinit {
        center.removeObserver(self)
    }
}
