import Foundation
import Testing
@testable import MomentsCore

/// Builds wallpaper stores in the layout macOS 27 uses. No user data: every UUID, path and
/// asset here is made up.
enum WallpaperFixtures {
    static let saver = URL(filePath: "/Users/test/Library/Screen Savers/SportingMomentsClock.saver", directoryHint: .isDirectory)
    static let otherSaver = "/Users/test/Library/Screen Savers/Other.saver"
    static let appleSaver = "/System/Library/Screen Savers/FloatingMessage.saver"
    static let setDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let oldDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
    static let null = "$null"

    static func plistData(_ value: Any) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    static func decode(_ data: Data) -> [String: Any] {
        try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    static func choice(_ provider: String, _ configuration: [String: Any]) -> [String: Any] {
        ["Provider": provider, "Files": [Any](), "Configuration": plistData(configuration)]
    }

    static func saverChoice(_ path: String) -> [String: Any] {
        let url = URL(filePath: path, directoryHint: .notDirectory)
        return choice(ScreenSaverSelection.screenSaverProvider, ["module": ["relative": url.absoluteString]])
    }

    static func aerialChoice(_ id: String = "11111111-2222-3333-4444-555555555555") -> [String: Any] {
        choice("com.apple.wallpaper.choice.aerials", ["assetID": id])
    }

    static let options = plistData(["values": ["aerialShuffleFrequency": ["picker": ["_0": ["id": "shuffle_every_12_hours"]]]]])

    static func member(_ choices: [[String: Any]], shuffle: Any = null) -> [String: Any] {
        [
            "Content": ["Choices": choices, "Shuffle": shuffle, "EncodedOptionValues": options],
            "LastSet": oldDate,
            "LastUse": oldDate,
        ]
    }

    static func individual(desktop: [String: Any] = member([aerialChoice()]), idle: [String: Any]) -> [String: Any] {
        ["Type": "individual", "Desktop": desktop, "Idle": idle]
    }

    static func linked(_ member: [String: Any] = member([aerialChoice()])) -> [String: Any] {
        ["Type": "linked", "Linked": member]
    }

    static func ours() -> [String: Any] { individual(idle: member([saverChoice(saver.path(percentEncoded: false))])) }
    static func other() -> [String: Any] { individual(idle: member([saverChoice(otherSaver)])) }

    static func store(
        all: Any = null, systemDefault: Any = null,
        displays: [String: Any] = [:], spaces: [String: Any] = [:]
    ) -> [String: Any] {
        ["AllSpacesAndDisplays": all, "SystemDefault": systemDefault, "Displays": displays, "Spaces": spaces]
    }

    static func space(default entry: Any = null, displays: [String: Any] = [:]) -> [String: Any] {
        ["Default": entry, "Displays": displays]
    }

    /// Two displays, three spaces including the "" space, and a linked system default.
    static func typical(idle: [String: Any]) -> [String: Any] {
        store(
            systemDefault: linked(),
            displays: [
                "DISPLAY-A": individual(idle: idle),
                "DISPLAY-B": linked(member([aerialChoice("B")])),
            ],
            spaces: [
                "": space(default: linked(), displays: ["DISPLAY-A": individual(idle: idle)]),
                "SPACE-1": space(default: individual(idle: idle), displays: [
                    "DISPLAY-A": individual(idle: idle),
                    "DISPLAY-B": linked(member([aerialChoice("C")])),
                ]),
                "SPACE-2": space(default: individual(idle: idle)),
            ]
        )
    }

    /// Every entry in a decoded store, with where it sits.
    static func entries(_ root: [String: Any]) -> [(String, [String: Any])] {
        var found: [(String, [String: Any])] = []
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            if let entry = root[key] as? [String: Any] { found.append((key, entry)) }
        }
        for (id, entry) in root["Displays"] as! [String: Any] { found.append(("display \(id)", entry as! [String: Any])) }
        for (id, value) in root["Spaces"] as! [String: Any] {
            let space = value as! [String: Any]
            if let entry = space["Default"] as? [String: Any] { found.append(("space \(id)", entry)) }
            for (display, entry) in space["Displays"] as? [String: Any] ?? [:] {
                found.append(("space \(id) display \(display)", entry as! [String: Any]))
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }

    static func same(_ a: Any?, _ b: Any?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return NSArray(object: a).isEqual(NSArray(object: b))
    }

    static func modulePath(of member: Any?) -> String? {
        guard let member = member as? [String: Any],
              let content = member["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              choices.count == 1,
              let data = choices[0]["Configuration"] as? Data
        else { return nil }
        return ScreenSaverSelection.modulePath(inConfiguration: data)
    }
}

@Suite("Screen saver selection")
struct ScreenSaverSelectionTests {
    typealias F = WallpaperFixtures
    let ourPath = "/Users/test/Library/Screen Savers/SportingMomentsClock.saver"

    @Test func configurationMatchesWhatSystemSettingsWrites() throws {
        let data = ScreenSaverSelection.configuration(for: F.saver)
        let plist = F.decode(data)
        let module = try #require(plist["module"] as? [String: Any])
        #expect(module["relative"] as? String == "file:///Users/test/Library/Screen%20Savers/SportingMomentsClock.saver")
        #expect(module.count == 1)
        #expect(ScreenSaverSelection.modulePath(inConfiguration: data) == ourPath)
    }

    @Test func modulePathReadsBaseAndIgnoresTrailingSlash() {
        let withBase = F.plistData(["module": ["relative": "SportingMomentsClock.saver/", "base": "file:///Users/test/Library/Screen%20Savers/"]])
        #expect(ScreenSaverSelection.modulePath(inConfiguration: withBase) == ourPath)
        let web = F.plistData(["module": ["relative": "https://example.com/x.saver"]])
        #expect(ScreenSaverSelection.modulePath(inConfiguration: web) == nil)
        #expect(ScreenSaverSelection.modulePath(inConfiguration: Data("nonsense".utf8)) == nil)
    }

    @Test func selectedWhenOursEverywhere() throws {
        let data = F.plistData(F.typical(idle: F.ours()["Idle"] as! [String: Any]).replacingLinked(with: F.ours()))
        #expect(try ScreenSaverSelection.isSelected(data, saver: F.saver))
        // The saver URL may come with or without a trailing slash.
        #expect(try ScreenSaverSelection.isSelected(data, saver: URL(filePath: ourPath, directoryHint: .notDirectory)))
    }

    @Test func notSelectedWhenAnotherThirdPartySaverIs() throws {
        let data = F.plistData(F.store(displays: ["D": F.other()], spaces: ["S": F.space(default: F.other())]))
        #expect(try !ScreenSaverSelection.isSelected(data, saver: F.saver))
    }

    @Test func notSelectedWhenOneSpaceDiffers() throws {
        let data = F.plistData(F.store(displays: ["D": F.ours()], spaces: ["S": F.space(default: F.ours(), displays: ["D": F.other()])]))
        #expect(try !ScreenSaverSelection.isSelected(data, saver: F.saver))
    }

    @Test func notSelectedWhenALinkedAerialShowsAsScreenSaver() throws {
        let data = F.plistData(F.store(displays: ["D": F.ours()], spaces: ["": F.space(displays: ["D": F.linked()])]))
        #expect(try !ScreenSaverSelection.isSelected(data, saver: F.saver))
    }

    @Test("Apple's own screen savers count as another one", arguments: ["bundle", "macintosh", "aerial"])
    func appleSaversAreNotOurs(_ kind: String) throws {
        let choice = switch kind {
        case "bundle": F.saverChoice(F.appleSaver)
        case "macintosh": F.choice("com.apple.wallpaper.choice.macintosh", ["style": "classic"])
        default: F.aerialChoice()
        }
        let data = F.plistData(F.store(displays: ["D": F.individual(idle: F.member([choice]))]))
        #expect(try !ScreenSaverSelection.isSelected(data, saver: F.saver))
        let updated = try ScreenSaverSelection.select(data, saver: F.saver, at: F.setDate)
        #expect(try ScreenSaverSelection.isSelected(updated, saver: F.saver))
    }

    @Test func shuffledIdleIsNotOurs() throws {
        let shuffle = F.member([F.saverChoice(ourPath), F.saverChoice(F.otherSaver)], shuffle: ["frequency": "hourly"])
        let data = F.plistData(F.store(displays: ["D": F.individual(idle: shuffle)]))
        #expect(try !ScreenSaverSelection.isSelected(data, saver: F.saver))
        let root = F.decode(try ScreenSaverSelection.select(data, saver: F.saver, at: F.setDate))
        let idle = try #require(((root["Displays"] as? [String: Any])?["D"] as? [String: Any])?["Idle"] as? [String: Any])
        #expect((idle["Content"] as? [String: Any])?["Shuffle"] as? String == F.null)
    }

    @Test func systemDefaultDoesNotDecideTheStatus() throws {
        let data = F.plistData(F.store(systemDefault: F.linked(), displays: ["D": F.ours()]))
        #expect(try ScreenSaverSelection.isSelected(data, saver: F.saver))
    }

    @Test func selectSetsEveryIdleAndLeavesEveryDesktop() throws {
        let before = F.typical(idle: F.other()["Idle"] as! [String: Any])
        let data = F.plistData(before)
        let updated = try ScreenSaverSelection.select(data, saver: F.saver, at: F.setDate)
        #expect(try ScreenSaverSelection.isSelected(updated, saver: F.saver))

        let old = F.entries(before)
        let new = F.entries(F.decode(updated))
        #expect(old.map(\.0) == new.map(\.0))
        for ((place, was), (_, now)) in zip(old, new) {
            #expect(now["Type"] as? String == "individual", "\(place)")
            #expect(now.count == 3, "\(place)")
            // The wallpaper is exactly what it was: the old Desktop, or for a linked entry the old Linked member.
            let desktop = was["Type"] as? String == "linked" ? was["Linked"] : was["Desktop"]
            #expect(F.same(now["Desktop"], desktop), "\(place)")
            #expect(F.modulePath(of: now["Idle"]) == ourPath, "\(place)")
        }
    }

    @Test func linkedEntryBecomesIndividual() throws {
        let linkedMember = F.member([F.aerialChoice("LINKED")])
        let data = F.plistData(F.store(displays: ["D": F.linked(linkedMember)]))
        let root = F.decode(try ScreenSaverSelection.select(data, saver: F.saver, at: F.setDate))
        let entry = try #require((root["Displays"] as? [String: Any])?["D"] as? [String: Any])
        #expect(Set(entry.keys) == ["Type", "Desktop", "Idle"])
        #expect(entry["Type"] as? String == "individual")
        #expect(F.same(entry["Desktop"], linkedMember))
        let idle = try #require(entry["Idle"] as? [String: Any])
        let content = try #require(idle["Content"] as? [String: Any])
        let choices = try #require(content["Choices"] as? [[String: Any]])
        #expect(choices.count == 1)
        #expect(choices[0]["Provider"] as? String == ScreenSaverSelection.screenSaverProvider)
        #expect(F.same(choices[0]["Files"], [Any]()))
        #expect(choices[0]["Configuration"] as? Data == ScreenSaverSelection.configuration(for: F.saver))
        #expect(content["Shuffle"] as? String == F.null)
        #expect(idle["LastSet"] as? Date == F.setDate)
        #expect(idle["LastUse"] as? Date == F.setDate)
    }

    @Test func individualIdleKeepsItsOtherKeys() throws {
        var idle = F.member([F.saverChoice(F.otherSaver)])
        idle["FutureMemberKey"] = "kept"
        var content = idle["Content"] as! [String: Any]
        content["FutureContentKey"] = Data([1, 2, 3])
        idle["Content"] = content
        let data = F.plistData(F.store(displays: ["D": F.individual(idle: idle)]))
        let root = F.decode(try ScreenSaverSelection.select(data, saver: F.saver, at: F.setDate))
        let newIdle = try #require(((root["Displays"] as? [String: Any])?["D"] as? [String: Any])?["Idle"] as? [String: Any])
        #expect(newIdle["FutureMemberKey"] as? String == "kept")
        let newContent = try #require(newIdle["Content"] as? [String: Any])
        #expect(newContent["FutureContentKey"] as? Data == Data([1, 2, 3]))
        #expect(newContent["EncodedOptionValues"] as? Data == F.options)
    }

    @Test func entriesAlreadyOursAreLeftAlone() throws {
        let before = F.store(displays: ["D": F.ours(), "E": F.other()])
        let root = F.decode(try ScreenSaverSelection.select(F.plistData(before), saver: F.saver, at: F.setDate))
        let displays = try #require(root["Displays"] as? [String: Any])
        // Same dates and all: the entry was not rewritten.
        #expect(F.same(displays["D"], (before["Displays"] as! [String: Any])["D"]))
        #expect(F.modulePath(of: (displays["E"] as? [String: Any])?["Idle"]) == ourPath)
    }

    @Test func alreadySelectedStoreComesBackUnchanged() throws {
        let before = F.store(all: F.ours(), displays: ["D": F.ours()], spaces: ["S": F.space(default: F.ours(), displays: ["D": F.ours()])])
        let after = F.decode(try ScreenSaverSelection.select(F.plistData(before), saver: F.saver, at: F.setDate))
        #expect(F.same(after, before))
    }

    @Test func everythingOutsideIdleSurvivesTheRoundTrip() throws {
        var before = F.typical(idle: F.other()["Idle"] as! [String: Any])
        before["AllSpacesAndDisplays"] = F.linked(F.member([F.aerialChoice("ALL")]))
        let after = F.decode(try ScreenSaverSelection.select(F.plistData(before), saver: F.saver, at: F.setDate))
        // Strip what select is meant to change, then the rest must be identical.
        func strip(_ root: [String: Any]) -> [[String: Any]] {
            F.entries(root).map { place, entry in
                let desktop = entry["Type"] as? String == "linked" ? entry["Linked"] : entry["Desktop"]
                return ["place": place, "desktop": desktop as Any]
            }
        }
        #expect(F.same(strip(before), strip(after)))
        #expect(F.modulePath(of: (after["AllSpacesAndDisplays"] as? [String: Any])?["Idle"]) == ourPath)
        #expect(F.modulePath(of: (after["SystemDefault"] as? [String: Any])?["Idle"]) == ourPath)
    }

    // MARK: Refusals

    static let malformed: [(String, Data)] = {
        func with(_ change: (inout [String: Any]) -> Void) -> Data {
            var root = F.store(displays: ["D": F.ours()], spaces: ["S": F.space(default: F.other())])
            change(&root)
            return F.plistData(root)
        }
        func display(_ entry: Any) -> Data { with { $0["Displays"] = ["D": entry] } }
        var noContent = F.other(); noContent["Idle"] = ["LastSet": F.oldDate]
        var noChoices = F.other(); noChoices["Idle"] = ["Content": ["Shuffle": F.null]]
        var badChoice = F.other(); badChoice["Idle"] = F.member([["Provider": "x", "Files": [Any]()]])
        var stringConfig = F.other(); stringConfig["Idle"] = F.member([["Provider": "x", "Files": [Any](), "Configuration": "text"]])
        var extraKey = F.linked(); extraKey["Idle"] = F.member([F.saverChoice(F.otherSaver)])
        var noIdle = F.other(); noIdle["Idle"] = nil
        return [
            ("not a plist", Data("hello".utf8)),
            ("empty file", Data()),
            ("top level array", F.plistData([1, 2, 3])),
            ("unknown top level key", with { $0["PerApp"] = [String: Any]() }),
            ("no Spaces", with { $0["Spaces"] = nil }),
            ("no Displays", with { $0["Displays"] = nil }),
            ("Displays not a dictionary", with { $0["Displays"] = [Any]() }),
            ("space with unknown key", with { $0["Spaces"] = ["S": ["Default": F.other(), "Extra": 1]] }),
            ("space not a dictionary", with { $0["Spaces"] = ["S": "x"] }),
            ("SystemDefault a number", with { $0["SystemDefault"] = 5 }),
            ("other null spelling", with { $0["SystemDefault"] = "null" }),
            ("unknown Type", display(["Type": "mirrored", "Linked": F.member([F.aerialChoice()])])),
            ("no Type", display(["Desktop": F.member([]), "Idle": F.member([])])),
            ("individual without Idle", display(noIdle)),
            ("linked with an Idle too", display(extraKey)),
            ("member without Content", display(noContent)),
            ("Content without Choices", display(noChoices)),
            ("choice without Configuration", display(badChoice)),
            ("Configuration not data", display(stringConfig)),
            ("entry a string", display("individual")),
        ]
    }()

    @Test("Refuses anything not exactly as expected", arguments: malformed)
    func refusesMalformed(_ name: String, _ data: Data) {
        #expect(throws: ScreenSaverSelection.Refusal.self, "\(name)") {
            try ScreenSaverSelection.isSelected(data, saver: F.saver)
        }
        #expect(throws: ScreenSaverSelection.Refusal.self, "\(name)") {
            try ScreenSaverSelection.select(data, saver: F.saver)
        }
    }

    @Test func refusesAStoreWithNoDisplaysOrSpaces() throws {
        let empty = F.plistData(F.store(systemDefault: F.linked()))
        #expect(try !ScreenSaverSelection.isSelected(empty, saver: F.saver))
        #expect(throws: ScreenSaverSelection.Refusal.noEntries) {
            try ScreenSaverSelection.select(empty, saver: F.saver)
        }
    }

