# Entwicklung

> **Zur Historie:** Das Projekt entstand am 17.–19. August 2026 in einem Zug; die Dateien
> wuchsen dabei an Ort und Stelle. Die Commits dieses Repositorys wurden anschließend aus
> dem gewachsenen Stand in Etappen geordnet, damit die Reihenfolge nachvollziehbar ist.
> Die Daten liegen im tatsächlichen Entstehungszeitraum, die Etappen entsprechen der
> tatsächlichen Baureihenfolge — aber es sind nicht die Zwischenstände von damals Zeile für
> Zeile. Entstanden ist das Projekt im Dialog mit einem KI-Assistenten; die Commits tragen
> deshalb einen `Co-Authored-By`-Vermerk.

## Warum überhaupt

Wer sich auf dreißig Stellen bewirbt, verliert den Überblick: Wo stand ich noch mal? Kam
die Absage vor oder nach dem Gespräch? Woran scheitert es eigentlich — an zu wenigen
Bewerbungen, an fehlenden Einladungen oder an den Gesprächen selbst? Eine Tabelle mit einer
Spalte „Status" beantwortet das nicht, weil sie nur den letzten Zustand kennt und den Weg
dorthin vergisst.

Daraus ergab sich die Leitentscheidung: **Nicht ein Status pro Bewerbung, sondern ein
Verlauf.** Alles andere folgt daraus — das Diagramm, die Quoten, die nachträgliche
Korrigierbarkeit.

## Etappen

### 1 · Grundgerüst (17.08.)

Tabelle, Erfassungsformular, Verlauf je Bewerbung, Sankey-Diagramm. Bewusst eine einzige
HTML-Datei ohne Abhängigkeiten: sie lässt sich per Doppelklick öffnen, in ein Fenster
einbetten oder auf einen Webspace legen — ohne Bauwerkzeug, das in zwei Jahren nicht mehr
läuft.

Das Diagramm ist von Hand als SVG gebaut. Eine Chart-Bibliothek hätte den Fall nicht
abgedeckt, auf den es ankommt: Endstatus sollen **dort abzweigen, wo sie eintraten**. Eine
Absage nach dem ersten Gespräch ist etwas anderes als eine Absage direkt nach dem
Verschicken — in einem gemeinsamen Endknoten wäre genau dieser Unterschied unsichtbar.

### 2 · macOS-App (17.08.)

Ein natives Fenster (WKWebView) um dieselbe Datei, Icon programmatisch mit CoreGraphics
gezeichnet, Bauskript ohne Paketmanager. Grund: der Standardbrowser des Rechners war
Safari, und Safari verweigert Web-Storage bei `file://`-Seiten — ein bloßer Doppelklick auf
die HTML-Datei hätte die Daten verloren. Die App schreibt stattdessen in eine JSON-Datei
unter *Application Support*, atomar und mit Sicherungskopie.

### 3 · Handy (17.08.)

Manifest und Icons, damit die Seite als App auf dem Home-Bildschirm landet.

### 4 · Gemeinsame Ablage (18.08.)

Cloudflare Worker mit KV-Speicher, Zugang zunächst über ein Token im Link. Jeder Datensatz
trägt eine Revision; der Server lehnt ein Schreiben mit veralteter Revision ab und liefert
seinen Stand mit. **Kein „letzter gewinnt".** In einem Werkzeug, in dem Wochen an
Bewerbungsarbeit stecken, ist stilles Überschreiben der teuerste Fehler.

### 5 · Konten (18.08.)

Token im Link ersetzt durch Konten mit Einladungscodes, je Konto ein eigener Datensatz.

Zwei Entscheidungen, die die Plattform erzwang:

**Passwort-Ableitung im Browser.** Cloudflare gibt Workers im Gratis-Tarif 10 ms Rechenzeit
pro Anfrage — für ein sauberes Passwort-Hashing zu wenig. Also rechnet der Browser PBKDF2
mit 400 000 Runden und schickt nur das Ergebnis; der Server speichert davon einen
SHA-256-Hash mit kontoeigenem Zufallswert. Das Passwort im Klartext sieht der Server nie,
und wer die Ablage stiehlt, muss pro Rateversuch die volle Ableitung nachrechnen.

**Sitzungen ohne Datenbankabfrage.** Ein signiertes Cookie statt Sitzungstabelle: kein
Lesezugriff pro Anfrage — und kein Problem damit, dass KV letztkonsistent ist. Der Preis
ist ehrlich zu nennen: ein entwendetes Cookie bleibt bis zum Ablauf gültig, darum 30 Tage.

### 6 · Vier Sprachen (18.08.)

Deutsch, Englisch, Französisch, Arabisch. Arabisch stellt die Oberfläche auf
Rechts-nach-links; Datums- und Zahlenformate folgen der Sprache, im Arabischen mit
lateinischen Ziffern, damit Geldbeträge lesbar bleiben. Das Sankey-Diagramm läuft bewusst
immer von links nach rechts — die Leserichtung eines Ablaufs soll überall dieselbe sein.

### 7 · Mac-App an der gemeinsamen Ablage (18.08.)

Die App lädt die gehostete Oberfläche und hält die lokale Datei als Offline-Stand. Fällt der
Start einmal darauf zurück, versucht sie es beim nächsten Wechsel ins Fenster erneut.

### 8–10 · Bedienung im Alltag (19.08.)

Ansicht für jede Fenstergröße (Spalten weichen gestaffelt, ab 960 px werden Zeilen zu
Karten), Filter-Chips mit Anzahl, Sortierung in beide Richtungen, Suche über Firma, Rolle,
Ort, Kanal und Status. Zuletzt ein Demo-Modus mit Beispieldaten, ausgeliefert als eigener
Worker ganz ohne Konten und Datenablage — dort gibt es nichts zu erreichen.

## Drei Fehler, die etwas gelehrt haben

**Ein Attribut, das nicht wirkt.** Die Anmeldemaske wird über `hidden` ausgeblendet, ihre
CSS-Klasse setzt aber `display:grid` — und eine Klassenregel überstimmt das Attribut. Die
Anmeldung war erfolgreich, die Maske blieb trotzdem stehen; von außen sah es aus, als
passiere beim Klick nichts. Dasselbe wiederholte sich später bei der Demo-Leiste. Erst die
zweite Begegnung führte zur richtigen Konsequenz: eine Grundregel `[hidden]{display:none}`
für alle Bereiche statt einer Einzelkorrektur.

**Prüfen, was zählt.** Der erste Test hatte nur das `hidden`-Attribut abgefragt — das war
korrekt gesetzt. Sichtbar war die Maske trotzdem. Seitdem wird gegen `getComputedStyle`
geprüft, also gegen das, was der Mensch vor dem Bildschirm sieht.

**Letztkonsistenz ist keine Verzögerung, mit der man rechnet — bis sie auffällt.** Ein neu
erzeugter Einladungscode war sofort gültig, tauchte aber nicht in der Liste auf: KV listet
Schlüssel mit Verzug. Die Oberfläche hält frisch erzeugte Codes nun selbst fest, bis die
Ablage sie mitliefert.

## Was fehlt

Kein „Passwort vergessen" (ohne Mailversand nicht ehrlich lösbar), kein Zusammenführen
einzelner Zeilen bei Konflikten (stattdessen eine bewusste Entscheidung durch den Nutzer),
keine automatisierten Tests — geprüft wurde im Browser gegen die echte Auslieferung, dazu
ein Selbsttest in der Mac-App (`--selftest`), der Daten, Tabelle und Diagramm durchmisst.
