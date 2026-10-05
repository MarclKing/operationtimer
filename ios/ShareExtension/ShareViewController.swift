import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedContent()
    }

    // MARK: - Einstieg

    func handleSharedContent() {
        print("🆕🆕🆕 NEUER BUILD AKTIV 🆕🆕🆕")

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }

        guard !items.isEmpty else {
            completeRequest()
            return
        }

        // 1. PDF (Dienstplan) — wie bisher
        let pdfType = "com.adobe.pdf"
        if let pdf = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(pdfType) }) {
            handleSharedPdf(attachment: pdf, typeIdentifier: pdfType)
            return
        }

        // 2. NEU: Text / Link (z. B. aus Google Maps oder Apple Maps)
        handleSharedText(items: items, attachments: attachments)
    }

    // MARK: - PDF (unverändert)

    func handleSharedPdf(attachment: NSItemProvider, typeIdentifier pdfType: String) {
        // open() wird JETZT SOFORT ausgelöst, sobald klar ist, dass ein
        // PDF geteilt wird — statt erst NACH dem asynchronen Laden+Speichern
        // der Datei. Datei-Verarbeitung läuft PARALLEL dazu.
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
                let defaults = UserDefaults(suiteName: AppGroup.id)
                let containerURL = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)

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

            // completeRequest() erst NACH dem Datei-Schreiben, damit die Extension
            // nicht beendet wird, bevor die Datei im App-Group-Container liegt.
            self.completeRequest()
        }
    }

    // MARK: - NEU: Text / Link

    func handleSharedText(items: [NSExtensionItem], attachments: [NSItemProvider]) {
        let urlType = "public.url"
        let textType = "public.plain-text"

        let lock = NSLock()
        var urls: [String] = []
        var texts: [String] = []
        let group = DispatchGroup()

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(urlType) {
                group.enter()
                loadString(from: attachment, type: urlType) { value in
                    if let v = value {
                        lock.lock(); urls.append(v); lock.unlock()
                    }
                    group.leave()
                }
            }
            if attachment.hasItemConformingToTypeIdentifier(textType) {
                group.enter()
                loadString(from: attachment, type: textType) { value in
                    if let v = value {
                        lock.lock(); texts.append(v); lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }

            let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            // Nur echte Web-Links (keine file://-URLs, z. B. vCard-Anhang von Apple Maps)
            let url = urls.map(trim).first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }

            // Text: vCard-Inhalte ignorieren, sonst Fallback auf attributedContentText
            var text = texts.map(trim).first { !$0.isEmpty && !$0.uppercased().hasPrefix("BEGIN:VCARD") }
            if text == nil {
                text = items.compactMap { $0.attributedContentText?.string }.map(trim).first { !$0.isEmpty }
            }

            var parts: [String] = []
            if let t = text { parts.append(t) }
            if let u = url, !parts.joined(separator: "\n").contains(u) { parts.append(u) }
            let combined = parts.joined(separator: "\n")

            guard !combined.isEmpty else {
                print("❌ Share Extension: Weder Text noch Link gefunden")
                self.completeRequest()
                return
            }

            let defaults = UserDefaults(suiteName: AppGroup.id)
            defaults?.set(combined, forKey: "PendingSharedText")
            defaults?.synchronize()

            // App öffnen, completeRequest() erst danach
            self.openMainApp(urlString: "optimes://shared-text") {
                self.completeRequest()
            }
        }
    }

    private func loadString(from attachment: NSItemProvider, type: String, completion: @escaping (String?) -> Void) {
        attachment.loadItem(forTypeIdentifier: type, options: nil) { data, _ in
            if let url = data as? URL {
                completion(url.absoluteString)
            } else if let s = data as? String {
                completion(s)
            } else if let a = data as? NSAttributedString {
                completion(a.string)
            } else if let d = data as? Data {
                completion(String(data: d, encoding: .utf8))
            } else {
                completion(nil)
            }
        }
    }

        private func openMainApp(urlString: String, completion: @escaping () -> Void) {
        guard let appURL = URL(string: urlString), let ctx = extensionContext else {
            completion()
            return
        }
        DispatchQueue.main.async {
            // Weg 1: offizielle API (in Share Extensions oft wirkungslos)
            ctx.open(appURL) { success in
                if success {
                    print("✅ Share Extension: open(\(urlString)) erfolgreich")
                    completion()
                    return
                }
                // Weg 2: über die Responder-Kette an UIApplication
                print("⚠️ Share Extension: extensionContext.open fehlgeschlagen, versuche Responder-Kette")
                let ok = self.openViaResponderChain(appURL)
                print(ok
                      ? "✅ Share Extension: Responder-Kette hat open(\(urlString)) ausgelöst"
                      : "❌ Share Extension: Responder-Kette fehlgeschlagen")
                // Kurz warten, damit iOS die Anfrage abarbeitet, bevor die Extension schließt
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion() }
            }
        }
    }

    @discardableResult
    private func openViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                if #available(iOS 18.0, *) {
                    // Ab iOS 18 funktioniert nur noch die Variante mit options/completionHandler
                    let sel = NSSelectorFromString("openURL:options:completionHandler:")
                    guard application.responds(to: sel), let imp = application.method(for: sel) else { return false }
                    typealias OpenFn = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                    let fn = unsafeBitCast(imp, to: OpenFn.self)
                    fn(application, sel, url as NSURL, [:] as NSDictionary, nil)
                    return true
                } else {
                    let sel = NSSelectorFromString("openURL:")
                    guard application.responds(to: sel) else { return false }
                    _ = application.perform(sel, with: url)
                    return true
                }
            }
            responder = current.next
        }
        return false
    }

    func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}