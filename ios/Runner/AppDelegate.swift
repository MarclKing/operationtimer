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
            let channel = FlutterMethodChannel(
                name: "de.marcel.optimes/widget",
                binaryMessenger: controller.binaryMessenger
            )
            channel.setMethodCallHandler { call, result in
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

        return result
    }

    // SEPARATE Methode – nicht verschachtelt!
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if url.scheme == "optimes" {
    if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
            name: "de.marcel.optimes/navigation",
            binaryMessenger: controller.binaryMessenger
        )
        let path = url.host ?? ""          // z.B. "dienstplan"
        let fullPath = url.absoluteString  // z.B. "optimes://dienstplan/note/2026-06-08"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            channel.invokeMethod("openFromWidget", arguments: [
                "path": path,
                "url": fullPath
            ])
        }
    }
    return true
}
        return super.application(app, open: url, options: options)
    }
}