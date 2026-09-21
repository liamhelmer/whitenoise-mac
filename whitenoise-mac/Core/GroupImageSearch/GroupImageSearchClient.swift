import Foundation

/// Searches a stock-image source for a group avatar. `OpenverseGroupImageSearchClient` is the
/// production implementation; injecting a stub keeps the search UI testable without network access.
nonisolated protocol GroupImageSearchClient {
    func searchImages(query: String) async throws -> [GroupImageSearchResult]
}
