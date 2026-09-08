// zapply – nativer macOS-Wrapper um web/index.html.
// Zeigt die Oberfläche in einem echten App-Fenster und speichert alle Daten in
// ~/Library/Application Support/Bewerbungen/bewerbungen.json (atomar, mit Backup).

import AppKit
import WebKit

// MARK: - Ablage auf der Festplatte

enum Store {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Der Ordner behält seinen Namen, damit die Daten beim Umbenennen liegen bleiben.
        let dir = base.appendingPathComponent("Bewerbungen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var file: URL { folder.appendingPathComponent("bewerbungen.json") }
    static var backup: URL { folder.appendingPathComponent("bewerbungen.backup.json") }
    static var config: URL { folder.appendingPathComponent("config.json") }

    /// Adresse der gemeinsamen Ablage (Worker-URL), falls eingerichtet.
    static var syncURL: String {
        get {
            guard let data = try? Data(contentsOf: config),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return "" }
            return (obj["syncURL"] as? String) ?? ""
        }
        set {
            let obj = ["syncURL": newValue]
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
                try? data.write(to: config, options: .atomic)
            }
        }
    }

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

/// Der Name der App – im Fenster, im Menü und in Meldungen.
let MARKE = "zapply"

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var usingRemote = false
    var offlineFallback = false

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
        window.title = MARKE
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 380, height: 480)
        window.contentView = web
        window.setFrameAutosaveName("BewerbungenMain")
        window.center()
        window.makeKeyAndOrderFront(nil)

        buildMenu()

        loadInterface()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Mit eingerichteter Synchronisierung wird die gemeinsame Ansicht geladen,
    /// ohne (oder wenn sie nicht erreichbar ist) die eingebaute Seite mit der lokalen Datei.
    private func loadInterface() {
        let sync = Store.syncURL
        if !sync.isEmpty, let url = URL(string: sync) {
            usingRemote = true
            window.title = MARKE
            web.load(URLRequest(url: url))
        } else {
            usingRemote = false
            loadBundled()
        }
    }

    private func loadBundled() {
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html") else {
            fail("index.html fehlt im App-Bundle.")
            return
        }
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    /// Kein Netz? Dann die eingebaute Seite mit dem letzten bekannten Stand zeigen –
    /// und merken, dass ein neuer Versuch nötig ist.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard usingRemote else { return }
        usingRemote = false
        offlineFallback = true
        window.title = "\(MARKE) – offline"
        loadBundled()
    }

    /// Bei jedem Wechsel ins Fenster erneut versuchen, den gemeinsamen Stand zu laden.
    func applicationDidBecomeActive(_ note: Notification) {
        guard offlineFallback, !Store.syncURL.isEmpty else { return }
        offlineFallback = false
        window.title = MARKE
        loadInterface()
    }

    /// Links zu Stellenanzeigen im Standardbrowser öffnen statt im App-Fenster.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let ownHost = URL(string: Store.syncURL)?.host
        if let url = action.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != ownHost {
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
        if !usingRemote { hydrate(Store.read(), function: "__hydrate") }
        if CommandLine.arguments.contains("--selftest") { selfTest() }
    }

    /// Prüft ohne Zutun: Daten kommen an, Tabelle und Diagramm bauen sich auf, Speichern landet in der Datei.
    private func selfTest() {
        let probe = """
        // Zuerst die Übersicht: nur dort hat die Tabelle eine Ausdehnung
        setView('list');
        await new Promise(r => setTimeout(r, 1500));   // Logos kommen übers Netz
        const tabelle = {
          zeilen: document.querySelectorAll('#viewList tbody tr').length,
          logos_versucht: document.querySelectorAll('.mark img').length,
          logos_geladen: document.querySelectorAll('.mark.has-logo').length,
          link: linkProbe(),
        };
        setView('stats');
        await new Promise(r => setTimeout(r, 400));
        return JSON.stringify({
          native: native, items: items.length,
          ...tabelle,
          diagramm_stroeme: document.querySelectorAll('#sankey path.link').length,
          diagramm_knoten: document.querySelectorAll('#sankey g.nodes rect').length,
          verzeichnis: typeof COMPANY_DIR !== 'undefined' ? COMPANY_DIR.length : 0,
          statistik_karten: document.querySelectorAll('#board .bcard').length,
          saeulen: saeulenProbe(),
          klickbar: document.querySelectorAll('#board .klick').length
                  + ' · Hinweise ' + document.querySelectorAll('#board [data-tip]').length,
          fenster_fehlend: fehlendeFenster(),
          verlauf: await verlaufProbe(),
          passwortknopf: (() => {
            const b = document.querySelector('#btnPass');
            if(!b) return 'Knopf fehlt';
            const an = getComputedStyle(b).display !== 'none';
            return account ? (an ? 'sichtbar' : 'fehlt bei angemeldetem Konto')
                           : (an ? 'sichtbar ohne Anmeldung' : 'aus, weil abgemeldet');
          })()
        });

        // Jedes Fenster, das die Oberfläche öffnen kann, muss auch im Dokument stehen
        function fehlendeFenster(){
          return ['#ovForm','#ovHistory','#ovShare','#ovInvite','#ovConfirm','#ovPass']
            .filter(sel => !document.querySelector(sel)).join(' ') || 'keine';
        }
        // Alle Monatssäulen müssen auf derselben Grundlinie stehen
        function saeulenProbe(){
          const spuren = [...document.querySelectorAll('#board .month .mtrack')];
          if(!spuren.length) return 'keine';
          const unten = spuren.map(s => Math.round(s.getBoundingClientRect().bottom));
          const spanne = Math.max(...unten) - Math.min(...unten);
          return spuren.length + ' Säulen, Grundlinie ' + (spanne <= 1 ? 'bündig' : 'um ' + spanne + ' px versetzt');
        }
        // Der Pfeil zur Ausschreibung: vorhanden, groß genug zum Klicken, echtes Ziel
        function linkProbe(){
          if(typeof linkOeffnen !== 'function') return 'linkOeffnen fehlt';
          const a = document.querySelector('tbody .extlink');
          if(!a) return 'kein Eintrag mit Link';
          const b = a.getBoundingClientRect();
          const masse = Math.round(b.width) + '×' + Math.round(b.height);
          if(!a.href.toLowerCase().startsWith('http')) return 'Ziel unbrauchbar: ' + a.getAttribute('href');
          return (b.width >= 12 && b.height >= 12 ? 'Pfeil ' : 'Pfeil zu klein ') + masse;
        }
        // Verlauf des ersten Eintrags wirklich öffnen und nachsehen, ob er sichtbar wird
        async function verlaufProbe(){
          if(!items.length) return 'kein Eintrag';
          openHistory(items[0]);
          const ov = document.querySelector('#ovHistory');
          if(!ov) return 'Fenster fehlt';
          await new Promise(r => setTimeout(r, 400));
          // Nicht die Deckkraft prüfen: in einem unsichtbaren Fenster läuft die Blende nicht.
          const stil = getComputedStyle(ov);
          const kasten = ov.querySelector('.sheet').getBoundingClientRect();
          const sichtbar = ov.classList.contains('show') && stil.display !== 'none'
                        && stil.pointerEvents === 'auto' && kasten.width > 200 && kasten.height > 200;
          const stationen = document.querySelectorAll('#histList .tl').length;
          document.querySelectorAll('.overlay.show').forEach(o => o.classList.remove('show'));
          document.body.style.overflow = '';
          return sichtbar ? stationen + ' Stationen sichtbar' : 'unsichtbar';
        }
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          self.breiteProbe(320) { winzig in
            print("WINZIG:", winzig)
            self.breiteProbe(390) { schmal in
            print("SCHMAL:", schmal)
            self.breiteProbe(1280) { breit in
              print("BREIT:", breit)
            self.web.callAsyncJavaScript(probe, in: nil, in: .page) { outcome in
                let result = try? outcome.get()
                print("OBERFLÄCHE:", result as? String ?? String(describing: outcome))
                self.posterPruefen {
                  // Nur schreiben, wenn wirklich Daten da sind: sonst würde der Test
                  // eine leere Liste über die gespeicherten Bewerbungen legen.
                  let bereit = "(() => { const g = document.querySelector('#gate'); return (!g || g.hidden) && items.length > 0; })()"
                  self.web.evaluateJavaScript(bereit) { ok, _ in
                    guard (ok as? Bool) == true else {
                        print("SCHREIBTEST ÜBERSPRUNGEN: nicht angemeldet oder keine Daten")
                        NSApp.terminate(nil)
                        return
                    }
                  self.web.evaluateJavaScript("items.push(normalize({company:'Selbsttest',role:'Prüfung'})); save(); items.length") { count, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        let saved = Store.read()
                        print("NACH SPEICHERN: items=\(count ?? "?") datei_enthält_neuen_eintrag=\(saved.contains("Selbsttest"))")
                        // Der Test räumt hinter sich auf – auch in der gemeinsamen Ablage
                        self.web.evaluateJavaScript("items = items.filter(i => i.company !== 'Selbsttest'); save(); items.length") { rest, _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                let danach = Store.read()
                                print("AUFGERÄUMT: items=\(rest ?? "?") testeintrag_weg=\(!danach.contains("Selbsttest"))")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                  }
                  }
                }
            }
            }
            }
          }
        }
    }

    /// Setzt das Fenster auf eine Breite und misst, wie sich die Oberfläche ordnet.
    /// So fällt auf, wenn auf dem Handy Reihen umbrechen oder etwas seitlich hinausläuft.
    private func breiteProbe(_ breite: CGFloat, dann: @escaping (String) -> Void) {
        var rahmen = window.frame
        rahmen.size = NSSize(width: breite, height: 900)
        window.setFrame(rahmen, display: true)
        let js = """
        // Gemessen wird die Übersicht: in der Statistik-Ansicht ist die Liste verborgen
        if(typeof setView === 'function') setView('list');
        // Warten, bis die Liste wirklich steht – sonst misst man den leeren Aufbau
        for(let i = 0; i < 40; i++){
          const bereit = document.querySelector('#chips')?.children.length
                      || !document.querySelector('#gate')?.hidden;
          if(bereit) break;
          await new Promise(r => setTimeout(r, 100));
        }
        await new Promise(r => setTimeout(r, 400));
        // Reihen zählen über Umbrüche: eine neue Reihe beginnt, wenn ein Kind
        // weiter links sitzt als sein Vorgänger. Leere Kinder bleiben außen vor.
        const reihen = el => {
          if(!el) return 0;
          const kinder = [...el.children]
            .map(k => k.getBoundingClientRect())
            .filter(b => b.width > 0 && b.height > 0);
          if(!kinder.length) return 0;
          let n = 1, links = kinder[0].left;
          for(const b of kinder.slice(1)){
            if(b.left <= links + 0.5) n++;
            links = b.left;
          }
          return n;
        };
        const sichtbar = sel => {
          const k = document.querySelector(sel);
          return !!k && getComputedStyle(k).display !== 'none';
        };
        // Wer läuft seitlich hinaus? Die drei breitesten Übeltäter benennen
        // Was in einer schiebbaren Reihe steckt, darf hinausragen – das ist gewollt
        const inSchiebereihe = k => {
          for(let e = k.parentElement; e; e = e.parentElement){
            const ux = getComputedStyle(e).overflowX;
            if(ux === 'auto' || ux === 'scroll') return true;
          }
          return false;
        };
        const raus = [...document.querySelectorAll('body *')]
          .map(k => ({k, b: k.getBoundingClientRect()}))
          .filter(({k, b}) => b.width > 0 && b.right > innerWidth + 1
                           && getComputedStyle(k).position !== 'fixed' && !inSchiebereihe(k))
          .sort((a, b) => b.b.right - a.b.right)
          .slice(0, 3)
          .map(({k, b}) => `${k.tagName.toLowerCase()}${k.id ? '#' + k.id : (k.className ? '.' + String(k.className).split(' ')[0] : '')}`
                         + ` bis ${Math.round(b.right)}`);
        return JSON.stringify({
          fenster: innerWidth,
          ueberlauf: document.documentElement.scrollWidth - innerWidth,
          raus: raus.length ? raus : 'nichts',
          kopfreihen: reihen(document.querySelector('.top-actions')),
          kartenkopf: reihen(document.querySelector('.card-head')),
          filterreihen: reihen(document.querySelector('#chips')),
          mehrknopf: sichtbar('#btnMore'),
          export_sichtbar: sichtbar('#btnExport'),
        });
        """
        web.callAsyncJavaScript(js, in: nil, in: .page) { outcome in
            dann((try? outcome.get()) as? String ?? String(describing: outcome))
        }
    }

    /// Zeichnet beide Poster und legt sie zum Ansehen im Temp-Ordner ab.
    private func posterPruefen(dann: @escaping () -> Void) {
        let js = """
        const bilder = ['hoch', 'quer'].map(f => {
          const c = posterZeichnen(f);
          return {format: f, groesse: c.width + '×' + c.height, daten: c.toDataURL('image/png').split(',')[1]};
        });
        return JSON.stringify(bilder);
        """
        web.callAsyncJavaScript(js, in: nil, in: .page) { outcome in
            defer { dann() }
            guard let text = (try? outcome.get()) as? String,
                  let data = text.data(using: .utf8),
                  let liste = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
                print("POSTER:", String(describing: outcome))
                return
            }
            for bild in liste {
                guard let format = bild["format"], let b64 = bild["daten"],
                      let png = Data(base64Encoded: b64) else { continue }
                let ziel = FileManager.default.temporaryDirectory
                    .appendingPathComponent("poster-\(format).png")
                try? png.write(to: ziel, options: .atomic)
                print("POSTER \(format): \(bild["groesse"] ?? "?") · \(png.count / 1024) kB · \(ziel.path)")
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

        // Die gemeinsame Ablage ist noch leer und fragt nach dem bisherigen Bestand
        case "seed":
            hydrate(Store.read(), function: "__seedLocal")

        // Stellenanzeige im Standardbrowser öffnen
        case "openURL":
            if let text = body["url"] as? String, let url = URL(string: text),
               let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
            }

        // Poster aus der Statistik-Ansicht sichern
        case "exportImage":
            let panel = NSSavePanel()
            panel.nameFieldStringValue = (body["name"] as? String) ?? "zapply.png"
            panel.allowedContentTypes = [.png]
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url,
                      let b64 = body["data"] as? String,
                      let data = Data(base64Encoded: b64) else { return }
                try? data.write(to: url, options: .atomic)
            }

        case "export":
            let panel = NSSavePanel()
            panel.nameFieldStringValue = (body["name"] as? String) ?? "zapply.json"
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
        alert.messageText = "\(MARKE) konnte nicht starten"
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
        appMenu.addItem(withTitle: "Über \(MARKE)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Synchronisierung …", action: #selector(setupSync), keyEquivalent: "")
        appMenu.addItem(withTitle: "Ordner mit Daten zeigen", action: #selector(revealData), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(MARKE) ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "\(MARKE) beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    /// Adresse der gemeinsamen Ablage eintragen oder wieder entfernen.
    @objc private func setupSync() {
        let alert = NSAlert()
        alert.messageText = "Synchronisierung"
        alert.informativeText = "Adresse der gemeinsamen Ablage samt Schlüssel einsetzen, "
            + "zum Beispiel https://bewerbungen.deinname.workers.dev\n\n"
            + "Leer lassen und sichern, um wieder nur mit der Datei auf diesem Mac zu arbeiten."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = Store.syncURL
        field.placeholderString = "https://…workers.dev"
        alert.accessoryView = field
        alert.addButton(withTitle: "Sichern")
        alert.addButton(withTitle: "Abbrechen")
        if alert.runModal() == .alertFirstButtonReturn {
            Store.syncURL = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            loadInterface()
        }
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
