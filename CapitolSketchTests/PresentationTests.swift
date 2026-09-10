import Foundation
import Testing
import DisclosureKit
@testable import CapitolSketch

/// The wording layer in `Models/Presentation.swift`: every string a reader sees is
/// defined once there, so these pin the ones that feed headers, VoiceOver, and the
/// disclosure-gap sentence.
@Suite("Presentation wording")
struct PresentationTests {

    @Test("monthOrdinal orders months across a year boundary")
    func monthOrdinalOrders() {
        let dec = CalendarDate("2025-12-31").monthOrdinal
        let jan = CalendarDate("2026-01-01").monthOrdinal
        let feb = CalendarDate("2026-02-15").monthOrdinal
        #expect(dec < jan)
        #expect(jan + 1 == feb)
    }

    @Test("monthOrdinal is stable within a calendar month")
    func monthOrdinalStableWithinMonth() {
        #expect(CalendarDate("2026-03-01").monthOrdinal == CalendarDate("2026-03-31").monthOrdinal)
    }

    @Test("monthLabel spells the month and keeps the year")
    func monthLabel() {
        #expect(CalendarDate("2026-07-04").monthLabel == "July 2026")
        #expect(CalendarDate("2026-01-01").monthLabel == "January 2026")
    }

    @Test("mediumLabel formats from calendar fields, no time zone shift")
    func mediumLabel() {
        #expect(CalendarDate("2026-07-24").mediumLabel == "Jul 24, 2026")
    }

    @Test("disclosureGapPhrase states the lag in words")
    func gapPhrase() {
        #expect(Build.trade(tx: CalendarDate("2026-06-01"), disclosed: CalendarDate("2026-06-01"))
            .disclosureGapPhrase == "disclosed the same day")
        #expect(Build.trade(tx: CalendarDate("2026-06-01"), disclosed: CalendarDate("2026-06-02"))
            .disclosureGapPhrase == "disclosed 1 day later")
        #expect(Build.trade(tx: CalendarDate("2026-06-01"), disclosed: CalendarDate("2026-07-01"))
            .disclosureGapPhrase == "disclosed 30 days later")
    }

    @Test("An impossible filing (traded after disclosed) is flagged, not silently corrected")
    func impossibleDate() {
        let t = Build.trade(tx: CalendarDate("2027-08-01"), disclosed: CalendarDate("2026-02-01"))
        #expect(t.hasImpossibleDate)
        #expect(t.disclosureGapPhrase == "filing dates are inconsistent")
        // Sorting falls back to the filing date so one typo cannot pin a row to the top.
        #expect(t.sortDate == CalendarDate("2026-02-01"))
    }

    @Test("cleanAssetName drops the trailing ticker/type bookkeeping")
    func cleanAssetName() {
        #expect(Build.trade(asset: "Acme Corp (ACME) [ST]").cleanAssetName == "Acme Corp")
        #expect(Build.trade(asset: "Broad Market Fund [MF]").cleanAssetName == "Broad Market Fund")
    }

    @Test("assetTypeName spells the House code, nil when there is none")
    func assetTypeName() {
        #expect(Build.trade(assetType: "OP").assetTypeName == "Option")
        #expect(Build.trade(assetType: nil).assetTypeName == nil)
        #expect(Build.trade(assetType: "ZZ").assetTypeName == nil)
    }

    @Test("A late filing is only late past 45 days and never when the dates are impossible")
    func lateFiling() {
        #expect(!Build.trade(tx: CalendarDate("2026-06-01"), disclosed: CalendarDate("2026-07-15")).isLateFiling)
        #expect(Build.trade(tx: CalendarDate("2026-06-01"), disclosed: CalendarDate("2026-08-01")).isLateFiling)
        #expect(!Build.trade(tx: CalendarDate("2027-01-01"), disclosed: CalendarDate("2026-01-01")).isLateFiling)
    }
}