    @Test func emptySlotsAreFine() throws {
        let data = F.plistData(F.store(displays: ["D": F.other()], spaces: ["S": F.space(), "T": ["Displays": [String: Any]()]]))
        let updated = try ScreenSaverSelection.select(data, saver: F.saver)
        #expect(try ScreenSaverSelection.isSelected(updated, saver: F.saver))
        let spaces = F.decode(updated)["Spaces"] as? [String: Any]
        #expect((spaces?["S"] as? [String: Any])?["Default"] as? String == F.null)
    }
}

/// Counts restarts and can stand in for an agent that throws the change away.
private actor FakeAgent {
    private(set) var restarts = 0
    let revert: (index: URL, to: Data)?

    init(revert: (index: URL, to: Data)? = nil) { self.revert = revert }

    func restart() {
        restarts += 1
        // Only the first restart reverts, as an agent that rewrote its own state would.
        if restarts == 1, let revert { try? revert.to.write(to: revert.index) }
    }
}

@Suite("Wallpaper store file")
struct WallpaperStoreTests {
    typealias F = WallpaperFixtures

    let folder: URL
    let store: WallpaperStore

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "WallpaperStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = WallpaperStore(index: folder.appending(path: "Index.plist"), backup: folder.appending(path: "Support/WallpaperIndex.backup.plist"))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: folder) }

