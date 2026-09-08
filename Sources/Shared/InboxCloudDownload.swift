import Foundation

/// Kurzer iCloud-Drive-Download vor dem Lesen von `inbox.txt`.
/// Kein persistenter Metadata-Query-Listener. Die Watch kompiliert die Datei mit, hat aber keine Inbox-UI.
enum InboxCloudDownload {
    static let timeoutNanoseconds: UInt64 = 4_000_000_000
    static let pollNanoseconds: UInt64 = 200_000_000

    /// Ubiquitäre URL: Download anstoßen und kurz auf `.current` warten.
    /// Timeout: still — der Aufrufer liest den lokalen Stand.
    static func ensureLocal(at url: URL) async {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            // Bereits lokal oder Download läuft — weiter pollen.
        }
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while ContinuousClock.now < deadline {
            if isCurrent(url) { return }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    private static func isCurrent(_ url: URL) -> Bool {
        var copy = url
        copy.removeCachedResourceValue(forKey: .ubiquitousItemDownloadingStatusKey)
        copy.removeCachedResourceValue(forKey: .ubiquitousItemIsDownloadingKey)
        let values = try? copy.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
        ])
        if let status = values?.ubiquitousItemDownloadingStatus {
            return status == .current
        }
        return values?.ubiquitousItemIsDownloading != true
    }
}
