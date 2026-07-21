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

- [ ] **A1** Background-Location auf der Watch: `allowsBackgroundLocationUpdates`
      wird nie gesetzt, `WKBackgroundModes` kennt nur `workout-processing`.
      Route und Höhe können abreißen, sobald das Handgelenk fällt.
- [ ] **A2** Location-Prompt erscheint mitten im laufenden Lauf, weil
      `requestWhenInUseAuthorization()` erst nach `startRun()` fällt.
- [ ] **A3** `FirstLaunchView` ist eine Sackgasse: der Button ist ein `Text`,
      und Settings ist aus diesem Zustand nicht erreichbar.
- [ ] **A4** First-Launch-Gate prüft `store.runs` statt `allRuns` — wer seine
      Historie in Health hat, sieht ewig den Willkommensscreen.
- [ ] **A5** Home mischt Datenquellen: `lastRun` liest `allRuns`, `recent`
      liest `runs`. Läufe fehlen oder doppeln sich.
- [ ] **A6** `RunStore.deleteRuns` existiert, ist getestet, wird von keiner
      View aufgerufen.
- [ ] **A7** `weekByDay` ist Locale-blind: feste Mo–So-Beschriftung über einer
      Woche, die in en_US sonntags beginnt.
- [ ] **A8** Debug-Schalter (`demo`, `empty`, `screen`) werden auch im Release
      gelesen; `SampleData` landet im Release-Binary.
- [ ] **A9** Importierte Läufe haben keine Splits → keine Rekorde, keine
      Race-Prediction für alle, die ihre Historie mitbringen.
- [ ] **A10** Health-Berechtigungssheet erscheint beim kalten Erststart, bevor
      der Nutzer weiß wofür.
- [ ] **A11** GPX-Zeitstempel driften nach jeder Pause gegen die Wanduhr.
- [ ] **A12** Sieben `Text + Text`-Deprecation-Warnings unter iOS 26.
- [ ] **A13** Kein Zustand für „Watch nicht gekoppelt / App nicht installiert".

## B — Features

- [ ] **B1** `MapCard` ist kariertes Papier und erfindet eine Route, wenn kein
      GPS-Track existiert. → echte Karte.
- [ ] **B2** `monthAxis` ist hartkodiert `["Apr","May","Jun","Jul"]`.
- [ ] **B3** Der „since"-Delta auf Progress erzwingt ein negatives Vorzeichen
      und behauptet damit immer eine Verbesserung.
- [ ] **B4** „Heart rate at 5:30 pace" ist auf 330 s verdrahtet.
- [ ] **B5** `TrendChart`-Achsenlabels (`max+8`/`min-8`) widersprechen der auf
      `min…max` normierten Kurve.
- [ ] **B6** Grade-adjusted Pace mittelt ungewichtet über Pace-Werte, auch über
      Läufe ohne Höhendaten.
- [ ] **B7** Records und Progress zeigen Gedankenstriche statt Leerzuständen
      („— 5K").
- [ ] **B8** `realismNote` rechnet `min()` und schreibt „average".
- [ ] **B9** `longestPct` kann über 100 % gehen.
- [ ] **B10** Lauf bearbeiten: Name, Road/Trail, Klassifikation.
- [ ] **B11** Tote Settings-Zeile „Units: Kilometers" entfernen.
- [ ] **B12** „Apple Health: Connected" ist ein hartkodierter String.
- [ ] **B13** Watch-Position (keine Historie) in README dokumentieren.

## C — Organisatorisch

- [ ] **C1** `PrivacyInfo.xcprivacy` fehlt in allen drei Targets
      (`UserDefaults` = CA92.1, File-Timestamps = C617.1).
- [ ] **C2** `DEVELOPMENT_TEAM` lebt nur im generierten pbxproj — ein
      `xcodegen generate` löscht es.
- [ ] **C3** Watch-Version ist auf `1.0`/`1` verdrahtet statt an
      `MARKETING_VERSION` gekoppelt.
- [ ] **C4** `ITSAppUsesNonExemptEncryption` fehlt.
- [ ] **C5** iOS-Target deklariert `NSHealthUpdateUsageDescription`, schreibt
      aber nie in Health.
- [ ] **C6** Privacy Policy und Support-Seite existieren nicht (beides
      Pflichtfelder in App Store Connect).
- [ ] **C7** Space Grotesk steht unter OFL, es gibt keinen
      Acknowledgements-Screen.
- [ ] **C8** Checkliste für App Store Connect, was nur von Hand geht.

---

## Offen, braucht Andreas

- Apple Developer Program: Individual oder Organization? (Seller-Name, D-U-N-S)
- Domain für Privacy Policy und Support URL.
- **A1 muss auf echter Hardware verifiziert werden.** Ein Lauf ist nicht
  wiederholbar; der Simulator kann das nicht zeigen.
