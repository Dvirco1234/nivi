import Foundation
import NiviCore

/// Downloads (or copies, for local sources) a model into a destination, validating ggml.
final class ModelDownloader: NSObject {
    private var progressHandler: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var resumeData: Data?

    func download(_ model: ManagedModel, to destination: URL,
                  progress: @escaping (Double) -> Void) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        if case .localFile(let path) = model.source {
            let src = URL(fileURLWithPath: path)
            guard validate(src, model: model) else {
                throw err("Local file is not a valid ggml model")
            }
            if src != destination {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: src, to: destination)
            }
            return
        }

        guard let url = model.source.downloadURL else { throw err("No download URL") }
        self.progressHandler = progress
        let temp = try await runDownload(url: url)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        guard validate(destination, model: model) else {
            try? FileManager.default.removeItem(at: destination)
            throw err("Downloaded file failed validation")
        }
    }

    private func validate(_ url: URL, model: ManagedModel) -> Bool {
        ModelSpec(fileName: model.localFileName, url: url, minSizeBytes: model.minSizeBytes)
            .validate(fileAt: url) == .ok
    }

    private func err(_ msg: String) -> NSError {
        NSError(domain: "Nivi", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private func runDownload(url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let task: URLSessionDownloadTask
            if let resumeData { task = session.downloadTask(withResumeData: resumeData); self.resumeData = nil }
            else { task = session.downloadTask(with: url) }
            task.resume()
        }
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData a: Int64, totalBytesWritten b: Int64, totalBytesExpectedToWrite c: Int64) {
        guard c > 0 else { return }
        let f = Double(b) / Double(c)
        DispatchQueue.main.async { [weak self] in self?.progressHandler?(f) }
    }
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let holding = FileManager.default.temporaryDirectory
            .appendingPathComponent("nivi-dl-\(UUID().uuidString).bin")
        do {
            try FileManager.default.moveItem(at: location, to: holding)
            continuation?.resume(returning: holding)
        } catch { continuation?.resume(throwing: error) }
        continuation = nil
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
