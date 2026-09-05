import WidgetKit
import SwiftUI
import AppIntents
import DisclosureKit

/// One widget, Home Screen and Lock Screen. The timeline is the refresh: WidgetKit
/// calls the provider, which may hit the Clerk over URLSession. There is no
/// BGTaskScheduler and no Live Activity.
///
/// The widget is configurable (`DisclosureWidgetIntent`): the reader picks between the
/// latest filings, their watchlist & follows, or one pinned ticker. That choice only
/// selects which already-downloaded rows to show — the Clerk fetch is identical
/// whatever the configuration says.
@main
struct CapitolSketchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "LatestDisclosures",
            intent: DisclosureWidgetIntent.self,
            provider: Provider()
        ) { entry in
            DisclosureWidgetView(entry: entry)
                .containerBackground(Ink.canvas, for: .widget)
        }
        .configurationDisplayName("House disclosures")
        .description("Latest House stock-trade disclosures, hits on tickers you watch and members you follow, or one ticker.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct DisclosureEntry: TimelineEntry {
    let date: Date
    let trades: [Trade]
    let generatedAt: Date?
    let watchlistEmpty: Bool
}

struct Provider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> DisclosureEntry {
        DisclosureEntry(date: Date(), trades: [], generatedAt: nil, watchlistEmpty: true)
    }

    func snapshot(for configuration: DisclosureWidgetIntent, in context: Context) async -> DisclosureEntry {
        currentEntry(for: configuration)
    }

    func timeline(for configuration: DisclosureWidgetIntent, in context: Context) async -> Timeline<DisclosureEntry> {
        await refreshFromClerk()
        let entry = currentEntry(for: configuration)
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date())
            ?? Date().addingTimeInterval(6 * 3600)
        return Timeline(entries: [entry], policy: .after(next))
    }

    /// Builds the entry for a configuration. The watchlist / follow sets and the pinned
    /// ticker are read here purely to choose which already-downloaded rows to show;
    /// nothing in this path — or in `refreshFromClerk` — varies a request by them.
    private func currentEntry(for configuration: DisclosureWidgetIntent) -> DisclosureEntry {
        let feed = loadFeed()
        let defaults = SharedContainer.defaults
        let tickers = Set(
            (defaults.stringArray(forKey: SharedContainer.Key.tickers) ?? []).map { $0.uppercased() }
        )
        let followed = Set(
            defaults.stringArray(forKey: SharedContainer.Key.followedMembers) ?? []
        )

        let rows: [Trade]
        let watchlistEmpty: Bool
        switch configuration.mode {
        case .ticker:
            let symbol = SharedContainer.normalizedTicker(configuration.ticker ?? "")
            watchlistEmpty = symbol.isEmpty
            rows = symbol.isEmpty
                ? Array(feed.trades.prefix(5))
                : Array(feed.trades.filter { $0.ticker?.uppercased() == symbol }.prefix(5))
        case .watchlist:
            watchlistEmpty = tickers.isEmpty && followed.isEmpty
            rows = watchlistEmpty
                ? Array(feed.trades.prefix(5))
                : Array(feed.trades
                    .filter { $0.isWatchlistRelevant(watchedTickers: tickers, followedMembers: followed) }
                    .prefix(5))
        case .latest:
            watchlistEmpty = true
            rows = Array(feed.trades.prefix(5))
        }

        let generated = feed.generatedAt == .distantPast ? nil : feed.generatedAt
        return DisclosureEntry(
            date: Date(),
            trades: rows,
            generatedAt: generated,
            watchlistEmpty: watchlistEmpty
        )
    }

    private func loadFeed() -> TradeFeed {
        let urls = [SharedContainer.feedFile, SharedContainer.localFeedFile].compactMap { $0 }
        for url in urls {
            if let feed = decode(url), feed.schemaVersion == TradeFeed.currentSchemaVersion {
                return feed
            }
        }
        return .empty
    }

    private func decode(_ url: URL) -> TradeFeed? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let (_, decoder) = TradeFeed.makeCoder()
        return try? decoder.decode(TradeFeed.self, from: data)
    }

    /// Incremental Clerk fetch, capped so a widget timeline reload cannot become a
    /// full-year ingest. The request pattern does not depend on the watchlist.
    private func refreshFromClerk() async {
        let seed = loadFeed()
        let outcome = await IncrementalRefresher.refresh(
            seed: seed,
            maxDownloads: 4,
            concurrency: 2,
            cacheDirectory: SharedContainer.directory
        )
        // Liveness, tracked apart from data age: only a genuine good exchange with the
        // Clerk (200 / legitimate 304) bumps this — never an error or an offline run.
        if outcome.report.reachedClerk {
            SharedContainer.noteClerkContact()
        }
        guard let updated = outcome.feed else { return }
        let destination = SharedContainer.feedFile ?? SharedContainer.localFeedFile
        let (encoder, _) = TradeFeed.makeCoder()
        guard let data = try? encoder.encode(updated) else { return }
        try? data.write(to: destination, options: .atomic)
    }
}

