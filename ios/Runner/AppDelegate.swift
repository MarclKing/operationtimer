import UIKit
import Flutter
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        if let controller = window?.rootViewController as? FlutterViewController {
            // ── Widget Channel ──────────────────────────────────────────
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

            // ── Navigation Channel (Widget → App) ───────────────────────
            let navChannel = FlutterMethodChannel(
                name: "de.marcel.optimes/navigation",
                binaryMessenger: controller.binaryMessenger
            )
            // Wird von Flutter selbst als Handler registriert – hier nur deklarieren
            _ = navChannel
        }

        return result
    }

    // ── Widget-Tap → App öffnen ─────────────────────────────────────────────
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        print("🔗 URL erhalten: \(url.absoluteString)")
        if url.scheme == "optimes" {
    if let controller = window?.rootViewController as? FlutterViewController {
        let navChannel = FlutterMethodChannel(
            name: "de.marcel.optimes/navigation",
            binaryMessenger: controller.binaryMessenger
        )
        let urlString = url.absoluteString
        let path = url.host ?? url.path

        // PDF aus Share Extension
        if urlString == "optimes://shared-pdf" {
    let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
    let pdfBytes = defaults?.data(forKey: "SharedPdfBytes")
    let pdfName = defaults?.string(forKey: "SharedPdfName") ?? "dienstplan.pdf"
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let bytes = pdfBytes, !bytes.isEmpty {
            // Bytes als Array übergeben ist zu groß für MethodChannel
            // → erst in shared container als Datei schreiben
            let containerURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.de.marcel.optimes")!
                .appendingPathComponent("shared_dienstplan.pdf")
            try? bytes.write(to: containerURL)
            
            navChannel.invokeMethod("openSharedPdf", arguments: [
                "path": containerURL.path,
                "fileName": pdfName
            ])
        }
        defaults?.removeObject(forKey: "SharedPdfBytes")
        defaults?.removeObject(forKey: "SharedPdfName")
        defaults?.synchronize()
    }
    return true
}
        return super.application(app, open: url, options: options)
    }
}