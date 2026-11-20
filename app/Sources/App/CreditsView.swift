import MomentsCore
import OSLog
import SwiftUI

/// Credits for every bundled photo and font, with the licences linked, as Creative Commons asks.
struct CreditsView: View {
    let store: MomentStore
    /// Loaded once, when the window first appears.
    @State private var photos: [Photo] = []

    private struct Photo: Identifiable {
        let credit: PhotoCredit
        let caption: String
        var id: String { credit.id }
    }

    var body: some View {
        Form {
            Section {
                Text("Times are approximate unless documented; those cards say Exactly.")
                Text("Moments come from Wikipedia and the sources recorded for each one.")
            } header: {
                Text("Sporting Moments Clock, version \(AppInfo.version)")
            }

            Section("Photos") {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(photo.caption)
                        Text(creditLine(for: photo.credit))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Fonts") {
                FontCredit(name: "Barlow Condensed", licenceFile: "OFL-BarlowCondensed")
                FontCredit(name: "Newsreader", licenceFile: "OFL-Newsreader")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 640)
        .onAppear {
            if photos.isEmpty { photos = loadPhotos() }
        }
    }

    /// Each credit with the caption of the moment the photo belongs to.
    private func loadPhotos() -> [Photo] {
        let credits: [PhotoCredit]
        do {
            credits = try Credits.load(from: AppResources.bundle)
        } catch {
            Logger(subsystem: AppIdentity.bundleID, category: "data").error("Could not load credits: \(error)")
            return []
        }
        let captions = Dictionary(store.moments.map { ($0.id, $0.caption) }, uniquingKeysWith: { first, _ in first })
        return credits.map { credit in
            // A related photo shows a person or place, not the moment, so it is listed by its subject.
            let caption = credit.subject ?? credit.mainMomentID.flatMap { captions[$0] }.map(Card.typeset)
            return Photo(credit: credit, caption: caption ?? credit.commonsFile)
        }
    }

    /// "Photo: Author · CC BY-SA 4.0 · Wikimedia Commons", with the licence and the source page linked.
    private func creditLine(for photo: PhotoCredit) -> AttributedString {
        var licence = AttributedString(photo.licence)
        licence.link = photo.licenceURL
        var commons = AttributedString(photo.sourceName)
        commons.link = photo.commonsPage
        return AttributedString("Photo: \(photo.author) · ") + licence + AttributedString(" · ") + commons
    }
}

/// One bundled font: its licence linked, and the full licence text on demand.
private struct FontCredit: View {
    let name: String
    let licenceFile: String

    var body: some View {
        DisclosureGroup {
            ScrollView {
                Text(licenceText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text(licence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var licence: AttributedString {
        var text = AttributedString("SIL Open Font License 1.1")
        text.link = URL(string: "https://openfontlicense.org")
        return text
    }

    private var licenceText: String {
        AppResources.bundle.url(forResource: licenceFile, withExtension: "txt", subdirectory: "Fonts")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "The licence text is missing from this copy of the app."
    }
}
