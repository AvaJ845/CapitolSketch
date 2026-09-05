import Foundation

/// Resolves a filer to a stable Bioguide ID.
///
/// The Clerk index carries no member identifier, only a printed name and a seat. Keying
/// on `last-first-state` merges two people who share a name and a state, and has no
/// concept of a district changing between terms. The Bioguide ID is the identifier the
/// rest of the civic-data world uses, so it is resolved once at build time and baked
/// into the feed alongside a name lookup the app reuses for on-device parsing.
public struct MemberDirectory: Sendable {

    public struct Entry: Codable, Hashable, Sendable {
        public let bioguideID: String
        public let last: String
        public let first: String
        public let state: String
        public let district: String?
        public let chamber: Chamber
        /// The name the member is actually known by, when it differs from the legal
        /// first name: the Clerk files "James D Jordan", the crosswalk says "Jim".
        public let nickname: String?

        public init(
            bioguideID: String, last: String, first: String, state: String,
            district: String?, chamber: Chamber, nickname: String? = nil
        ) {
            self.bioguideID = bioguideID
            self.last = last
            self.first = first
            self.state = state
            self.district = district
            self.chamber = chamber
            self.nickname = nickname
        }
    }

    private var byNameState: [String: [Entry]] = [:]
    private var byLastState: [String: [Entry]] = [:]
    /// Keyed on the forename and surname run together, so a compound surname matches
    /// regardless of where the two sources decided to split it.
    private var byJoinedNameState: [String: [Entry]] = [:]
    public private(set) var entries: [Entry] = []

    public init(entries: [Entry]) {
        self.entries = entries
        for e in entries {
            byNameState[Self.key(last: e.last, first: e.first, state: e.state), default: []].append(e)
            byLastState[Self.key(last: e.last, state: e.state), default: []].append(e)
            byJoinedNameState[Self.joinedKey(last: e.last, first: e.first, state: e.state), default: []]
                .append(e)
            if let nick = e.nickname, !nick.isEmpty {
                byNameState[Self.key(last: e.last, first: nick, state: e.state), default: []].append(e)
                byJoinedNameState[Self.joinedKey(last: e.last, first: nick, state: e.state), default: []]
                    .append(e)
            }
        }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: #"[^a-z ]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func key(last: String, first: String, state: String) -> String {
        "\(normalize(last))|\(normalize(first).components(separatedBy: " ").first ?? "")|\(state.uppercased())"
    }

    private static func key(last: String, state: String) -> String {
        "\(normalize(last))|\(state.uppercased())"
    }

    /// All letters of the forename and surname with the boundary removed. "April McClain"
    /// + "Delaney" and "April" + "McClain Delaney" both collapse to `aprilmcclaindelaney`.
    private static func joinedKey(last: String, first: String, state: String) -> String {
        let letters = normalize(first + last).replacingOccurrences(of: " ", with: "")
        return "\(letters)|\(state.uppercased())"
    }

