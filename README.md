# Bewerbungen — Bewerbungs-Tracker

Ein Werkzeug, das den eigenen Bewerbungsprozess sichtbar macht: Tabelle aller Bewerbungen,
Statusverlauf pro Stelle und ein Sankey-Diagramm, das zeigt, wo Bewerbungen tatsächlich enden.

**▶ Live-Demo (ohne Anmeldung, mit Beispieldaten):**
https://bewerbungen-demo.bewerbungs-tracker.workers.dev

Vier Sprachen (Deutsch, English, Français, العربية inkl. Rechts-nach-links), hell und dunkel
nach Systemeinstellung, vom 320-px-Handy bis zum großen Bildschirm ohne seitliches Scrollen.

**Wie es entstanden ist:** [DEVELOPMENT.md](DEVELOPMENT.md) beschreibt die Etappen, die
Entscheidungen dahinter und drei Fehler, die unterwegs auftraten. Dort steht auch, dass die
Commit-Historie nachträglich aus dem gewachsenen Stand geordnet wurde.

---

## Was es kann

**Prozess statt Statusfeld.** Jede Bewerbung führt einen Verlauf: geplant → beworben →
1./2./3./weiteres Gespräch → Angebot → Zusage, Absage, keine Antwort oder zurückgezogen.
Gespräche werden in der Zeile mit einem Klick angesetzt, beliebig oft. Der Verlauf ist
nachträglich editierbar — kam die Absage erst nach zwei Gesprächen, lässt sich das eintragen,
statt die Vorgeschichte zu verlieren.

**Sankey-Diagramm mit ehrlichen Abzweigen.** Endstatus zweigen dort ab, wo sie eingetreten
sind: eine Absage nach dem ersten Gespräch steht neben dem ersten Gespräch, nicht im selben
Topf wie eine Absage direkt nach dem Verschicken. Das Diagramm ist von Hand als SVG gebaut
(Bezier-Bänder, Knotenstapelung, kollisionsfreie Beschriftung) — ohne Chart-Bibliothek.

**Erfassung mit wenig Tippen.** Eingabehilfe für rund 300 Arbeitgeber und 175 Orte,
Firmenlogos über einen öffentlichen Favicon-Dienst mit farbiger Monogramm-Kachel als Rückfall,
Bewerbungskanäle als Icon (LinkedIn, Indeed, StepStone, Xing, Website, E-Mail) und
Gehalt strukturiert nach Betrag, Art und Zeitraum.

**Teilen als Bild.** Aus den Statistiken lässt sich ein Poster im Hochformat (1080 × 1920)
oder Querformat (1920 × 1080) erzeugen — auf eine Leinwand gezeichnet statt die Seite
abzufotografieren, damit das Ergebnis überall gleich aussieht und ohne fremde Bausteine
auskommt. Darauf stehen die Kennzahlen, das Sankey-Diagramm (dieselbe Geometrie wie in der
Ansicht, nur mit Leinwand-Mitteln gezeichnet), der Monatsverlauf, der Ausgang und die Orte
mit Gehaltsspanne. Werte von null bekommen keinen gestauchten Balken, sondern nur die Spur
und eine gedämpfte Zahl. Es zeigt bewusst nur Summen, keine Firmennamen.

**Zwei Ansichten.** Oben schaltet ein Segmentwähler zwischen *Übersicht* und *Statistiken*.
Das Dashboard zeigt den Bewerbungsfluss als Sankey, Bewerbungen nach Monat, die Antwortzeit
vom Verschicken bis zur ersten Reaktion, die Gehaltsspanne mit Median, Bewerbungen nach Ort,
die Kanäle mit ihrem Anteil an Gesprächen und den Ausgang abgeschlossener Vorgänge — alles
als handgebautes SVG beziehungsweise CSS, mit gestaffelt einlaufenden Balken.

**Suchen, filtern, sortieren.** Die Suche greift über Firma, Rolle, Ort, Kanal und Status
und verlangt bei mehreren Wörtern, dass alle passen. Chips nach Status zeigen die Anzahl
innerhalb des Suchergebnisses, sortiert wird nach Datum, Status, Firma oder Gehalt in beide
Richtungen; Filter und Sortierung bleiben pro Gerät gespeichert.

**Konten und Synchronisierung.** Registrierung nur mit Einladungscode, je Konto ein eigener
Datensatz. Änderungen gehen sofort hoch, beim Fensterwechsel wird geholt. Bei gleichzeitigen
Änderungen auf zwei Geräten wird nichts stillschweigend überschrieben — die Oberfläche legt
beide Stände vor und fragt, welcher gilt.

