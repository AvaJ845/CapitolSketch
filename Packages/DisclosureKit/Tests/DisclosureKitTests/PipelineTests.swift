import Foundation
import Testing
@testable import DisclosureKit

@Suite("Calendar dates carry no time zone")
struct CalendarDateTests {

    @Test("A form date survives a round trip unchanged")
    func roundTrip() {
        let d = CalendarDate(formStyle: "07/24/2026")
        #expect(d?.iso == "2026-07-24")
        #expect(CalendarDate(iso: "2026-07-24") == d)
    }

    @Test("The rendered day does not shift with the device time zone")
    func timeZoneIndependence() {
        // Storing these as instants and formatting them elsewhere shifted every date a
        // day earlier for anyone west of Greenwich. Calendar fields cannot drift.
        let d = CalendarDate(iso: "2026-12-26")!
        for id in ["UTC", "America/Los_Angeles", "Pacific/Kiritimati", "Asia/Tokyo"] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: id)!
            let components = cal.dateComponents([.year, .month, .day], from: d.date(in: cal))
            #expect(components.day == 26, "day shifted in \(id)")
            #expect(components.month == 12)
        }
    }

    @Test("Ordering is chronological")
    func ordering() {
        #expect(CalendarDate(iso: "2025-12-31")! < CalendarDate(iso: "2026-01-01")!)
        #expect(CalendarDate(iso: "2026-02-09")! < CalendarDate(iso: "2026-12-26")!)
    }

    @Test("Day arithmetic matches the disclosure window")
    func dayMath() {
        let traded = CalendarDate(iso: "2026-07-01")!
        let filed = CalendarDate(iso: "2026-08-15")!
        #expect(traded.days(to: filed) == 45)
    }

    @Test("Nonsense dates are rejected rather than coerced")
    func rejectsGarbage() {
        #expect(CalendarDate(formStyle: "13/45/2026") == nil)
        #expect(CalendarDate(iso: "not-a-date") == nil)
        #expect(CalendarDate(formStyle: "") == nil)
    }
}

@Suite("Filing index")
struct FilingIndexTests {

    private static let sample = """
    Prefix\tLast\tFirst\tSuffix\tFilingType\tStateDst\tYear\tFilingDate\tDocID
    Hon.\tPelosi\tNancy\t\tP\tCA11\t2026\t8/21/2026\t20035143
    Hon.\tSmith\tJohn\t\tC\tTX31\t2026\t5/13/2026\t10078016
    Hon.\tCohen\tSteve\t\tP\tTN09\t2026\t2/9/2026\t20033889
    """

    @Test("Only periodic transaction reports are treated as trade filings")
    func filtersPTRs() {
        let rows = FilingIndex.parse(Self.sample, fallbackYear: 2026)
        #expect(rows.count == 3)
        #expect(rows.filter(\.isPeriodicTransactionReport).count == 2)
    }

    @Test("Rows expose the fields the pipeline needs")
    func fieldMapping() {
        let rows = FilingIndex.parse(Self.sample, fallbackYear: 2026)
        let pelosi = rows[0]
        #expect(pelosi.fullName == "Nancy Pelosi")
        #expect(pelosi.state == "CA")
        #expect(pelosi.district == "11")
        #expect(pelosi.filedOn?.iso == "2026-08-21")
        #expect(pelosi.docID == "20035143")
        #expect(pelosi.documentURL?.absoluteString.hasSuffix("2026/20035143.pdf") == true)
    }

    @Test("A byte-order mark and CRLF endings do not break parsing")
    func handlesBOMAndCRLF() {
        let raw = "\u{FEFF}" + Self.sample.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(FilingIndex.parse(raw, fallbackYear: 2026).count == 3)
    }

    @Test("The year window always includes the previous year")
    func yearWindowSurvivesNewYear() {
        // Defaulting to the current year alone produced a nearly empty feed every
        // 1 January, because December trades are disclosed the following month.
        let newYearsDay = CalendarDate(year: 2027, month: 1, day: 1)
        let years = FilingIndex.relevantYears(asOf: newYearsDay)
        #expect(years.contains(2026))
        #expect(years.contains(2027))

        let midYear = CalendarDate(year: 2026, month: 8, day: 25)
        #expect(FilingIndex.relevantYears(asOf: midYear) == [2025, 2026])
    }