struct DisclosureWidgetView: View {
    let entry: DisclosureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.widgetURL(Self.link(for: lead, watchlistEmpty: entry.watchlistEmpty))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            smallHome
        default:
            mediumHome
        }
    }

    private var lead: Trade? { entry.trades.first }

    /// Where a tap on the widget lands. A specific filing when there is one, otherwise
    /// the tab that matches what the widget is showing.
    static func link(for trade: Trade?, watchlistEmpty: Bool) -> URL {
        if let trade {
            return URL(string: "capitolsketch://filing/\(trade.id)")!
        }
        return URL(string: watchlistEmpty ? "capitolsketch://feed" : "capitolsketch://watchlist")!
    }

    private var inlineText: String {
        guard let trade = lead else { return "No House filings yet" }
        return "\(trade.memberName) · \(trade.txType.directionLabel) \(trade.displaySymbol)"
    }

    private var circular: some View {
        VStack(spacing: 1) {
            if let trade = lead {
                Text(trade.txType.arrowGlyph)
                    .font(.headline)
                Text(trade.displaySymbol)
                    .font(.caption.weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Image(systemName: "building.columns")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let trade = lead {
                Text("\(trade.txType.directionLabel) \(trade.displaySymbol)")
                    .font(.headline)
                    .lineLimit(1)
                Text(trade.memberName)
                    .font(.caption)
                    .lineLimit(1)
                Text(trade.amount.label)
                    .font(.caption2)
                    .lineLimit(1)
            } else {
                Text("No House filings yet")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var smallHome: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.watchlistEmpty ? "Latest filing" : "Watchlist")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let trade = lead {
                Text(trade.displaySymbol)
                    .font(.title2.weight(.bold).monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(trade.txType.directionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.accent)
                Text(trade.memberName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ageLine
        }
    }

    private var mediumHome: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.watchlistEmpty ? "Latest House filings" : "Watchlist hits")
                    .font(.caption.weight(.semibold))
                Spacer()
                ageLine
            }
            if entry.trades.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.trades.prefix(3)) { trade in
                    Link(destination: URL(string: "capitolsketch://filing/\(trade.id)")!) {
                        HStack(spacing: 6) {
                            Text(trade.txType.arrowGlyph)
                                .font(.caption.weight(.bold))
                                .frame(width: 12)
                            Text(trade.displaySymbol)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 52, alignment: .leading)
                                .lineLimit(1)
                            Text(trade.memberName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(trade.amount.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyMessage: String {
        if entry.watchlistEmpty {
            return "Open the app to load House filings."
        }
        return "No watched ticker has a disclosure yet."
    }

    @ViewBuilder
    private var ageLine: some View {
        if let generatedAt = entry.generatedAt {
            Text(generatedAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
