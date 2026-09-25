[English](README.md) · [日本語](README-ja.md) · [繁體中文](README-zh-TW.md) · [简体中文](README-zh.md) · Deutsch · [Français](README-fr.md)

# nimo

*Terminal-Texteditor in Nim.*

Ein kleiner, zugänglicher Terminal-Texteditor, geschrieben in Nim und nur mit der Standardbibliothek. Er ist von nano inspiriert (leicht auffindbare Tastenkürzel, eine Hinweisleiste unten), fühlt sich aber auch für Umsteiger von VSCode vertraut an: Eine Dateibaum-Seitenleiste zeigt das gesamte Arbeitsverzeichnis, Editor-Tabs liegen oben, und mit der Maus lassen sich Dateien anklicken, Tabs wechseln und der Cursor setzen.

![nimo bearbeitet seinen eigenen Quellbaum](images/screenshot.png)

## Funktionen

- Eine Dateibaum-Seitenleiste des aktuellen Arbeitsverzeichnisses, standardmäßig eingeblendet.
- Editor-Tabs mit einem Punkt für ungespeicherte Änderungen, schließbar per Maus oder `Strg+W`; sind mehr Tabs offen, als Platz haben, scrollt die Leiste seitlich.
- Mausunterstützung: Datei anklicken zum Öffnen, Tab anklicken zum Wechseln, mit dem Mausrad den Bereich unter dem Zeiger scrollen.
- UTF-8-fähiges Bearbeiten mit Rückgängig/Wiederholen und einer Anzeige des Speicherstands.
- Smart-Case-Suche, Sprung zu Zeile und wortweise Cursorbewegung.
- `Strg+Z` hält den Editor an und kehrt zur Shell zurück; mit `fg` geht es sauber weiter.
- Keine externen Bibliotheken; die Nim-Standardbibliothek ist die einzige Voraussetzung.

## Plattformen

Linux, macOS/BSD und Windows teilen sich eine Codebasis; nur `term.nim` unterscheidet sich.

| Plattform | Status |
| --- | --- |
| Linux | Unterstützt (getestet mit 2.2.10) |
| macOS / BSD | Unterstützt (dasselbe POSIX-Backend) |
| Windows 10 1703+ | Unterstützt (getestet unter 10.0.19045 mit Nim 2.2.4 + mingw64) |

Unter Windows wird die Konsole in den VT-Modus geschaltet (`ENABLE_VIRTUAL_TERMINAL_INPUT` / `ENABLE_VIRTUAL_TERMINAL_PROCESSING`). Sie versteht damit dieselben Escape-Sequenzen wie ein POSIX-Terminal, und der gesamte Decoder wird gemeinsam genutzt. Einige Unterschiede lassen sich dort aber nicht vermeiden:

- Das Anhalten mit `Strg+Z` braucht Job-Control, wofür es unter Windows keine Entsprechung gibt. Die Taste meldet, dass sie nicht verfügbar ist, und die Hinweisleiste zeigt stattdessen `^G Goto`.
- Größenänderungen des Fensters werden per Polling erkannt statt über `SIGWINCH` gemeldet.
- Bracketed Paste ist nicht verfügbar: Die alte Konsole hat es nie implementiert, und ConPTY entfernt die Markierungen, sodass ein Einfügen als gewöhnliche Tastenanschläge ankommt. Das Einfügen ist trotzdem schnell (die Eingabeschleife liest den ganzen Schwall, bevor neu gezeichnet wird), aber jedes eingefügte Zeichen ist ein eigener Rückgängig-Schritt. `Strg+U` nach dem Einfügen macht also Zeichen für Zeichen rückgängig und nicht das Eingefügte als Ganzes.

Windows Terminal ist dem alten Konsolenhost vorzuziehen, besonders wegen der Mausunterstützung. Dateien werden auf allen Plattformen mit `\n`-Zeilenenden geschrieben.

## Bauen

Benötigt Nim >= 2.0 (getestet mit 2.2.10). Es müssen keine Abhängigkeiten geladen werden.

```sh
nim c -d:release --out:nimo src/nimo.nim
```

Oder mit nimble:

```sh
nimble build          # erzeugt ./nimo
nimble run            # bauen und das aktuelle Verzeichnis öffnen
```

## Starten

```sh
./nimo                # Editor mit dem aktuellen Verzeichnis als Wurzel öffnen
./nimo path/file      # eine bestimmte Datei öffnen (oder anlegen)
```

## Tastenbelegung

### Überall
| Taste | Aktion |
| --- | --- |
| `Ctrl+S` | Speichern (fragt nach einem Namen, falls der Puffer keinen hat) |
| `Ctrl+X` | Beenden (`Ctrl+Q` geht auch; fragt nach, falls etwas ungespeichert ist) |
| `Ctrl+B` | Dateibaum-Seitenleiste ein-/ausblenden |
| `Ctrl+O` | Fokus in den Dateibaum setzen, um zu stöbern und zu öffnen |
| `Ctrl+Z` | Zur Shell anhalten (weiter mit `fg`; nur POSIX) |
| `Shift+Tab` | Fokus zwischen Editor und Dateibaum wechseln |

