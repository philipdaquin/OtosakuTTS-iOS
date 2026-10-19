#if canImport(Sparkle)
import Sparkle
#endif
import Combine
import Foundation
import SwiftUI

@MainActor
final class SparkleUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
#endif

    init() {
#if canImport(Sparkle)
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let hasSparkleConfiguration = !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasSparkleConfiguration {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = controller
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main)
                .assign(to: &$canCheckForUpdates)
        } else {
            updaterController = nil
            canCheckForUpdates = false
        }
#else
        canCheckForUpdates = false
#endif
    }

    func checkForUpdates() {
#if canImport(Sparkle)
        updaterController?.checkForUpdates(nil)
#endif
    }
}
