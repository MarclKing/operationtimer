import UIKit
import Flutter
import WidgetKit
import UserNotifications  // ← NEU: für lokale Notifications
import workmanager        // NEU

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // ── NEU: Lokale Notification-Berechtigung anfordern ──
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            ) { granted, error in
                if granted {
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                }
            }
        } else {
            let settings = UIUserNotificationSettings(types: [.alert, .sound, .badge], categories: nil)
            application.registerUserNotificationSettings(settings)
            application.registerForRemoteNotifications()
        }

        GeneratedPluginRegistrant.register(with: self)

        // NEU: Zwingend erforderlich für workmanager auf iOS — Apple verlangt,
        // dass jede BGTaskScheduler-Identifier-Registrierung synchron HIER
        // passiert, bevor didFinishLaunchingWithOptions zurückkehrt. Ohne das
        // stürzt die App beim ersten registerPeriodicTask()-Aufruf aus main.dart ab.
        WorkmanagerPlugin.registerTask(withIdentifier: "de.marcel.optimes.appleCalendarSync")

        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        DispatchQueue.main.async {
        if let controller = self.window?.rootViewController as? FlutterViewController {
            let widgetChannel = FlutterMethodChannel(
                name: "de.marcel.optimes/widget",
                binaryMessenger: controller.binaryMessenger
            )
            widgetChannel.setMethodCallHandler { call, result in
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
                } else if call.method == "updateCalendarEvents" {
                    // Datenquelle für die beiden neuen Kalender-Widgets.
                    if let args = call.arguments as? [String: Any] {
                        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
                        if let json = args["json"] as? String {
                            defaults?.set(json, forKey: "calendar_widget_events")
                        }
                        if let readOnly = args["readOnly"] as? Bool { // NEU
                            defaults?.set(readOnly, forKey: "read_only_mode")
                        }
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

            let navChannel = FlutterMethodChannel(
                name: "de.marcel.optimes/navigation",
                binaryMessenger: controller.binaryMessenger
            )
            _ = navChannel

            // Beim App-Start prüfen ob eine PDF aus Share Extension wartet
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.checkAndSendPendingPdf(navChannel: navChannel)
            }
        }
        }

        return result
    }

    // ── PDF aus App Group Container (Share Extension) ───────────────────────
    //
    // WICHTIG: Diese Methode wird bei einem Kaltstart über die Share
    // Extension ZWEIMAL aufgerufen — einmal aus didFinishLaunchingWithOptions
    // (asyncAfter 1.0s) und einmal aus application(_:open:), weil die
    // Extension jetzt korrekt "optimes://shared-pdf" öffnet (siehe
    // ShareViewController). Beide Aufrufe liefen bisher fast parallel und
    // konkurrierten um dieselbe Datei: einer sendet+löscht, der andere findet
    // sie danach nicht mehr → "PathNotFoundException". Fix: die Datei wird
    // ATOMAR verschoben, sobald sie entdeckt wird — nur der Aufruf, der die
    // Datei zuerst verschiebt, verarbeitet sie; der andere bricht sauber ab.
    func checkAndSendPendingPdf(navChannel: FlutterMethodChannel, retriesLeft: Int = 6) {
    guard let containerURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.de.marcel.optimes") else {
        return
    }
    let pdfURL = containerURL.appendingPathComponent("pending_dienstplan.pdf")
    let workingURL = containerURL.appendingPathComponent("pending_dienstplan_processing.pdf")

    do {
        if FileManager.default.fileExists(atPath: workingURL.path) {
            try? FileManager.default.removeItem(at: workingURL)
        }
        try FileManager.default.moveItem(at: pdfURL, to: workingURL)
    } catch {
        // NEU: Die Share Extension schreibt die Datei jetzt PARALLEL zum
        // open()-Aufruf, nicht mehr davor. Die Datei kann daher beim ersten
        // Check noch fehlen — kurz erneut versuchen statt sofort aufzugeben.
        if retriesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkAndSendPendingPdf(navChannel: navChannel, retriesLeft: retriesLeft - 1)
            }
        }
        return
    }

        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
        let fileName = defaults?.string(forKey: "PendingPdfName") ?? "dienstplan.pdf"

        var didCleanup = false
        let cleanup = {
            guard !didCleanup else { return }
            didCleanup = true
            try? FileManager.default.removeItem(at: workingURL)
            defaults?.removeObject(forKey: "PendingPdfName")
            defaults?.synchronize()
        }

        navChannel.invokeMethod("openSharedPdf", arguments: [
            "path": workingURL.path,
            "fileName": fileName
        ]) { _ in
            cleanup()
        }

        // Fallback: falls die Dart-Seite aus irgendeinem Grund nie antwortet
        // (z.B. Hot-Reload währenddessen), spätestens nach 10s aufräumen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            cleanup()
        }
    }

    // ── PDF aus Dokument-Inbox ("Öffnen mit" / direkt geteilt) ─────────────
    private func handleInboxPdf(url: URL) {
        guard let controller = window?.rootViewController as? FlutterViewController else { return }
        let navChannel = FlutterMethodChannel(
            name: "de.marcel.optimes/navigation",
            binaryMessenger: controller.binaryMessenger
        )
        let fileName = url.lastPathComponent
        print("📄 Inbox PDF: \(url.path)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            navChannel.invokeMethod("openSharedPdf", arguments: [
                "path": url.path,
                "fileName": fileName
            ])
        }
    }

    // ── URL-Handler (Widget-Tap + Share Extension URL + Dokument-Inbox) ─────
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        print("🔗 URL erhalten: \(url.absoluteString)")

        // PDF direkt geöffnet über "Öffnen mit" / Share Sheet
        if url.isFileURL && url.pathExtension.lowercased() == "pdf" {
            handleInboxPdf(url: url)
            return true
        }

        if url.scheme == "optimes" {
            if let controller = window?.rootViewController as? FlutterViewController {
                let navChannel = FlutterMethodChannel(
                    name: "de.marcel.optimes/navigation",
                    binaryMessenger: controller.binaryMessenger
                )
                let urlString = url.absoluteString

                // PDF aus Share Extension
                if urlString == "optimes://shared-pdf" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.checkAndSendPendingPdf(navChannel: navChannel)
                    }
                    return true
                }

                // Widget-Navigation
                let path = url.host ?? url.path
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navChannel.invokeMethod("openFromWidget", arguments: [
                        "url": urlString,
                        "path": path
                    ])
                }
            }
            return true
        }

        return super.application(app, open: url, options: options)
    }
}