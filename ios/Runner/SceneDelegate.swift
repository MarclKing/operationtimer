import UIKit
import Flutter

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        // URL beim Kaltstart (App war komplett geschlossen)
        if let urlContext = connectionOptions.urlContexts.first {
            handleURL(urlContext.url)
        }
    }

    func scene(_ scene: UIScene,
               openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // URL wenn App bereits läuft (Hintergrund oder Vordergrund)
        if let urlContext = URLContexts.first {
            handleURL(urlContext.url)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "optimes" else { return }

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }

        let channel = FlutterMethodChannel(
            name: "de.marcel.optimes/navigation",
            binaryMessenger: controller.binaryMessenger
        )

        let urlString = url.absoluteString
        let host = url.host ?? ""

        // Kaltstart braucht mehr Zeit
        let isBackground = UIApplication.shared.applicationState == .background
        let delay: Double = isBackground ? 1.5 : 0.4

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            channel.invokeMethod("openFromWidget", arguments: [
                "path": host,
                "url": urlString
            ])
        }
    }
}