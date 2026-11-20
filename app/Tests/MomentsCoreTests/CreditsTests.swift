import Foundation
import Testing
@testable import MomentsCore

@Suite("Photo credits")
struct CreditsTests {
    static let credits: [PhotoCredit] = (try? Credits.load(from: Fixtures.bundle)) ?? []

    @Test func creditsFileDecodes() throws {
        let url = try #require(Fixtures.bundle.url(forResource: "credits", withExtension: "json", subdirectory: MomentStore.dataFolder))
        let credits = try Credits.decode(Data(contentsOf: url))
        #expect(!credits.isEmpty)
        #expect(Set(credits.map(\.file)).count == credits.count, "one entry per file")
    }

    @Test func everyPhotoInTheMomentsHasACredit() {
        let credited = Set(Self.credits.map(\.file))
        let missing = Set(Fixtures.bundledStore.moments.compactMap(\.image?.file)).subtracting(credited)
        #expect(missing.isEmpty, "no credit for \(missing.sorted())")
    }

    @Test func everyCreditNamesAnAuthorAndALicence() {
        for credit in Self.credits {
            #expect(!credit.author.trimmingCharacters(in: .whitespaces).isEmpty, "\(credit.file) has no author")
            #expect(!credit.licence.trimmingCharacters(in: .whitespaces).isEmpty, "\(credit.file) has no licence")
            #expect(!credit.moments.isEmpty, "\(credit.file) is used by no moment")
        }
    }

    @Test func aBlankLicenceLinkDecodesAsNoLink() throws {
        let json = """
        {"version": 1, "photos": [{"file": "M0114.jpg", "moments": ["M0001", "M0114"], "author": "A. Author",
          "licence": "Attribution", "licenceURL": null, "commonsFile": "X.jpg", "commonsPage": null}]}
        """
        let credit = try #require(try Credits.decode(Data(json.utf8)).first)
        #expect(credit.licenceURL == nil)
        #expect(credit.mainMomentID == "M0114")
    }
}
