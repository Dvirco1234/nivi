import Foundation
import DictatoCore

/// Keeps the list of past transcriptions and owns the file they are saved in.
///
/// The whole list is held in memory. A few thousand short records is well under two
/// megabytes, so searching and filtering never touch the disk: re-parsing the file on
/// every keystroke in the search box would be slow for no reason.
///
/// Nothing here saves audio. Only the text, and the few facts around it.
@MainActor
final class HistoryStore: ObservableObject {
    /// One instance for the app, because dictation writes to it and Preferences reads
    /// from it, and both must see the same list.
    static let shared = HistoryStore()

    /// In the order they were written, which is oldest first. Sorting for display is
    /// `HistoryFiltering`'s job.
    @Published private(set) var records: [HistoryRecord] = []

    let fileURL: URL
    private let settings = Settings()
    /// All file work happens here, so saving a dictation never delays the paste.
    private let ioQueue = DispatchQueue(label: "com.dvir.dictato.history")

    init(fileURL: URL = ModelPaths.appSupportBase().appendingPathComponent("history.jsonl")) {
        self.fileURL = fileURL
        reload()
    }

    // MARK: - Reading

    /// Reads the file from disk and drops anything older than the retention limit.
    ///
    /// Called at launch and whenever the retention setting changes. The rewrite only
    /// happens when something was actually dropped, so the usual case is a read.
    func reload() {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let all = HistoryFile.records(fromFileText: text)
        let kept = HistoryRetention.keeping(all,
                                            retentionDays: settings.historyRetentionDays,
                                            now: Date())
        records = kept
        if kept.count != all.count {
            Log.info("History: dropped \(all.count - kept.count) entries past the retention limit")
            rewrite(kept)
        }
    }

    // MARK: - Writing

    /// Saves one finished transcription, if the user has history turned on.
    ///
    /// Failures are logged and otherwise ignored. A history write must never be the
    /// reason a dictation does not land in the user's document.
    func record(text: String,
                durationSeconds: Double,
                source: HistorySource,
                modelID: String,
                language: String,
                profileID: String? = nil,
                sourceName: String? = nil) {
        guard settings.historyEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let record = HistoryRecord(text: trimmed,
                                   durationMs: Int((durationSeconds * 1000).rounded()),
                                   source: source,
                                   modelID: modelID,
                                   language: language,
                                   profileID: profileID,
                                   sourceName: sourceName)
        records.append(record)
        append(record)
        pruneAfterWrite()
    }

    func delete(id: String) {
        records.removeAll { $0.id == id }
        rewrite(records)
    }

    func delete(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        records.removeAll { ids.contains($0.id) }
        rewrite(records)
    }

    func deleteAll() {
        records = []
        let url = fileURL
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
        Log.info("History: deleted every saved entry")
    }

    /// Drops expired entries from the list we already hold, without re-reading the file.
    private func pruneAfterWrite() {
        let kept = HistoryRetention.keeping(records,
                                            retentionDays: settings.historyRetentionDays,
                                            now: Date())
        guard kept.count != records.count else { return }
        records = kept
        rewrite(kept)
    }

    /// Prunes on demand, used when the retention setting changes.
    func pruneNow() { pruneAfterWrite() }

    // MARK: - The file itself

    private func append(_ record: HistoryRecord) {
        guard let line = HistoryFile.line(for: record) else {
            Log.error("History: could not encode an entry, so it was not saved")
            return
        }
        let url = fileURL
        ioQueue.async { Self.appendLine(line, to: url) }
    }

    private func rewrite(_ records: [HistoryRecord]) {
        let text = HistoryFile.fileText(for: records)
        let url = fileURL
        ioQueue.async { Self.write(text, to: url) }
    }

    /// One line at the end of the file. Appending means saving a dictation never
    /// rewrites what is already there.
    private static func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)
        guard manager.fileExists(atPath: url.path) else {
            // 0600 so only this user can read what was dictated.
            manager.createFile(atPath: url.path, contents: data,
                               attributes: [.posixPermissions: 0o600])
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Log.error("History: could not append an entry: \(error.localizedDescription)")
        }
    }

    private static func write(_ text: String, to url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                     withIntermediateDirectories: true)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            // An atomic write replaces the file, so the mode has to be set again.
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.error("History: could not save the file: \(error.localizedDescription)")
        }
    }
}
