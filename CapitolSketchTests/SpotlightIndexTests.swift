import Foundation
import Testing
import CoreSpotlight
@testable import CapitolSketch

/// `SpotlightIndex.route` turns the continuation activity from a Spotlight tap back into
/// an in-app destination. A crafted or unrelated activity must resolve to nothing.
@Suite("Spotlight routing")
struct SpotlightIndexTests {

    private func activity(id: String?, type: String = CSSearchableItemActionType) -> NSUserActivity {
        let a = NSUserActivity(activityType: type)
        if let id { a.userInfo = [CSSearchableItemActivityIdentifier: id] }
        return a
    }

    @Test("A member identifier routes to that member")
    func member() {
        #expect(SpotlightIndex.route(for: activity(id: "member:M000123")) == .member(id: "M000123"))
    }

    @Test("A ticker identifier routes to that symbol")
    func ticker() {
        #expect(SpotlightIndex.route(for: activity(id: "ticker:NVDA")) == .ticker("NVDA"))
    }

    @Test("An unknown prefix routes nowhere")
    func unknownPrefix() {
        #expect(SpotlightIndex.route(for: activity(id: "filing:20035143")) == nil)
        #expect(SpotlightIndex.route(for: activity(id: "member:")) == nil)
        #expect(SpotlightIndex.route(for: activity(id: "ticker:")) == nil)
    }

    @Test("A non-Spotlight activity routes nowhere")
    func wrongActivityType() {
        #expect(SpotlightIndex.route(for: activity(id: "member:M1", type: "com.example.other")) == nil)
        #expect(SpotlightIndex.route(for: activity(id: nil)) == nil)
    }
}