    @Test func missingStoreIsUnknownAndNotWritten() async throws {
        defer { cleanUp() }
        #expect(store.state(of: F.saver) == .unknown)
        let agent = FakeAgent()
        await #expect(throws: WallpaperStore.Failure.self) {
            try await store.select(F.saver, restartAgent: { await agent.restart() }, settle: .zero)
        }
        #expect(await agent.restarts == 0)
        #expect(!FileManager.default.fileExists(atPath: store.index.path))
        #expect(!FileManager.default.fileExists(atPath: store.backup.path))
    }

    @Test func malformedStoreIsLeftByteForByte() async throws {
        defer { cleanUp() }
        let bytes = F.plistData(F.store(displays: ["D": ["Type": "mirrored"]]))
        try bytes.write(to: store.index)
        #expect(store.state(of: F.saver) == .unknown)
        let agent = FakeAgent()
        await #expect(throws: WallpaperStore.Failure.self) {
            try await store.select(F.saver, restartAgent: { await agent.restart() }, settle: .zero)
        }
        #expect(try Data(contentsOf: store.index) == bytes)
        #expect(await agent.restarts == 0)
    }

    @Test func selectWritesBacksUpAndRestartsOnce() async throws {
        defer { cleanUp() }
        let original = F.plistData(F.typical(idle: F.other()["Idle"] as! [String: Any]))
        try original.write(to: store.index)
        #expect(store.state(of: F.saver) == .notSelected)
        let agent = FakeAgent()
        try await store.select(F.saver, restartAgent: { await agent.restart() }, settle: .zero)
        #expect(store.state(of: F.saver) == .selected)
        #expect(try Data(contentsOf: store.backup) == original)
        #expect(await agent.restarts == 1)
    }

    @Test func alreadySelectedDoesNothing() async throws {
        defer { cleanUp() }
        let original = F.plistData(F.store(displays: ["D": F.ours()]))
        try original.write(to: store.index)
        let agent = FakeAgent()
        try await store.select(F.saver, restartAgent: { await agent.restart() }, settle: .zero)
        #expect(try Data(contentsOf: store.index) == original)
        #expect(!FileManager.default.fileExists(atPath: store.backup.path))
        #expect(await agent.restarts == 0)
    }

    @Test func changeThatDoesNotTakeIsUndone() async throws {
        defer { cleanUp() }
        let original = F.plistData(F.store(displays: ["D": F.linked()]))
        try original.write(to: store.index)
        let agent = FakeAgent(revert: (store.index, original))
        await #expect(throws: WallpaperStore.Failure.didNotTake) {
            try await store.select(F.saver, restartAgent: { await agent.restart() }, settle: .zero)
        }
        #expect(try Data(contentsOf: store.index) == original)
        #expect(await agent.restarts == 2)
    }
}

private extension Dictionary where Key == String, Value == Any {
    /// The same store with every linked entry swapped for `entry`.
    func replacingLinked(with entry: [String: Any]) -> [String: Any] {
        func swap(_ value: Any) -> Any {
            guard let dict = value as? [String: Any] else { return value }
            if dict["Type"] as? String == "linked" { return entry }
            return dict.mapValues(swap)
        }
        return mapValues(swap)
    }
}
