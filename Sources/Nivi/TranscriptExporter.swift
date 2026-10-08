import AppKit
import NiviCore
import SwiftUI
import UniformTypeIdentifiers

/// Writes a transcript to a file the user picked: plain text, Word, Rich Text or
/// OpenDocument.
///
/// The three document formats are written by `NSAttributedString` itself, so there is no
/// extra library. The text is split into paragraphs first, because whisper hands back one
/// endless line, and each paragraph is marked right to left or left to right from its own
/// letters. Without that mark Word lines Hebrew up on the left.
enum TranscriptExporter {
    struct Transcript {
        var text: String
        /// The audio file it came from, when there was one. Used for the title and the
        /// suggested file name.
        var sourceName: String?
        var createdAt: Date
        var durationMs: Int
    }

    /// Fonts that exist on any Mac or Windows machine that opens the file and that cover
    /// Hebrew. The system font would be saved under a private name Word does not know.
    private static let bodyFont = NSFont(name: "Arial", size: 12) ?? .systemFont(ofSize: 12)
    private static let titleFont = NSFont(name: "Arial Bold", size: 16) ?? .boldSystemFont(ofSize: 16)
    private static let detailFont = NSFont(name: "Arial", size: 10) ?? .systemFont(ofSize: 10)

    static func data(for transcript: Transcript, as format: TranscriptFormat) throws -> Data {
        let paragraphs = TranscriptParagraphs.split(transcript.text)
        if format == .plainText {
            return Data((paragraphs.joined(separator: "\n\n") + "\n").utf8)
        }
        let document = attributedDocument(transcript, paragraphs: paragraphs)
        let type: NSAttributedString.DocumentType
        switch format {
        case .plainText: type = .plain   // handled above
        case .word: type = .officeOpenXML
        case .richText: type = .rtf
        case .openDocument: type = .openDocument
        }
        return try document.data(from: NSRange(location: 0, length: document.length),
                                 documentAttributes: [.documentType: type])
    }

    private static func attributedDocument(_ transcript: Transcript, paragraphs: [String]) -> NSAttributedString {
        let document = NSMutableAttributedString()
        let wholeIsRightToLeft = TextDirection.isRightToLeft(transcript.text)

        /// `rightToLeft` is which way the line's own letters read. `alignRight` is which
        /// side of the page it sits on. They differ for the title and the detail line of a
        /// Hebrew transcript: "meeting.mp4" reads left to right, but belongs on the right
        /// with the rest of the document.
        func append(_ text: String, font: NSFont, rightToLeft: Bool, alignRight: Bool? = nil,
                    spacingAfter: CGFloat) {
            let style = NSMutableParagraphStyle()
            style.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
            style.alignment = (alignRight ?? rightToLeft) ? .right : .left
            style.paragraphSpacing = spacingAfter
            document.append(NSAttributedString(string: text + "\n",
                                               attributes: [.font: font, .paragraphStyle: style]))
        }

        let title = (transcript.sourceName?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Transcript"
        append(title, font: titleFont, rightToLeft: TextDirection.isRightToLeft(title),
               alignRight: wholeIsRightToLeft, spacingAfter: 4)
        append(detailLine(transcript), font: detailFont, rightToLeft: false,
               alignRight: wholeIsRightToLeft, spacingAfter: 14)
        for paragraph in paragraphs {
            append(paragraph, font: bodyFont, rightToLeft: TextDirection.isRightToLeft(paragraph),
                   spacingAfter: 10)
        }
        return document
    }

    private static func detailLine(_ transcript: Transcript) -> String {
        let date = DateFormatter.localizedString(from: transcript.createdAt, dateStyle: .long, timeStyle: .short)
        let length = DurationFormatting.short(milliseconds: transcript.durationMs)
        return "Transcribed by Nivi, \(date). Audio length \(length)."
    }

    // MARK: - Asking where to save

    /// Shows the save panel, then writes the file. Errors are shown to the user, because
    /// a save that fails quietly looks exactly like a save that worked.
    @MainActor
    static func save(_ transcript: Transcript, as format: TranscriptFormat) {
        let panel = NSSavePanel()
        panel.title = "Save transcript"
        panel.nameFieldStringValue = TranscriptExport.suggestedFileName(sourceName: transcript.sourceName,
                                                                         format: format)
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data(for: transcript, as: format).write(to: url, options: .atomic)
                Log.info("Saved transcript as \(format.fileExtension): \(url.lastPathComponent)")
            } catch {
                Log.error("Could not save transcript: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.messageText = "The transcript was not saved"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }
}

/// The "Save as" menu shown wherever a file transcript appears.
struct SaveTranscriptMenu: View {
    let transcript: TranscriptExporter.Transcript

    var body: some View {
        Menu("Save as…") {
            ForEach(TranscriptFormat.allCases, id: \.self) { format in
                Button(format.menuTitle) { TranscriptExporter.save(transcript, as: format) }
            }
        }
        .fixedSize()
    }
}
