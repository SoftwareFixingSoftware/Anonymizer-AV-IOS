// HeuristicsManager.swift
// Single source-of-truth for heuristic scanning (MainActor).
// Uses a file-level constant for the defaults key so nonisolated accessors
// can read the flag without actor-isolation warnings.

import Foundation
import Combine

// File-level constant used by both isolated and nonisolated code.
// Using a file/global constant avoids actor-isolation issues.
fileprivate let HeuristicsDefaultsKey = "heuristicScanEnabled"

@MainActor
final class HeuristicsManager: ObservableObject {
    static let shared = HeuristicsManager()

    private init() {
        let stored = UserDefaults.standard.object(forKey: HeuristicsDefaultsKey) as? Bool
        self.isEnabled = stored ?? false
    }

    /// Published property for SwiftUI consumers. External mutation should use `setEnabled(_:)`.
    @Published public private(set) var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: HeuristicsDefaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil, userInfo: ["isEnabled": isEnabled])
        }
    }

    /// Combine publisher for non-SwiftUI consumers.
    var publisher: AnyPublisher<Bool, Never> {
        $isEnabled.eraseToAnyPublisher()
    }

    /// Notification name for legacy observers.
    static let didChangeNotification = Notification.Name("HeuristicsManager.didChange")

    // MARK: - Mutating API (main actor)
    /// Set enabled/disabled from SwiftUI or other main-actor contexts.
    @MainActor
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }

    /// Toggle the flag (main actor).
    @MainActor
    func toggle() {
        self.isEnabled.toggle()
    }

    // MARK: - Nonisolated synchronous helper
    /// Synchronous accessor usable from background threads / non-async contexts.
    /// Reads UserDefaults directly and therefore does not require jumping to the main actor.
    nonisolated func isEnabledSync() -> Bool {
        return UserDefaults.standard.object(forKey: HeuristicsDefaultsKey) as? Bool ?? false
    }
}