    @Test("The index is fetched from the plain text file, needing no archive reader")
    func usesPlainTextEndpoint() {
        // The Clerk serves the same content as .txt and .zip. Using .txt means no ZIP
        // reader and no Process, so identical code runs on macOS and iOS.
        let url = FilingIndex.textURL(year: 2026).absoluteString
        #expect(url.hasSuffix("2026FD.txt"))
        #expect(!url.contains(".zip"))
    }
}

@Suite("Member identity")
struct MemberDirectoryTests {

    private static let directory = MemberDirectory(entries: [
        .init(bioguideID: "P000197", last: "Pelosi", first: "Nancy",
              state: "CA", district: "11", chamber: .house),
        .init(bioguideID: "A000001", last: "Rivera", first: "Ana",
              state: "TX", district: "7", chamber: .house),
        .init(bioguideID: "B000002", last: "Rivera", first: "Ben",
              state: "TX", district: "9", chamber: .house),
    ])

    @Test("A member resolves to a Bioguide ID")
    func resolvesBioguide() {
        #expect(Self.directory.resolve(last: "Pelosi", first: "Nancy", state: "CA")
                == .resolved("P000197"))
    }

    @Test("Two people sharing a surname and state are never merged")
    func doesNotMergeNamesakes() {
        // The old key was last-first-state, which collapsed distinct humans into one
        // identifier and silently pooled their trades.
        let ana = Self.directory.resolve(last: "Rivera", first: "Ana", state: "TX")
        let ben = Self.directory.resolve(last: "Rivera", first: "Ben", state: "TX")
        #expect(ana == .resolved("A000001"))
        #expect(ben == .resolved("B000002"))
        #expect(ana != ben)

        // With only a surname the answer is ambiguity, not a guess.
        let surnameOnly = Self.directory.resolve(last: "Rivera", first: "", state: "TX")
        guard case .ambiguous(let ids) = surnameOnly else {
            Issue.record("expected ambiguity, got \(surnameOnly)")
            return
        }
        #expect(Set(ids) == ["A000001", "B000002"])
    }

    @Test("An unknown filer gets a fallback ID that cannot pass for a Bioguide ID")
    func fallbackIsDistinguishable() {
        #expect(Self.directory.resolve(last: "Nobody", first: "Nemo", state: "ZZ") == .notFound)
        let fallback = MemberDirectory.fallbackID(
            last: "Nobody", first: "Nemo", state: "ZZ", district: "1"
        )
        #expect(fallback.hasPrefix("x-"))
        #expect(!MemberDirectory.isBioguideID(fallback))
        #expect(MemberDirectory.isBioguideID("P000197"))
    }

    @Test("Diacritics and punctuation do not prevent a match")
    func normalisesNames() {
        let d = MemberDirectory(entries: [
            .init(bioguideID: "C000003", last: "Núñez", first: "José",
                  state: "NM", district: "2", chamber: .house)
        ])
        #expect(d.resolve(last: "Nunez", first: "Jose", state: "NM") == .resolved("C000003"))
    }

    @Test("A compound surname resolves whichever side the sources split it on")
    func compoundSurname() {
        // The Clerk files April McClain Delaney as first "April McClain", last "Delaney".
        // The crosswalk records first "April", last "McClain Delaney". Neither the
        // forename key nor the surname key matches, so joining them is the only tier
        // that can see these are one person. This was the single unmatched filer.
        let d = MemberDirectory(entries: [
            .init(bioguideID: "M001208", last: "McClain Delaney", first: "April",
                  state: "MD", district: "6", chamber: .house)
        ])
        #expect(d.resolve(last: "Delaney", first: "April McClain", state: "MD")
                == .resolved("M001208"))
    }

    @Test("A filed forename that differs from the legal one still resolves")
    func nicknameResolves() {
        // The Clerk prints "James D Jordan"; the crosswalk says "Jim".
        let d = MemberDirectory(entries: [
            .init(bioguideID: "J000289", last: "Jordan", first: "Jim",
                  state: "OH", district: "4", chamber: .house, nickname: "James")
        ])
        #expect(d.resolve(last: "Jordan", first: "James D", state: "OH", district: "04")
                == .resolved("J000289"))
    }

    @Test("The seat number separates a filer from their historical namesakes")
    func seatSeparatesNamesakes() {
        // Loading the historical crosswalk alongside the current one means a surname in
        // a state can name several people across decades. Without the seat that reads as
        // ambiguous and the filer loses their Bioguide ID.
        let d = MemberDirectory(entries: [
            .init(bioguideID: "B001304", last: "Begich", first: "Nick",
                  state: "AK", district: "0", chamber: .house),
            .init(bioguideID: "B001265", last: "Begich", first: "Mark",
                  state: "AK", district: nil, chamber: .senate),
        ])
        #expect(d.resolve(last: "Begich", first: "Nicholas", state: "AK", district: "00")
                == .resolved("B001304"))

        // Without a seat to go on it must still refuse to guess.
        guard case .ambiguous = d.resolve(last: "Begich", first: "", state: "AK") else {
            Issue.record("expected ambiguity when nothing distinguishes the two")
            return
        }
    }

    @Test("One member indexed under several terms is not mistaken for several people")
    func multipleTermsAreOnePerson() {
        let d = MemberDirectory(entries: [
            .init(bioguideID: "P000197", last: "Pelosi", first: "Nancy",
                  state: "CA", district: "8", chamber: .house),
            .init(bioguideID: "P000197", last: "Pelosi", first: "Nancy",
                  state: "CA", district: "11", chamber: .house),
        ])
        #expect(d.resolve(last: "Pelosi", first: "Nancy", state: "CA") == .resolved("P000197"))
    }
}