### Editorbereich
| Taste | Aktion |
| --- | --- |
| Pfeiltasten / `Home` / `End` | Cursor bewegen |
| `Ctrl+←` / `Ctrl+→` | Wortweise bewegen |
| `Ctrl+Home` / `Ctrl+End` | Zum Anfang / Ende der Datei springen |
| `PageUp` / `PageDown` | Um eine Bildschirmseite scrollen |
| `Ctrl+F` | Suchen (Smart Case; `Ctrl+N` wiederholt die letzte Suche) |
| `Ctrl+G` | Zu Zeilennummer springen |
| `Ctrl+U` / `Ctrl+R` | Rückgängig / Wiederholen (`Ctrl+Y` wiederholt ebenfalls) |
| `Ctrl+A` / `Ctrl+E` | Zeilenanfang / Zeilenende (wie in nano) |
| `Ctrl+W` | Aktuellen Tab schließen |
| `Ctrl+PageUp` / `Ctrl+PageDown` | Zum vorherigen / nächsten Tab wechseln |

### Dateibaum
| Taste | Aktion |
| --- | --- |
| `↑` / `↓` | Auswahl bewegen |
| `→` / `←` | Ordner auf-/zuklappen (oder hinein-/herausgehen) |
| `Enter` | Datei öffnen oder Ordner auf-/zuklappen |
| `n` | Neue Datei im ausgewählten Ordner anlegen |
| `r` / `F5` | Baum von der Festplatte neu einlesen |
| `Tab` | Fokus zurück an den Editor |

### Maus
| Aktion | Ergebnis |
| --- | --- |
| Eintrag im Baum anklicken | Datei öffnen oder Ordner auf-/zuklappen |
| Tab anklicken | Zu ihm wechseln; Klick auf seine `×` / `●`-Markierung schließt ihn |
| Pfeile `‹` / `›` anklicken | Tableiste scrollen, wenn sie überläuft |
| In den Text klicken | Cursor dorthin setzen |
| Mausrad | Baum, Text oder Tableiste unter dem Zeiger scrollen |

## Designnotizen

Der Code teilt sich in vier Module. `term.nim` kümmert sich um den Raw-Modus, das Dekodieren von Tasten und Maus, Bracketed Paste, Größenänderungen des Fensters und das Anhalten zur Shell; hinter einer gemeinsamen Schnittstelle stecken die beiden Plattform-Backends (termios/Signale unter POSIX, die Konsolen-API unter Windows), und der Decoder für Escape-Sequenzen wird von beiden genutzt. `textbuffer.nim` ist der Bearbeitungskern: UTF-8-fähig, mit Anzeigeberechnung inklusive Tab-Erweiterung, einem Journal für Rückgängig/Wiederholen und Smart-Case-Suche. `filetree.nim` ist das verzögert geladene, zwischengespeicherte Modell der Seitenleiste. `nimo.nim` verbindet alles mit der Darstellung und der Eingabeschleife.

Jede geöffnete Datei ist ein eigener Puffer mit eigenem Cursor und eigener Scrollposition. Wird eine bereits offene Datei im Baum geöffnet, wechselt nimo zu ihrem Tab, sodass nichts ungefragt verworfen wird. Cursorbewegung, Löschen und horizontales Scrollen rechnen in ganzen Zeichen (Runes) und deren Spaltenbreite auf dem Bildschirm, und der Änderungspunkt in der Statusleiste verfolgt den genauen Speicherstand: Wer bis vor das Speichern rückgängig macht, lässt ihn verschwinden. Dateien, die binär aussehen oder größer als 20 MB sind, werden abgelehnt statt beschädigt.

## Tests

```sh
nim c -r tests/test_buffer.nim   # Unit-Tests für den Bearbeitungskern
python3 tests/pty_smoke.py       # steuert die echte TUI über ein pty
python3 tests/pty_suspend.py     # prüft Anhalten / Fortsetzen mit Strg+Z
```

Die ersten beiden laufen in der CI. `pty_suspend.py` läuft nur lokal, weil POSIX ein `SIGTSTP` an eine verwaiste Prozessgruppe verwirft; auf einem CI-Runner ohne interaktive Sitzung kann Strg+Z den Prozess also nicht anhalten.

## Screenshot

Das Bild oben wird aus diesem Repository mit `scripts/screenshot.sh` erzeugt: Das Skript steuert nimo in einem tmux-Bereich und rendert den erfassten Bildschirm mit [freeze](https://github.com/charmbracelet/freeze).

<!-- BEGIN gh-mutual-linking -->

---

### Related projects

- [lpchart](https://github.com/didvc/lpchart): Chart InfluxDB line protocol in your terminal. Browse measurements, fields and tag sets interactively without knowing what is in the file first.
- [totp](https://github.com/tui-apps/totp): Terminal TOTP authenticator: live 2FA codes with countdown (RFC 6238, Go, Bubble Tea)
- [calc](https://github.com/tui-apps/calc): Live terminal calculator: evaluates arithmetic as you type, no Enter key (Go, Bubble Tea)
- [note-cli](https://github.com/didvc/note-cli): Markdown Indexing and Pcre Regular Expression Compatible Full Text Searching for Advanced Note Takers.
<!-- END gh-mutual-linking -->
