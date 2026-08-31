import SwiftUI
import Observation

/// The Home Screen icon the reader has chosen.
///
/// The alternates are declared by `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in
/// `project.yml` and shipped as Icon Composer `.icon` bundles alongside the primary. iOS
/// remembers the choice itself; this just mirrors it for the Settings UI and wraps the
/// swap in something a view can call.
@MainActor
@Observable
final class AppIconStore {

    enum Option: String, CaseIterable, Identifiable {
        case navy, paper, red

        var id: String { rawValue }

        /// `nil` is the primary icon; the others match an alternate's name.
        var alternateName: String? {
            switch self {
            case .navy: return nil
            case .paper: return "CapitolSketch-Paper"
            case .red: return "CapitolSketch-Red"
            }
        }

        var label: String {
            switch self {
            case .navy: return "Navy"
            case .paper: return "Paper"
            case .red: return "Civic Red"
            }
        }

        /// Swatch colours for the picker — background then the Capitol mark on top of it.
        var background: Color {
            switch self {
            case .navy: return Ink.navy
            case .paper: return Ink.paper
            case .red: return Color(red: 217 / 255, green: 45 / 255, blue: 58 / 255)
            }
        }

        var mark: Color {
            self == .paper ? Ink.navy : .white
        }

        /// The rendered icon art, bundled as a small PNG under Resources/IconPreviews.
        var preview: Image? {
            let file = alternateName ?? "CapitolSketch"
            guard let url = Bundle.main.url(forResource: file, withExtension: "png"),
                  let image = UIImage(contentsOfFile: url.path)
            else { return nil }
            return Image(uiImage: image)
        }
    }

    private(set) var current: Option
    private(set) var lastError: String?

    init() {
        let name = UIApplication.shared.alternateIconName
        current = Option.allCases.first { $0.alternateName == name } ?? .navy
    }

    var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    func select(_ option: Option) async {
        guard option != current else { return }
        guard UIApplication.shared.alternateIconName != option.alternateName else {
            current = option
            return
        }
        do {
            try await UIApplication.shared.setAlternateIconName(option.alternateName)
            current = option
            lastError = nil
        } catch {
            lastError = "Could not change the icon. \(error.localizedDescription)"
        }
    }
}
