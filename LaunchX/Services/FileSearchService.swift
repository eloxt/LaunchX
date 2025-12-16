import AppKit
import Combine
import Foundation

class FileSearchService: NSObject {
    private var fileQuery = NSMetadataQuery()
    private var appQuery = NSMetadataQuery()
    private var cancellables = Set<AnyCancellable>()

    let resultsSubject = PassthroughSubject<[SearchResult], Never>()

    override init() {
        super.init()
        setupQueries()
    }

    private func setupQueries() {
        // Observe App Query
        NotificationCenter.default.publisher(
            for: .NSMetadataQueryDidFinishGathering, object: appQuery
        )
        .sink { [weak self] _ in self?.processResults() }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSMetadataQueryDidUpdate, object: appQuery)
            .sink { [weak self] _ in self?.processResults() }
            .store(in: &cancellables)

        // Observe File Query
        NotificationCenter.default.publisher(
            for: .NSMetadataQueryDidFinishGathering, object: fileQuery
        )
        .sink { [weak self] _ in self?.processResults() }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSMetadataQueryDidUpdate, object: fileQuery)
            .sink { [weak self] _ in self?.processResults() }
            .store(in: &cancellables)
    }

    func search(query text: String) {
        fileQuery.stop()
        appQuery.stop()

        guard !text.isEmpty else {
            resultsSubject.send([])
            return
        }

        // 1. App Query: Search entire system for Applications
        appQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        // Predicate: Name contains text AND ContentType is Application
        let appPredicate = NSPredicate(
            format: "%K CONTAINS[cd] %@ AND %K == 'com.apple.application-bundle'",
            NSMetadataItemFSNameKey, text,
            NSMetadataItemContentTypeKey)
        appQuery.predicate = appPredicate

        // 2. File Query: Search User Home for everything
        fileQuery.searchScopes = [NSMetadataQueryUserHomeScope]
        // Predicate: Name contains text
        let filePredicate = NSPredicate(
            format: "%K CONTAINS[cd] %@",
            NSMetadataItemFSNameKey, text)
        fileQuery.predicate = filePredicate

        appQuery.start()
        fileQuery.start()
    }

    private func processResults() {
        // Temporarily disable updates to avoid UI flickering during processing
        appQuery.disableUpdates()
        fileQuery.disableUpdates()

        var combinedResults: [SearchResult] = []
        var seenPaths = Set<String>()

        // Helper to process items
        func process(query: NSMetadataQuery, limit: Int) {
            let count = query.resultCount
            var addedCount = 0

            for i in 0..<count {
                if addedCount >= limit { break }

                guard let item = query.result(at: i) as? NSMetadataItem,
                    let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                    let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String
                else { continue }

                // Avoid duplicates (e.g., an App in UserHome found by both queries)
                if seenPaths.contains(path) { continue }

                // Filter out some noise if needed (e.g., Library folder content often not desired in launcher)
                if path.contains("/Library/") && !path.contains("/Mobile Documents/") {  // Allow iCloud Drive
                    // Simple heuristic to reduce noise: Skip Library unless it's iCloud
                    continue
                }

                seenPaths.insert(path)

                let icon = NSWorkspace.shared.icon(forFile: path)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)

                let result = SearchResult(
                    name: name,
                    path: path,
                    icon: icon,
                    isDirectory: isDir.boolValue
                )
                combinedResults.append(result)
                addedCount += 1
            }
        }

        // 1. Process Apps first (Higher priority)
        process(query: appQuery, limit: 10)

        // 2. Process Files second
        process(query: fileQuery, limit: 20)

        appQuery.enableUpdates()
        fileQuery.enableUpdates()

        resultsSubject.send(combinedResults)
    }
}
