import SwiftUI
import Observation

/// Explicit Light / Dark / System control.
///
/// Following the system is the default, but it is not always the right answer: readers
/// who keep their phone in Dark and want a dense table in Light, or the reverse, have no
/// other way to ask. The stored value is the raw string, so a future option can be added
/// without migrating anything.
@MainActor
@Observable
final class AppearanceStore {

    enum Preference: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        /// Nil hands the decision back to the system.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    /// Neutral key so a product rename does not force a migration.
    private static let key = SharedContainer.Key.appearance

    private let defaults: UserDefaults

    var preference: Preference {
        didSet { defaults.set(preference.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.key) ?? ""
        preference = Preference(rawValue: raw) ?? .system
    }

    var colorScheme: ColorScheme? { preference.colorScheme }
}
