import UIKit
import Flutter
import WidgetKit  // ← NEU

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    
    // ← NEU: Channel als Property speichern damit er nicht deallocated wird
    private var widgetChannel: FlutterMethodChannel?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        // ── NEU: Widget-Channel registrieren ─────────────────────────────
        if let controller = window?.rootViewController as? FlutterViewController {
            widgetChannel = FlutterMethodChannel(
                name: "de.marcel.optimes/widget",
                binaryMessenger: controller.binaryMessenger
            )
            widgetChannel?.setMethodCallHandler { call, result in
                if call.method == "updateSchedule" {
                    if let args = call.arguments as? [String: Any],
                       let json = args["json"] as? String {
                        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
                        defaults?.set(json, forKey: "schedule_entries")
                        defaults?.synchronize()
                    }
                    if #available(iOS 14.0, *) {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    result(nil)
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
        }
        // ─────────────────────────────────────────────────────────────────

        // Kaltstart: PDF oder URL
        if let urlContext = connectionOptions.urlContexts.first {
            let url = urlContext.url
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.handleAnyURL(url)
            }
        }

        // Kaltstart: Pending PDF aus Share Extension
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.checkPendingPdf()
        }
    }

    func scene(_ scene: UIScene,
               openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.handleAnyURL(url)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkPendingPdf()
        }
    }

    private func handleAnyURL(_ url: URL) {
        print("🔗 handleAnyURL: \(url.absoluteString)")

        if url.isFileURL && url.pathExtension.lowercased() == "pdf" {
            sendPdfToFlutter(path: url.path, fileName: url.lastPathComponent)
            return
        }

        if url.scheme == "optimes" {
            let urlString = url.absoluteString

            if urlString == "optimes://shared-pdf" {
                checkPendingPdf()
                return
            }

            guard let controller = window?.rootViewController as? FlutterViewController else { return }
            let channel = FlutterMethodChannel(
                name: "de.marcel.optimes/navigation",
                binaryMessenger: controller.binaryMessenger
            )
            if urlString.contains("/note/") {
                let dateKey = url.pathComponents.last ?? ""
                channel.invokeMethod("openFromWidget", arguments: [
                    "path": "dienstplan",
                    "url": urlString,
                    "noteDate": dateKey
                ])
            } else {
                channel.invokeMethod("openFromWidget", arguments: [
                    "path": url.host ?? url.path,
                    "url": urlString
                ])
            }
        }
    }

    private func checkPendingPdf() {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.de.marcel.optimes") else {
            print("❌ Kein App Group Container")
            return
        }
        let pdfURL = containerURL.appendingPathComponent("pending_dienstplan.pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            print("ℹ️ Keine pending PDF")
            return
        }

        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
        let fileName = defaults?.string(forKey: "PendingPdfName") ?? "dienstplan.pdf"

        print("✅ Pending PDF gefunden: \(pdfURL.path)")
        sendPdfToFlutter(path: pdfURL.path, fileName: fileName)

        try? FileManager.default.removeItem(at: pdfURL)
        defaults?.removeObject(forKey: "PendingPdfName")
        defaults?.synchronize()
    }

    private func sendPdfToFlutter(path: String, fileName: String) {
        print("📤 Sende PDF an Flutter: \(fileName)")
        guard let controller = window?.rootViewController as? FlutterViewController else {
            print("❌ Kein FlutterViewController")
            return
        }
        let channel = FlutterMethodChannel(
            name: "de.marcel.optimes/navigation",
            binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("openSharedPdf", arguments: [
            "path": path,
            "fileName": fileName
        ])
    }
}