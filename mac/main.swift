// Bewerbungen – nativer macOS-Wrapper um web/index.html.
// Zeigt die Oberfläche in einem echten App-Fenster und speichert alle Daten in
// ~/Library/Application Support/Bewerbungen/bewerbungen.json (atomar, mit Backup).

import AppKit
import WebKit

// MARK: - Ablage auf der Festplatte

enum Store {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Bewerbungen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var file: URL { folder.appendingPathComponent("bewerbungen.json") }
    static var backup: URL { folder.appendingPathComponent("bewerbungen.backup.json") }
    static func read() -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? "[]"
    }

    /// Schreibt atomar und hebt die vorherige Fassung als Backup auf.
    static func write(_ json: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: file, to: backup)
        }
        try? json.data(using: .utf8)?.write(to: file, options: .atomic)
    }
}

// MARK: - Fenster & Web-Ansicht

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!

    func applicationDidFinishLaunching(_ note: Notification) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "bewerbungen")

        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")   // Hintergrund kommt aus dem CSS
        if #available(macOS 13.3, *) { web.isInspectable = true }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Bewerbungen"
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 380, height: 480)
        window.contentView = web
        window.setFrameAutosaveName("BewerbungenMain")
        window.center()
        window.makeKeyAndOrderFront(nil)

        buildMenu()

        guard let page = Bundle.main.url(forResource: "index", withExtension: "html") else {
            fail("index.html fehlt im App-Bundle.")
            return
        }
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Links zu Stellenanzeigen im Standardbrowser öffnen statt im App-Fenster.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// target="_blank" öffnet kein zweites App-Fenster, sondern den Browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // Gespeicherte Daten hereinreichen, sobald die Oberfläche geladen ist.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hydrate(Store.read(), function: "__hydrate")
        if CommandLine.arguments.contains("--selftest") { selfTest() }
    }

    /// Prüft ohne Zutun: Daten kommen an, Tabelle und Diagramm bauen sich auf, Speichern landet in der Datei.
    private func selfTest() {
        let probe = """
        document.querySelector('#btnChart').click();
        await new Promise(r => setTimeout(r, 1500));   // Logos kommen übers Netz
        return JSON.stringify({
          native: native, items: items.length,
          zeilen: document.querySelectorAll('tbody tr').length,
          diagramm_stroeme: document.querySelectorAll('#sankey path.link').length,
          diagramm_knoten: document.querySelectorAll('#sankey g.nodes rect').length
        });
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.web.callAsyncJavaScript(probe, in: nil, in: .page) { outcome in
                let result = try? outcome.get()
                print("OBERFLÄCHE:", result as? String ?? String(describing: outcome))
                self.web.evaluateJavaScript("items.push(normalize({company:'Selbsttest',role:'Prüfung'})); save(); items.length") { count, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        let saved = Store.read()
                        print("NACH SPEICHERN: items=\(count ?? "?") datei_enthält_neuen_eintrag=\(saved.contains("Selbsttest"))")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func hydrate(_ json: String, function: String) {
        let b64 = Data(json.utf8).base64EncodedString()
        web.evaluateJavaScript("window.\(function)?.('\(b64)')")
    }

    // MARK: Nachrichten aus der Oberfläche

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "save":
            if let data = body["data"] as? String { Store.write(data) }

        case "export":
            let panel = NSSavePanel()
            panel.nameFieldStringValue = (body["name"] as? String) ?? "bewerbungen.json"
            panel.allowedContentTypes = [.json]
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url,
                      let data = (body["data"] as? String)?.data(using: .utf8) else { return }
                try? data.write(to: url, options: .atomic)
            }

        case "import":
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url,
                      let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                self?.hydrate(text, function: "__imported")
            }

        default:
            break
        }
    }

    private func fail(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Bewerbungen konnte nicht starten"
        alert.informativeText = text
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }

    // MARK: Menüleiste (u. a. damit Kopieren/Einfügen in Feldern funktioniert)

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Über Bewerbungen", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ordner mit Daten zeigen", action: #selector(revealData), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Bewerbungen ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Bewerbungen beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "Fenster")
        win.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Neu laden", action: #selector(reload), keyEquivalent: "r")
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    @objc private func revealData() {
        NSWorkspace.shared.activateFileViewerSelecting([Store.file])
    }

    @objc private func reload() {
        web.reload()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