@Suite("Feed assembly")
struct FeedTests {

    private func trade(
        ticker: String, type: String, txType: TradeType = .buy, owner: TradeOwner = .self
    ) -> Trade {
        Trade(
            id: "t-\(ticker)-\(type)", memberID: "P000197", memberName: "Nancy Pelosi",
            owner: owner, asset: "\(ticker) [\(type)]", ticker: ticker, assetType: type,
            txType: txType, txDate: CalendarDate(iso: "2026-07-24")!,
            disclosedDate: CalendarDate(iso: "2026-08-21")!,
            amount: DisclosedAmount(kind: .range, lowCents: 100_100, highCents: 1_500_000,
                                    label: "$1,001 – $15,000"),
            filingDescription: nil, filingID: "20035143", documentURL: nil
        )
    }

    @Test("De-duplication keeps the stock and option legs apart")
    func dedupKeepsAssetTypes() {
        let rows = [trade(ticker: "BE", type: "ST"), trade(ticker: "BE", type: "OP")]
        #expect(deduplicate(rows).count == 2)
    }

    @Test("De-duplication removes a restated row from an amended filing")
    func dedupRemovesRestatements() {
        let rows = [trade(ticker: "BE", type: "ST"), trade(ticker: "BE", type: "ST")]
        #expect(deduplicate(rows).count == 1)
    }

    @Test("Coverage stats separate scanned filings from parser failures")
    func statsDistinguishFailureModes() {
        // Counting both as "failed" and dropping them is how the old pipeline hid a
        // real parser regression behind an expected scanning gap.
        let stats = ParseStats(
            filingsProcessed: 100, tradesParsed: 900,
            filingsYieldingNoTrades: ["111"], filingsWithoutText: ["222", "333"],
            filingsFailedToFetch: []
        )
        #expect(stats.filingsYieldingNoTrades.count == 1)
        #expect(stats.filingsWithoutText.count == 2)
        #expect(stats.coverageNote.contains("2 were scanned paper"))
    }

    @Test("A feed round-trips through its coder")
    func feedRoundTrip() throws {
        let feed = TradeFeed(
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            indexYears: [2025, 2026], source: "test",
            members: [Member(id: "P000197", bioguideID: "P000197", name: "Nancy Pelosi",
                             state: "CA", district: "11", chamber: .house)],
            trades: [trade(ticker: "BE", type: "ST")],
            stats: ParseStats(filingsProcessed: 1, tradesParsed: 1)
        )
        let (encoder, decoder) = TradeFeed.makeCoder()
        let restored = try decoder.decode(TradeFeed.self, from: encoder.encode(feed))
        #expect(restored.trades.count == 1)
        #expect(restored.trades[0].txDate.iso == "2026-07-24")
        #expect(restored.trades[0].amount.label == "$1,001 – $15,000")
        #expect(restored.chambersCovered == [.house])
        #expect(restored.schemaVersion == TradeFeed.currentSchemaVersion)
    }

    @Test("The disclosure gap reads as a sentence")
    func gapPhrasing() {
        let t = trade(ticker: "BE", type: "ST")
        #expect(t.disclosureLagDays == 28)
        #expect(t.disclosureGapPhrase == "disclosed 28 days later")
    }
}
