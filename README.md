# Einkauf für iPhone und Apple Watch

Native Begleit-App zur [Einkaufs-PWA](https://supervised-info.github.io/einkauf/). Dieselbe Liste auf iPhone und Watch, Abhaken synchronisiert über **WatchConnectivity**. Brücke zur PWA ist das JSON-Backup (`kind: einkauf-backup`) — die App scrapt die Website nicht.

Mindestens **Xcode 15**, iOS 17, watchOS 10. Im Apple-Developer-Account ein Team wählen. v1 ist nicht für den App-Store-Submit gedacht.

Dieses Repo wurde auf Linux erzeugt. **Simulator und `xcodebuild` wurden hier nicht ausgeführt.** Bitte auf dem Mac öffnen und dort bauen.

## Auf dem Mac öffnen

1. Repo klonen und `Einkauf.xcodeproj` in Xcode öffnen.
2. Target **Einkauf** → Signing & Capabilities → **Team** wählen (Bundle-IDs sind Platzhalter: `net.tschelle.einkauf` / `net.tschelle.einkauf.watchkitapp`).
3. Scheme **Einkauf** wählen.
4. Destination: iPhone (Gerät oder Simulator). Die Watch-App ist eingebettet und wird mitinstalliert.
5. Run (⌘R). Watch-Simulator: Scheme **EinkaufWatch** oder in der Destination das paarige Watch-Gerät wählen.

Nach einer Watch-UI-Änderung ist der Bundle-Bump über diese Build-Nummer automatisch; zeigt die Watch weiter die alte UI, Einkauf auf der Watch löschen und in der iPhone-Watch-App unter **Verfügbare Apps** neu installieren.

Projekt neu erzeugen (optional, Python 3, ohne XcodeGen):

```sh
chmod +x Scripts/generate-xcodeproj.sh
./Scripts/generate-xcodeproj.sh
```

Wenn [XcodeGen](https://github.com/yonaskolb/XcodeGen) installiert ist: `xcodegen generate` (nutzt `project.yml`).

## Backup importieren

Die App versteht PWA-Backups mit `"kind": "einkauf-backup"`. Unbekannte Felder werden ignoriert, fehlende `staples` sind in Ordnung.

**In der App**

1. Rechts oben **…** → **Backup importieren…**
2. Datei in Dateien / iCloud wählen (z. B. `einkauf-backup.json`).

**Über die Share Sheet / Dateien**

- Eine `*.json` mit `einkauf-backup` an **Einkauf** übergeben. Die App ist als JSON-Dokumenttyp registriert.

**Export**

- **…** → **Backup exportieren…** schreibt dieselbe Form (`kind`, `v`, `currentStoreId`, `stores`, `items`, `mappings`, `walkMode`, `layoutTrip`, `staples`).
- **…** → **Backup teilen** schickt dieselbe JSON-Datei über das System-Teilen-Menü (`yyyyMMdd_HHmm-einkauf-backup.json`).

Beispiel-Dateien im Repo:

- `Fixtures/einkauf-backup.json` — volle Liste inkl. Stamm-Artikel und einem unbekannten Feld
- `Fixtures/einkauf-backup-ohne-staples.json` — ohne `staples`

PWA-Export: in der Website Backup speichern/teilen, Datei aufs iPhone legen, hier importieren. Die Watch zeigt die Liste in Laden-/Abteilungsreihenfolge (`vor` zuerst, `nach` zuletzt).

## Bedienung

**iPhone:** **Geh-Modus** (große Checkbox + Name, ohne Ziehen) und **Bearbeiten** (Ziehen auch in andere Abteilungen, Umbenennen, Abteilungs-Picker, Löschen). Der Knopf zeigt den jeweils anderen Modus, wie in der PWA; `walkMode` bleibt im Backup. Plus Artikel hinzufügen, **Ladenwahl** (eingebaute Seeds plus eigene Läden unter Einstellungen), Stamm, Einstellungen (Hell/Dunkel/System, Creme/Blau), Import/Export/Teilen.

**Watch (Geh-Modus):** große Checkbox + Name, gruppiert nach Abteilung. Tippen schaltet erledigt um. Digital Crown scrollt. In v1 kein Bearbeiten auf der Watch. **Complication:** WidgetKit auf dem Zifferblatt zeigt `xx/yy` (plus Ladenname wo Platz); Tippen öffnet die Watch-App. Scheme **EinkaufWatch** auf die physische Watch installieren, danach Komplikation auf dem Zifferblatt hinzufügen.

**Sync:** Jede Änderung speichert lokal und schickt den Stand per WatchConnectivity (`updateApplicationContext`, bei Erreichbarkeit `sendMessage`, sonst `transferUserInfo`). Abhaken mergen nach Zeitstempel; neue Artikel/Import folgen der höheren Listenrevision. iPhone und Watch müssen sich einmal sehen (typisch: Bluetooth, Apps im Vordergrund oder kurz aktiv).

## Tests

Swift-Paket-Tests (auf dem Mac):

```sh
swift test
```

Ohne Swift, nur Fixture/Projekt-Checks:

```sh
python3 Scripts/verify_core.py
```

## Technik

| | |
|---|---|
| Bundle ID | `net.tschelle.einkauf` (Watch: `.watchkitapp`) |
| Geteilter Code | `Sources/Shared` in beiden Targets |
| Persistenz | JSON in Application Support |
| Abteilungen / Läden | wie die PWA (`edeka`, `aldi`, `rewe`, `lidl`, `dm`, `eigenes`) |

Stamm-Artikel lassen sich unter **Einstellungen** anlegen, entfernen und einer Abteilung zuordnen. **Stamm → Gesamtliste** setzt alle auf die Einkaufsliste (fehlende ergänzen, erledigte wieder öffnen).
