import Foundation

/// The app's self-description, for the strings that appear in more than one place or
/// need to be reviewed together. Screen-specific phrasing still lives in its view; this
/// is the shared set, kept here so the promises the app makes can be read at once.
///
/// Two sentences are banned outright and must never reappear anywhere in the app:
/// "everything runs on your iPhone" and "kept fresh in the background". Both are false —
/// the app downloads a file over the network, and it only does so while it is open.
enum Copy {

    static let historyNotHeadlines = """
        History, not headlines. The law gives members up to 45 days to disclose a trade. \
        Every entry here is already weeks old, and every entry shows exactly how old.
        """

    static let rangesOnly = """
        Ranges, because ranges are all there is. The form requires only a dollar \
        bracket — never an exact amount, never a share count.
        """

    static let noAdvice = """
        We'll tell you something happened. We'll never tell you what to do about it.
        """

    /// Short title + body for Settings, so the screen is scannable instead of a wall.
    struct Principle: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let body: String
    }

    static let principles: [Principle] = [
        Principle(
            id: "private",
            symbol: "lock.shield",
            title: "Private by default",
            body: "No account, no sign-in, no ads, no analytics. Your holdings list never leaves your phone. The app downloads one public file of House disclosures — the same file for everyone."
        ),
        Principle(
            id: "history",
            symbol: "clock.arrow.circlepath",
            title: "History, not headlines",
            body: "The law gives members up to 45 days to disclose a trade. Every entry here is already weeks old, and every entry shows exactly how old."
        ),
        Principle(
            id: "ranges",
            symbol: "arrow.left.and.right",
            title: "Ranges, because ranges are all there is",
            body: "The form requires only a dollar bracket — never an exact amount, never a share count."
        ),
        Principle(
            id: "alert",
            symbol: "bell.badge",
            title: "One alert worth having",
            body: "Tell the app which tickers you own. If a member you follow discloses a trade in one of them, you'll know."
        ),
        Principle(
            id: "updated",
            symbol: "calendar",
            title: "Updated daily",
            body: "And it always says when."
        ),
    ]

    /// Shown wherever the 45-day window needs restating in a single line.
    static let lagBanner = """
        The law gives members up to 45 days to disclose. Every entry here is already \
        weeks old, and shows exactly how old.
        """

    static let datesAsFiled = """
        A few filings list a transaction date after their own filing date — almost \
        always a mistyped year. Those are shown exactly as filed and flagged, not \
        quietly corrected.
        """
}
