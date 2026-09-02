import SwiftUI
import UIKit

/// Temp-Datei, die erst nach dem Schreiben das Share-Sheet öffnet (`.sheet(item:)`).
/// URL ist Backup-JSON oder Listen-PDF — gleiches Blatt, anderer Dateiname.
struct BackupShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// System-Teilen-Blatt. Bekommt immer eine existierende Datei, kein optionales `if let`.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        Self.configurePopover(controller)
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        Self.configurePopover(controller)
    }

    /// iPad: `UIActivityViewController` braucht eine Popover-Quelle, sonst bleibt das Blatt leer.
    /// iPhone nutzt diesen Pfad nicht. `view` ist auf neueren SDKs `UIView?` (Swift 6).
    private static func configurePopover(_ controller: UIActivityViewController) {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              let popover = controller.popoverPresentationController,
              let source = controller.view else { return }
        popover.sourceView = source
        let bounds = source.bounds
        popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
    }
}
