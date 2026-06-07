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

    // MethodChannel nach dem Plugin-Register registrieren
    let registrar = self.registrar(forPlugin: "WidgetChannel")
    let channel = FlutterMethodChannel(
      name: "de.marcel.optimes/widget",
      binaryMessenger: registrar!.messenger()
    )

    channel.setMethodCallHandler { call, result in
      if call.method == "updateSchedule" {
        if let args = call.arguments as? [String: Any],
           let json = args["json"] as? String {
          let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
          defaults?.set(json, forKey: "schedule_entries")
          defaults?.synchronize()
          WidgetCenter.shared.reloadAllTimelines()
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}