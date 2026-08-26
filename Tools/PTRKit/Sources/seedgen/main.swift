import Foundation
import DisclosureKit
import PTRKit

// seedgen — bakes the app's bundled snapshot from primary-source House filings.
//
//   swift run seedgen --out ../../CapitolSketch/Resources/seed-filings.json
//
// Everything it reads is public domain: the Clerk's bulk filing index and the Periodic
// Transaction Report PDFs it links to. No API key and no third-party feed. It runs the
// same DisclosureKit parser the app runs on device, so the seed and later incremental
// refreshes cannot disagree.

struct Options {
    /// A rolling window. Defaulting to the current year alone produced a nearly empty
    /// feed every 1 January, because December trades are disclosed in January.
    var years: [Int] = FilingIndex.relevantYears()
    var out = URL(fileURLWithPath: "seed-filings.json")
    var cache = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ptrfetch-cache")
    var limit: Int?
    var concurrency = 6
    var pretty = false
    /// Ignore every cache — index, crosswalk and PDFs — and refetch.
    var force = false
}

func parseArgs() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--years": if let v = it.next() { o.years = v.split(separator: ",").compactMap { Int($0) } }
        case "--out": if let v = it.next() { o.out = URL(fileURLWithPath: v) }
        case "--cache": if let v = it.next() { o.cache = URL(fileURLWithPath: v) }
        case "--limit": if let v = it.next() { o.limit = Int(v) }
        case "--concurrency": if let v = it.next(), let n = Int(v) { o.concurrency = max(1, n) }
        case "--pretty": o.pretty = true
        case "--force": o.force = true
        case "--help", "-h":
            print("""
            seedgen — parse US House Periodic Transaction Reports into a seed snapshot

              --years 2025,2026   filing years (default: previous and current year)
              --out PATH          output JSON path
              --cache DIR         index, crosswalk and PDF cache directory
              --limit N           only the N most recent filings (for testing)
              --concurrency N     parallel PDF downloads (default 6)
              --force             ignore every cache and refetch
              --pretty            pretty-print the JSON
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("warning: ignoring unknown argument \(a)\n".utf8))
        }
    }
    return o
}

func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let opts = parseArgs()
try? FileManager.default.createDirectory(at: opts.cache, withIntermediateDirectories: true)

// 1. Bioguide directory, so members are keyed by a real identifier rather than by a
//    name-and-state string that merges two people who share both.
let (directory, directoryReport) = await LegislatorDirectory.load(
    cacheDirectory: opts.cache, force: opts.force
)
for failed in directoryReport.filesFailed {
    log("WARNING: crosswalk \(failed) unavailable")
}
if directory != nil {
    log("member directory: \(directoryReport.entries) seat-terms from "
        + directoryReport.filesLoaded.joined(separator: ", "))
} else {
    log("WARNING: no member directory. Every member will use a fallback ID.")
}

// 2. The Clerk's index per year, revalidated rather than trusted because it is cached.
var filings: [FilingIndexRow] = []
for year in opts.years {
    do {
        let rows = try await FilingIndex.fetch(year: year, cacheDirectory: opts.cache)
        let ptrs = rows.filter(\.isPeriodicTransactionReport)
        log("index \(year): \(rows.count) filings, \(ptrs.count) PTRs")
        filings.append(contentsOf: ptrs)
    } catch {
        log("index \(year): FAILED — \(error.localizedDescription)")
    }
}

guard !filings.isEmpty else {
    log("ERROR: no filings to process. Refusing to overwrite the seed with nothing.")
    exit(1)
}

filings.sort { ($0.filedOn ?? CalendarDate(year: 0, month: 1, day: 1))
    > ($1.filedOn ?? CalendarDate(year: 0, month: 1, day: 1)) }
if let n = opts.limit { filings = Array(filings.prefix(n)) }

log("processing \(filings.count) PTR filings, concurrency \(opts.concurrency)…")

// 3. Download and parse, using the same code path the app uses on device.
let fetcher = PTRFetcher(concurrency: opts.concurrency, cacheDirectory: opts.cache)
let output = await fetcher.run(filings: filings, directory: directory) { p in
    if p.completed % 200 == 0 || p.completed == p.total {
        log("  \(p.completed)/\(p.total) filings — \(p.tradesSoFar) rows")
    }
}

let deduped = deduplicate(output.trades).sorted {
    $0.sortDate == $1.sortDate ? $0.id > $1.id : $0.sortDate > $1.sortDate
}
log("de-duplicated \(output.trades.count) → \(deduped.count) rows")

// 4. Report what did not work, loudly. These used to be counted as failures and dropped.
var stats = output.stats
stats.tradesParsed = deduped.count
log("")
log("─── coverage ───")
log(stats.coverageNote)
if !stats.filingsFailedToFetch.isEmpty {
    log("DOWNLOAD FAILURES (\(stats.filingsFailedToFetch.count)): "
        + stats.filingsFailedToFetch.prefix(20).joined(separator: ", "))
}
if stats.filingsYieldingNoTrades.isEmpty {
    log("PARSER FAILURES: none — every filing with readable text produced rows.")
} else {
    log("PARSER FAILURES — readable text but no rows (\(stats.filingsYieldingNoTrades.count)):")
    for id in stats.filingsYieldingNoTrades.prefix(25) { log("   docID \(id)") }
}
let flagged = deduped.filter { !$0.warnings.isEmpty }
if flagged.isEmpty {
    log("ROW WARNINGS: none.")
} else {
    var counts: [String: Int] = [:]
    for t in flagged { for w in t.warnings { counts[w, default: 0] += 1 } }
    log("ROW WARNINGS (\(flagged.count) rows):")
    for (w, n) in counts.sorted(by: { $0.value > $1.value }) { log("   \(n)×  \(w)") }
}
let impossible = deduped.filter(\.hasImpossibleDate)
if !impossible.isEmpty {
    log("MISTYPED DATES ON THE FORM (\(impossible.count)): shown as filed, flagged in the UI.")
}
let unresolved = output.members.filter { $0.bioguideID == nil }
if !unresolved.isEmpty {
    log("NO BIOGUIDE ID (\(unresolved.count)): " + unresolved.map(\.name).joined(separator: ", "))
}
log("────────────────")
log("")

// 5. Write the seed. Built through FeedBuilder, which is the same code the app's
//    on-device refresh merges through, so the two cannot order or de-duplicate
//    the same filings differently.
var nameToMemberID: [String: String] = [:]
for m in output.members { nameToMemberID[m.name] = m.id }

let feed = FeedBuilder.make(
    trades: deduped,
    members: output.members,
    stats: stats,
    indexYears: opts.years,
    nameToMemberID: nameToMemberID
)

let (encoder, _) = TradeFeed.makeCoder()
if opts.pretty { encoder.outputFormatting.insert(.prettyPrinted) }
let data = try encoder.encode(feed)
try FileManager.default.createDirectory(
    at: opts.out.deletingLastPathComponent(), withIntermediateDirectories: true
)
try data.write(to: opts.out)

log("wrote \(feed.trades.count) rows from \(feed.members.count) members → \(opts.out.path)")
log("(\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
