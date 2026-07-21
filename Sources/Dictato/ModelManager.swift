import Foundation
import DictatoCore

final class ModelManager: NSObject {
    private let spec: ModelSpec
    private var progressHandler: ((Double) -> Void)?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var resumeData: Data?

    init(spec: ModelSpec = .ivritTurbo) {
        self.spec = spec
    }

    var modelURL: URL {
        if let override = Settings().modelPathOverride {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dictato/models", isDirectory: true)
            .appendingPathComponent(spec.fileName)
    }

    /// Returns the validated local model path, downloading it first if needed.
    func ensureModel(progress: @escaping (Double) -> Void) async throws -> URL {
        let destination = modelURL
        switch spec.validate(fileAt: destination) {
        case .ok:
            return destination
        case .missing:
            Log.info("Model missing, downloading")
        case .tooSmall, .badMagic:
            Log.error("Model file invalid, deleting and redownloading")
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = try await download(progress: progress)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        guard spec.validate(fileAt: destination) == .ok else {
            try? FileManager.default.removeItem(at: destination)
            throw NSError(domain: "Dictato", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Downloaded model failed validation"])
        }
        Log.info("Model downloaded to \(destination.path)")
        return destination
    }

    func deleteModel() throws {
        try FileManager.default.removeItem(at: modelURL)
    }

    private func download(progress: @escaping (Double) -> Void) async throws -> URL {
        progressHandler = progress
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            downloadContinuation = continuation
            let task: URLSessionDownloadTask
            if let resumeData {
                task = session.downloadTask(withResumeData: resumeData)
                self.resumeData = nil
            } else {
                task = session.downloadTask(with: spec.url)
            }
            task.resume()
        }
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in self?.progressHandler?(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move out of the system temp slot synchronously — it is deleted when this returns.
        let holding = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictato-model-download.bin")
        do {
            try? FileManager.default.removeItem(at: holding)
            try FileManager.default.moveItem(at: location, to: holding)
            downloadContinuation?.resume(returning: holding)
        } catch {
            downloadContinuation?.resume(throwing: error)
        }
        downloadContinuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }  // success handled in didFinishDownloadingTo
        resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        downloadContinuation?.resume(throwing: error)
        downloadContinuation = nil
    }
}
