import AppIntents

// The configurable-widget intent. This is the only App Intents type both the app and the
// widget extension need to see, so it is the only one in `Shared/` — the App Shortcuts
// and their watchlist intents live in the app target (`CapitolSketch/App/AppShortcuts`).
//
// On-device only: no field of the widget configuration causes a network request or
// leaves the phone. `.ticker` is matched locally against data every reader already has.

enum DisclosureWidgetMode: String, AppEnum {
    case latest
    case watchlist
    case ticker

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget content"
    static let caseDisplayRepresentations: [DisclosureWidgetMode: DisplayRepresentation] = [
        .latest: "Latest filings",
        .watchlist: "My watchlist & follows",
        .ticker: "A specific ticker",
    ]
}

struct DisclosureWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Disclosures"
    static let description = IntentDescription("Choose what this widget shows.")

    @Parameter(title: "Show", default: .latest)
    var mode: DisclosureWidgetMode

    @Parameter(title: "Ticker", requestValueDialog: "Which ticker symbol?")
    var ticker: String?
}
