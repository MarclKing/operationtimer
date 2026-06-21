import UIKit
import Flutter
import WidgetKit
import UserNotifications  // ← NEU: für lokale Notifications

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
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        if let controller = window?.rootViewController as? FlutterViewController {
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

        return result
    }

    // ── PDF aus App Group Container (Share Extension) ───────────────────────
    private func checkAndSendPendingPdf(navChannel: FlutterMethodChannel) {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.de.marcel.optimes") else {
            return
        }
        let pdfURL = containerURL.appendingPathComponent("pending_dienstplan.pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path) else { return }

        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
        let fileName = defaults?.string(forKey: "PendingPdfName") ?? "dienstplan.pdf"

        navChannel.invokeMethod("openSharedPdf", arguments: [
            "path": pdfURL.path,
            "fileName": fileName
        ])

        try? FileManager.default.removeItem(at: pdfURL)
        defaults?.removeObject(forKey: "PendingPdfName")
        defaults?.synchronize()
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

    // ── Ältere iOS-Variante (sourceApplication) ─────────────────────────────
    override func application(
        _ application: UIApplication,
        open url: URL,
        sourceApplication: String?,
        annotation: Any
    ) -> Bool {
        if url.isFileURL && url.pathExtension.lowercased() == "pdf" {
            handleInboxPdf(url: url)
            return true
        }
        return super.application(application, open: url, sourceApplication: sourceApplication, annotation: annotation)
    }
}