import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedPdf()
    }

    func handleSharedPdf() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completeRequest()
            return
        }

        let pdfType = "com.adobe.pdf"

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(pdfType) {
                attachment.loadItem(forTypeIdentifier: pdfType, options: nil) { data, error in
                    var fileURL: URL?

                    if let url = data as? URL {
                        fileURL = url
                    } else if let rawData = data as? Data {
                        let tmp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("shared_dienstplan.pdf")
                        try? rawData.write(to: tmp)
                        fileURL = tmp
                    }

                    if let url = fileURL {
                        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
                        defaults?.set(url.path, forKey: "SharedPdfPath")
                        defaults?.synchronize()

                        if let appURL = URL(string: "optimes://shared-pdf") {
                            _ = self.openURL(appURL)
                        }
                    }

                    self.completeRequest()
                }
                return
            }
        }
        completeRequest()
    }

    func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    @objc func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let app = responder as? UIApplication {
                return app.perform(#selector(openURL(_:)), with: url) != nil
            }
            responder = responder?.next
        }
        return false
    }
}
