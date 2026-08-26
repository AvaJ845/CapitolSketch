import Foundation

/// Every claim the app makes about itself, in one place so it can be audited as a set.
///
/// Two sentences are banned outright and must never reappear anywhere in the app:
/// "everything runs on your iPhone" and "kept fresh in the background". Both are false —
/// the app downloads a file over the network, and it only does so while it is open.
enum Copy {

    static let privateByDefault = """
        Private by default. No account, no sign-in, no ads, no analytics. Your holdings \
        list never leaves your phone. The app downloads one public file of House \
        disclosures — the same file for everyone.
        """

    static let historyNotHeadlines = """
        History, not headlines. The law gives members up to 45 days to disclose a trade. \
        Every entry here is already weeks old, and every entry shows exactly how old.
        """

    static let rangesOnly = """
        Ranges, because ranges are all there is. The form requires only a dollar \
        bracket — never an exact amount, never a share count.
        """

    static let oneAlert = """
        One alert worth having. Tell the app which tickers you own. If a member you \
        follow discloses a trade in one of them, you'll know.
        """

    static let updatedDaily = "Updated daily, and it always says when."

    static let noAdvice = """
        We'll tell you something happened. We'll never tell you what to do about it.
        """

    /// Shown wherever the 45-day window needs restating in a single line.
    static let lagBanner = """
        The law gives members up to 45 days to disclose. Every entry here is already \
        weeks old, and shows exactly how old.
        """

    // MARK: - Limitations, stated plainly rather than buried

    static let houseOnly = """
        House only. Senate disclosures live on a separate portal behind a session \
        cookie, and are not covered yet.
        """

    static let scannedPaper = """
        Some filings are photographs of paper forms with no readable text. Those \
        transactions are missing entirely, and the count is shown on this screen.
        """

    static let amountsAreRanges = """
        Amounts are the brackets the form requires, not exact values. Any total or \
        ranking built on them is an estimate, so this app does not build one.
        """

    static let datesAsFiled = """
        A few filings list a transaction date after their own filing date — almost \
        always a mistyped year. Those are shown exactly as filed and flagged, not \
        quietly corrected.
        """

    static let noPrices = """
        No prices and no performance. Computing a return from a weeks-old bracket \
        midpoint would be a made-up number presented as analysis.
        """
}
