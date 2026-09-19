import Foundation

enum AppGroup {
    private static let original = "group.de.marcel.optimes"

    static let id: String = {
        var bundleID = Bundle.main.bundleIdentifier ?? ""
        // Extensions tragen genau EINEN Suffix hinter der App-Bundle-ID
        // (so setzt es auch der AppLoader in patchProjectSigning).
        if Bundle.main.bundleURL.pathExtension == "appex" {
            bundleID = bundleID.split(separator: ".").dropLast().joined(separator: ".")
        }
        let derived = "group." + bundleID
        // Nur nehmen, wenn dieser Build die Gruppe wirklich entitled hat.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: derived) != nil {
            return derived
        }
        return original
    }()
}
