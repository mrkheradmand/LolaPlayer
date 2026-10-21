import AppKit
import Foundation
import PlayerCore

extension PlayerModel {
    func startAutomaticUpdateChecks() {
        automaticUpdateTask?.cancel()
        automaticUpdateTask = nil
        guard automaticUpdateChecks, !CommandLine.arguments.contains("--smoke-test") else { return }
        let previousCheck = updateCheckTask
        automaticUpdateTask = Task { [weak self] in
            await previousCheck?.value
            while !Task.isCancelled {
                self?.checkForUpdates(manual: false)
                do { try await Task.sleep(for: .seconds(24 * 60 * 60)) }
                catch { return }
            }
        }
    }

    func checkForUpdates(manual: Bool = true) {
        guard updateCheckTask == nil else { return }
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            updateAvailability = .failed
            updateCheckStatus = "Build the app bundle to check for updates."
            return
        }
        updateAvailability = .checking
        updateCheckStatus = "Checking GitHub for updates…"
        updateCheckTask = Task { [weak self] in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel(); self?.updateCheckTask = nil }
            do {
                let update = try await UpdateChecker.check(currentVersion: currentVersion, session: session)
                try Task.checkCancellation()
                guard let self, manual || self.automaticUpdateChecks else { return }
                if let update {
                    self.updateAvailability = .available(update)
                    self.updateCheckStatus = "Lola Player \(update.version) is available."
                    if manual || UserDefaults.standard.string(forKey: "dismissedUpdateVersion") != update.version {
                        self.availableUpdate = update
                    }
                } else {
                    self.availableUpdate = nil
                    self.updateAvailability = .current
                    self.updateCheckStatus = "You’re up to date."
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.updateAvailability = .failed
                self?.updateCheckStatus = "Couldn’t check for updates. \(error.localizedDescription)"
            }
        }
    }

    func dismissUpdate() {
        if let update = availableUpdate {
            UserDefaults.standard.set(update.version, forKey: "dismissedUpdateVersion")
        }
        availableUpdate = nil
    }

    func openUpdateRelease() {
        guard let update = availableUpdate else { return }
        NSWorkspace.shared.open(update.releaseURL)
    }
}
