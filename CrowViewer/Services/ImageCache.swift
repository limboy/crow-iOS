import CryptoKit
import SwiftUI
import UIKit

/// Images kept in memory and on disk. Crow names every media file with a fresh UUID, so a url's
/// content never changes and a downloaded image is kept without checking back with the server.
nonisolated final class ImageCache: Sendable {
    static let shared = ImageCache()

    /// NSCache is thread-safe.
    private nonisolated(unsafe) let memory = NSCache<NSURL, UIImage>()
    private let root: URL

    init(root: URL = .cachesDirectory.appending(path: "CrowMedia", directoryHint: .isDirectory)) {
        self.root = root
        memory.totalCostLimit = 128 << 20
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async throws -> UIImage {
        if let image = cached(url) { return image }
        let file = root.appending(path: Self.hash(url.absoluteString))
        let data: Data
        if let saved = try? Data(contentsOf: file) {
            data = saved
        } else {
            let (downloaded, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
            data = downloaded
            try? data.write(to: file, options: .atomic)
        }
        guard let decoded = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        let image = await decoded.byPreparingForDisplay() ?? decoded
        memory.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// `AsyncImage`, backed by `ImageCache`.
struct CachedAsyncImage<Content: View>: View {
    let url: URL
    var transaction = Transaction()
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(ImageCache.shared.cached(url).map { .success(Image(uiImage: $0)) } ?? phase)
            .task(id: url) {
                guard ImageCache.shared.cached(url) == nil else { return }
                do {
                    let image = try await ImageCache.shared.image(for: url)
                    withTransaction(transaction) { phase = .success(Image(uiImage: image)) }
                } catch is CancellationError {
                } catch {
                    phase = .failure(error)
                }
            }
    }
}
