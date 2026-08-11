import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedPdf()
    }

    func handleSharedPdf() {
        print("🆕🆕🆕 NEUER BUILD AKTIV 🆕🆕🆕")
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completeRequest()
            return
        }

        let pdfType = "com.adobe.pdf"

        guard let attachment = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(pdfType) }) else {
            completeRequest()
            return
        }

        // NEU: open() wird JETZT SOFORT ausgelöst, sobald klar ist, dass ein
        // PDF geteilt wird — statt erst NACH dem asynchronen Laden+Speichern
        // der Datei. Vermutung: iOS knüpft die animierte App-Wechsel-Transition
        // an zeitliche Nähe zur Nutzerinteraktion. Je mehr asynchrone Arbeit
        // vorher passiert, desto eher überspringt iOS die Animation (liefert
        // aber weiterhin success: true, da die technische Anfrage trotzdem
        // durchgeht). Datei-Verarbeitung läuft jetzt PARALLEL dazu.
        if let appURL = URL(string: "optimes://shared-pdf") {
            DispatchQueue.main.async {
                self.extensionContext?.open(appURL) { success in
                    if success {
                        print("✅ Share Extension: extensionContext.open() ERFOLGREICH (früh ausgelöst)")
                    } else {
                        print("❌ Share Extension: extensionContext.open() fehlgeschlagen")
                    }
                }
            }
        } else {
            print("❌ Share Extension: Konnte optimes://shared-pdf URL nicht erstellen")
        }

        attachment.loadItem(forTypeIdentifier: pdfType, options: nil) { data, error in
            var pdfData: Data?
            var fileName: String = "dienstplan.pdf"

            if let url = data as? URL {
                fileName = url.lastPathComponent
                pdfData = try? Data(contentsOf: url)
            } else if let rawData = data as? Data {
                pdfData = rawData
            }

            if let bytes = pdfData, !bytes.isEmpty {
                let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
                let containerURL = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: "group.de.marcel.optimes")

                if let containerURL {
                    let pendingURL = containerURL.appendingPathComponent("pending_dienstplan.pdf")
                    do {
                        try FileManager.default.createDirectory(
                            at: containerURL,
                            withIntermediateDirectories: true
                        )
                        try bytes.write(to: pendingURL, options: .atomic)
                        defaults?.set(fileName, forKey: "PendingPdfName")
                        defaults?.synchronize()
                    } catch {
                        print("❌ Share Extension: PDF konnte nicht im App-Group-Container gespeichert werden: \(error)")
                    }
                } else {
                    print("❌ Share Extension: Kein App-Group-Container verfügbar")
                }
            }

            // NEU: completeRequest() wird jetzt immer erst NACH dem
            // Datei-Schreiben aufgerufen (unabhängig vom open()-Ergebnis) —
            // damit die Extension nicht vorzeitig beendet wird, bevor die
            // Datei tatsächlich im App-Group-Container liegt.
            self.completeRequest()
        }
    }

    func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}