## Aufbau

```
web/index.html      komplette Oberfläche: HTML, CSS, JavaScript — keine Abhängigkeiten,
                    kein Build-Schritt, keine externen Skripte
sync/worker.js      Cloudflare Worker: Konten, Sitzungen, Datensatz je Konto in KV
mac/main.swift      nativer macOS-Wrapper (WKWebView) mit lokaler Datei als Offline-Stand
mac/icon.swift      zeichnet das App-Icon programmatisch (CoreGraphics)
build-app.sh        baut daraus Bewerbungen.app
sync/codes.py       Einladungscodes verwalten
```

### Entscheidungen, die erklärt werden wollen

**Eine Datei für die Oberfläche.** Kein Framework, kein Bundler: die App läuft als statische
Datei überall — lokal per Doppelklick, in einem WKWebView, hinter einem Worker. Der Preis ist
eine große Datei; der Gewinn ist, dass sie in fünf Jahren noch startet.

**Passwort-Ableitung im Browser.** Cloudflare gibt Workers im Gratis-Tarif 10 ms Rechenzeit
pro Anfrage — zu wenig für ein sauberes Passwort-Hashing. Deshalb rechnet der Browser
PBKDF2 mit 400.000 Runden und schickt nur das Ergebnis; der Server speichert davon einen
SHA-256-Hash mit kontoeigenem Zufallswert. Das Passwort im Klartext sieht der Server nie,
und Rateversuche kosten weiter die volle Ableitung.

**Sitzungen ohne Datenbankabfrage.** Ein signiertes Cookie (HMAC über Konto-ID und Ablauf)
statt Sitzungstabelle: kein Lesezugriff pro Anfrage, keine Verzögerung durch die
letztkonsistente Schlüsselablage. Der Preis: ein entwendetes Cookie bleibt bis zum Ablauf
gültig, deshalb 30 Tage Laufzeit.

**Optimistische Nebenläufigkeit statt „letzter gewinnt".** Jeder Datensatz trägt eine
Revision; der Server lehnt ein Schreiben mit veralteter Revision ab und liefert seinen Stand
mit. Die Oberfläche zeigt dann beide Möglichkeiten. Bei einem Werkzeug, in dem Wochen an
Bewerbungsarbeit stecken, ist stilles Überschreiben der schlimmste Fehler.

## Selbst betreiben

Voraussetzung: Node (für `wrangler`) und ein kostenloses Cloudflare-Konto.

```bash
npx wrangler login
npx wrangler kv namespace create DB     # die ausgegebene id in wrangler.toml einsetzen
npx wrangler secret put SESSION_SECRET  # langer Zufallswert, signiert die Sitzungscookies
npx wrangler secret put ADMIN_EMAIL     # Adresse(n), die Einladungen erzeugen dürfen
npx wrangler deploy
```

Einladungscode anlegen und damit das erste Konto registrieren:

```bash
python3 sync/codes.py neu 1
```

Nur die Vorführung ohne Konten und ohne Ablage veröffentlichen:

```bash
npx wrangler deploy -c wrangler.demo.toml
```

Die Mac-App bauen (benötigt Xcode-Befehlszeilenwerkzeuge):

```bash
./build-app.sh
```

Ohne Server geht es auch: `web/index.html` per Doppelklick öffnen oder auf einen Webspace
legen — die Daten liegen dann im Browser-Speicher des jeweiligen Geräts.

## Demo-Modus

`https://…/#demo` oder der Knopf auf der Anmeldemaske startet die Vorführung mit
Beispieldaten. Änderungen bleiben in der Sitzung des Tabs und werden nirgends gespeichert.
Die eigene Auslieferung `wrangler.demo.toml` hat weder Konten noch Datenablage — dort gibt es
nichts zu erreichen.

---

## English summary

A job application tracker built as a single dependency-free HTML file, deployed on a
Cloudflare Worker with KV storage. Four languages (German, English, French, Arabic with RTL),
light and dark, responsive from 320 px up. Its centrepiece is a hand-built SVG Sankey diagram
that branches terminal states where they actually happened, so a rejection after the first
interview is visibly distinct from a rejection right after applying. Search, status filters
and sorting work together on the same view. Accounts are
invitation-only; passwords are stretched in the browser (PBKDF2, 400k rounds) because the
Worker free tier allows only 10 ms CPU per request; concurrent edits are resolved by
revision checks and an explicit user choice rather than last-write-wins.

**Live demo:** https://bewerbungen-demo.bewerbungs-tracker.workers.dev