    /// The seat number, as an integer. The Clerk zero-pads and writes at-large as `00`.
    private static func districtNumber(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    /// Returns a Bioguide ID when exactly one member matches.
    ///
    /// Ambiguity is reported rather than guessed: two people who genuinely share a
    /// surname and a state must not be silently merged, which is the bug this replaces.
    ///
    /// The tiers run from most to least specific, and each only ever answers when it
    /// narrows to exactly one person. Passing the seat number lets the middle tiers
    /// separate namesakes in the same delegation, which is otherwise unresolvable —
    /// including the case where the crosswalk lists every historical holder of a
    /// surname in a state and the surname alone therefore looks ambiguous.
    public func resolve(
        last: String, first: String, state: String, district: String? = nil
    ) -> Resolution {
        let seat = Self.districtNumber(district)

        // 1. Forename and surname as filed, or a known nickname for the forename.
        let exact = byNameState[Self.key(last: last, first: first, state: state)] ?? []
        if let only = Self.narrow(exact, toSeat: seat) { return .resolved(only.bioguideID) }
        if exact.count > 1 { return .ambiguous(Self.ids(exact)) }

        // 2. Surname and state, narrowed by forename and then by seat.
        let surname = byLastState[Self.key(last: last, state: state)] ?? []
        if let only = Self.narrow(surname, toSeat: seat) { return .resolved(only.bioguideID) }
        if surname.count > 1, !Self.normalize(first).isEmpty {
            let sameForename = surname.filter {
                Self.normalize($0.first).hasPrefix(Self.normalize(first))
                    || Self.normalize(first).hasPrefix(Self.normalize($0.first))
                    || Self.normalize($0.nickname ?? "") == Self.normalize(first)
            }
            if let only = Self.narrow(sameForename, toSeat: seat) { return .resolved(only.bioguideID) }
        }

        // 3. The two sources disagree about where a compound surname splits. The Clerk
        //    files April McClain Delaney as first "April McClain" / last "Delaney"; the
        //    crosswalk records first "April" / last "McClain Delaney". Running the names
        //    together removes the boundary they disagree about.
        let joined = byJoinedNameState[Self.joinedKey(last: last, first: first, state: state)] ?? []
        if let only = Self.narrow(joined, toSeat: seat) { return .resolved(only.bioguideID) }

        if !surname.isEmpty { return .ambiguous(Self.ids(surname)) }
        return .notFound
    }

    /// Resolves a filer by name within one chamber, for sources that give a name but no
    /// state — the Senate eFD search being the case this exists for. With 100 senators
    /// national surname+forename collisions are rare (the Scotts differ by forename), so
    /// this answers whenever the chamber narrows to exactly one person and reports
    /// ambiguity otherwise rather than guessing.
    ///
    /// Senate-only: the sole caller is `SenateFetcher`, so it is compiled only where
    /// SEEDGEN is defined (`seedgen` and the DisclosureKit test target). See P0-2.
    #if SEEDGEN
    public func resolve(last: String, first: String, chamber: Chamber) -> Resolution {
        let nLast = Self.normalize(last)
        let nFirst = Self.normalize(first).components(separatedBy: " ").first ?? ""

        let bySurname = entries.filter {
            $0.chamber == chamber && Self.normalize($0.last) == nLast
        }
        if let only = Self.sameHuman(bySurname) { return .resolved(only.bioguideID) }

        guard !nFirst.isEmpty else {
            return bySurname.isEmpty ? .notFound : .ambiguous(Self.ids(bySurname))
        }
        let byForename = bySurname.filter {
            let f = Self.normalize($0.first)
            let nick = Self.normalize($0.nickname ?? "")
            return f.hasPrefix(nFirst) || nFirst.hasPrefix(f) || nick == nFirst
        }
        if let only = Self.sameHuman(byForename) { return .resolved(only.bioguideID) }
        if byForename.count > 1 { return .ambiguous(Self.ids(byForename)) }
        return bySurname.isEmpty ? .notFound : .ambiguous(Self.ids(bySurname))
    }
    #endif // SEEDGEN

    /// The single person these candidates describe, if there is one. A group that is all
    /// the same human — the same member indexed under several terms — counts as one.
    /// When several people remain, the seat number is the only honest tiebreak.
    private static func narrow(_ candidates: [Entry], toSeat seat: Int?) -> Entry? {
        if let single = sameHuman(candidates) { return single }
        guard let seat else { return nil }
        return sameHuman(candidates.filter { districtNumber($0.district) == seat })
    }

    private static func sameHuman(_ candidates: [Entry]) -> Entry? {
        guard let first = candidates.first else { return nil }
        return candidates.allSatisfy { $0.bioguideID == first.bioguideID } ? first : nil
    }

    private static func ids(_ candidates: [Entry]) -> [String] {
        var seen = Set<String>()
        return candidates.map(\.bioguideID).filter { seen.insert($0).inserted }
    }

    public enum Resolution: Equatable, Sendable {
        case resolved(String)
        case ambiguous([String])
        case notFound
    }

    /// Fallback identifier used when the directory has no match. Distinct from a
    /// Bioguide ID by construction so the two can never be confused.
    public static func fallbackID(last: String, first: String, state: String, district: String?) -> String {
        let base = [last, first, state, district ?? ""]
            .map { normalize($0).replacingOccurrences(of: " ", with: "-") }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "x-\(base)"
    }

    public static func isBioguideID(_ id: String) -> Bool {
        id.range(of: #"^[A-Z]\d{6}$"#, options: .regularExpression) != nil
    }

    // MARK: - Loading

    /// Decodes the `congress-legislators` project's JSON. Only the fields needed to
    /// identify a member are read; the file carries far more.
    public static func fromCongressLegislators(_ data: Data) throws -> MemberDirectory {
        struct Legislator: Decodable {
            struct ID: Decodable { let bioguide: String? }
            struct Name: Decodable {
                let first: String?
                let last: String?
                let nickname: String?
                let official_full: String?
            }
            struct Term: Decodable {
                let type: String?
                let state: String?
                let district: Int?
            }
            let id: ID
            let name: Name
            let terms: [Term]?
        }

        let all = try JSONDecoder().decode([Legislator].self, from: data)
        var entries: [Entry] = []
        var seen = Set<String>()

        for l in all {
            guard let bio = l.id.bioguide,
                  let last = l.name.last, let first = l.name.first,
                  let terms = l.terms, !terms.isEmpty else { continue }

            // The Clerk prints whatever name the member files under, which is often the
            // one they go by rather than the legal forename the crosswalk records.
            // `official_full` is the fullest spelling available, so its leading word is
            // kept as an additional forename to try.
            let officialFirst = l.name.official_full?
                .components(separatedBy: " ").first
                .flatMap { $0 == first ? nil : $0 }
            let nickname = l.name.nickname ?? officialFirst

            // A member can serve several terms and change seat. Index every distinct
            // seat they held so an older filing still resolves, and so the seat number
            // can separate namesakes within one delegation.
            for t in terms {
                guard let state = t.state else { continue }
                let chamber: Chamber = (t.type == "sen") ? .senate : .house
                let key = "\(bio)|\(state)|\(chamber.rawValue)|\(t.district.map(String.init) ?? "-")"
                guard seen.insert(key).inserted else { continue }
                entries.append(Entry(
                    bioguideID: bio, last: last, first: first, state: state,
                    district: t.district.map(String.init), chamber: chamber,
                    nickname: nickname
                ))
            }
        }
        return MemberDirectory(entries: entries)
    }
}
