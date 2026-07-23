# Release-Readiness — Arbeitsplan

Branch `feature/release-readiness`. Ein Punkt = ein Commit, damit jede
Einzelentscheidung isoliert revertierbar ist. Diese Datei fliegt beim Merge
nach `main` wieder raus.

## Entschiedene Rahmenbedingungen

| Frage | Entscheidung |
|---|---|
| Deployment Target | iOS 26 bleibt. Liquid Glass bleibt, kein Fallback. |
| Karte im Run-Detail | MapKit, echte Karte. |
| Einheiten | App bleibt metrisch, `usesKilometers` fliegt raus. |
| Watch-Historie | Bewusst keine. Uhr nimmt auf, iPhone liest. In README dokumentiert. |
| Lauf bearbeiten | Löschen + Name + Road/Trail + Klassifikation überschreibbar. |
| Progress-Metriken | HR-Drift und grade-adjusted Pace beide reparieren, nicht streichen. |
| Sprachen | Nur Englisch für v1. |

---

## A — Technische Schulden

- [x] **A1** Background-Location auf der Watch: `allowsBackgroundLocationUpdates`
      wird nie gesetzt, `WKBackgroundModes` kennt nur `workout-processing`.
      Route und Höhe können abreißen, sobald das Handgelenk fällt.
- [x] **A2** Location-Prompt erscheint mitten im laufenden Lauf, weil
      `requestWhenInUseAuthorization()` erst nach `startRun()` fällt.
- [x] **A3** `FirstLaunchView` ist eine Sackgasse: der Button ist ein `Text`,
      und Settings ist aus diesem Zustand nicht erreichbar.
- [x] **A4** First-Launch-Gate prüft `store.runs` statt `allRuns` — wer seine
      Historie in Health hat, sieht ewig den Willkommensscreen.
- [x] **A5** Home mischt Datenquellen: `lastRun` liest `allRuns`, `recent`
      liest `runs`. Läufe fehlen oder doppeln sich.
- [x] **A6** `RunStore.deleteRuns` existiert, ist getestet, wird von keiner
      View aufgerufen.
- [x] **A7** `weekByDay` ist Locale-blind: feste Mo–So-Beschriftung über einer
      Woche, die in en_US sonntags beginnt.
- [x] **A8** Debug-Schalter (`demo`, `empty`, `screen`) werden auch im Release
      gelesen; `SampleData` landet im Release-Binary.
- [x] **A9** Importierte Läufe haben keine Splits → keine Rekorde, keine
      Race-Prediction für alle, die ihre Historie mitbringen.
- [x] **A10** Health-Berechtigungssheet erscheint beim kalten Erststart, bevor
      der Nutzer weiß wofür.
- [x] **A11** GPX-Zeitstempel driften nach jeder Pause gegen die Wanduhr.
- [x] **A12** Sieben `Text + Text`-Deprecation-Warnings unter iOS 26.
- [x] **A13** Kein Zustand für „Watch nicht gekoppelt / App nicht installiert".

## B — Features

- [x] **B1** `MapCard` ist kariertes Papier und erfindet eine Route, wenn kein
      GPS-Track existiert. → echte Karte.
- [x] **B2** `monthAxis` ist hartkodiert `["Apr","May","Jun","Jul"]`.
- [x] **B3** Der „since"-Delta auf Progress erzwingt ein negatives Vorzeichen
      und behauptet damit immer eine Verbesserung.
- [x] **B4** „Heart rate at 5:30 pace" ist auf 330 s verdrahtet.
- [x] **B5** `TrendChart`-Achsenlabels (`max+8`/`min-8`) widersprechen der auf
      `min…max` normierten Kurve.
- [x] **B6** Grade-adjusted Pace mittelt ungewichtet über Pace-Werte, auch über
      Läufe ohne Höhendaten.
- [x] **B7** Records und Progress zeigen Gedankenstriche statt Leerzuständen
      („— 5K").
- [x] **B8** `realismNote` rechnet `min()` und schreibt „average".
- [x] **B9** `longestPct` kann über 100 % gehen.
- [x] **B10** Lauf bearbeiten: Name, Road/Trail, Klassifikation.
- [x] **B11** Tote Settings-Zeile „Units: Kilometers" entfernen.
- [x] **B12** „Apple Health: Connected" ist ein hartkodierter String.
- [x] **B13** Watch-Position (keine Historie) in README dokumentieren.

## C — Organisatorisch

- [x] **C1** `PrivacyInfo.xcprivacy` fehlt in allen drei Targets. Deklariert
      sind 1C8F.1 (App-Group-Suite) und CA92.1 (Standard-Defaults, Migration).
      File-Timestamps waren im Plan genannt, werden aber gar nicht benutzt —
      Über-Deklarieren ist genauso falsch wie Weglassen.
- [x] **C2** `DEVELOPMENT_TEAM` lebt nur im generierten pbxproj — ein
      `xcodegen generate` löscht es.
- [x] **C3** Watch-Version ist auf `1.0`/`1` verdrahtet statt an
      `MARKETING_VERSION` gekoppelt.
- [x] **C4** `ITSAppUsesNonExemptEncryption` fehlt.
- [x] **C5** iOS-Target deklariert `NSHealthUpdateUsageDescription`, schreibt
      aber nie in Health.
- [x] **C6** Privacy Policy und Support-Seite existieren nicht (beides
      Pflichtfelder in App Store Connect).
- [x] **C7** Space Grotesk steht unter OFL, es gibt keinen
      Acknowledgements-Screen.
- [x] **C8** Checkliste für App Store Connect, was nur von Hand geht.

---

Zusätzlich gefunden und behoben, während an dem obigen gearbeitet wurde:

- [x] **B14** Progress las `store.runs` statt `allRuns` — der einzige Screen,
      der importierte Läufe ignorierte, während Home, Log und Records sie
      zählen.
- [x] **B5 (zweiter Fehler)** `invert` tat das Gegenteil seines Kommentars, und
      der Trail-Chart übergab den falschen Wert: die höchste Kletterwoche wurde
      *unten* gezeichnet, unter einem Label, das genau diese Zahl oben nannte.
- [x] **C2 vorgezogen** — der erste `xcodegen generate` dieses Branches löschte
      `DEVELOPMENT_TEAM`, also musste das vor allem anderen sitzen.

## Offen, braucht Andreas

Siehe `docs/RELEASE-CHECKLIST.md` für die vollständige Liste. Das Wichtigste:

- Apple Developer Program: Individual oder Organization? (Seller-Name, D-U-N-S)
- Domain für Privacy Policy und Support URL; der Kontakt in beiden Seiten ist
  noch der Platzhalter `support@currimus.app`.
- **A1 muss auf echter Hardware verifiziert werden.** Ein Lauf ist nicht
  wiederholbar; der Simulator kann das nicht zeigen.
- **B1 ebenfalls**: der Simulator rendert Kartenkacheln als flachen
  Vektor-Fallback und ignoriert das Styling, die dunkle Karte wurde also noch
  nie wirklich gesehen.

## Stand am Ende des Branches

- 80 Tests grün (vorher 68), iOS- und watchOS-Release-Build ohne Warnungen.
- Jeder Punkt ein Commit, jeder Commit einzeln revertierbar.
