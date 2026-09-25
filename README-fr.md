[English](README.md) · [日本語](README-ja.md) · [繁體中文](README-zh-TW.md) · [简体中文](README-zh.md) · [Deutsch](README-de.md) · Français

# nimo

*Éditeur de texte pour le terminal, écrit en Nim.*

Un petit éditeur de texte pour le terminal, simple à prendre en main, écrit en Nim avec la seule bibliothèque standard. Il s’inspire de nano (raccourcis faciles à découvrir, barre d’aide en bas de l’écran) tout en restant familier pour qui vient de VSCode : une barre latérale affiche l’arborescence de tout le répertoire de travail, les onglets de l’éditeur sont alignés en haut, et la souris permet de cliquer sur les fichiers, de changer d’onglet et de placer le curseur.

![nimo en train d’éditer sa propre arborescence de sources](images/screenshot.png)

## Fonctionnalités

- Une barre latérale avec l’arborescence du répertoire courant, affichée par défaut.
- Des onglets avec un point signalant les modifications, fermables à la souris ou avec `Ctrl+W` ; la barre d’onglets défile horizontalement quand ils ne tiennent plus tous.
- Prise en charge de la souris : cliquer sur un fichier pour l’ouvrir, sur un onglet pour y basculer, et utiliser la molette pour faire défiler le panneau sous le pointeur.
- Édition compatible UTF-8, avec annuler/rétablir et un indicateur du point de sauvegarde.
- Recherche « smart case », aller à la ligne et déplacement du curseur mot par mot.
- `Ctrl+Z` suspend l’éditeur pour revenir au shell, et `fg` le reprend proprement.
- Aucune bibliothèque externe : la bibliothèque standard de Nim est la seule dépendance.

## Plateformes

Linux, macOS/BSD et Windows partagent une seule base de code ; seul `term.nim` diffère.

| Plateforme | État |
| --- | --- |
| Linux | Pris en charge (testé avec 2.2.10) |
| macOS / BSD | Pris en charge (même backend POSIX) |
| Windows 10 1703+ | Pris en charge (testé sous 10.0.19045 avec Nim 2.2.4 + mingw64) |

Sous Windows, la console passe en mode VT (`ENABLE_VIRTUAL_TERMINAL_INPUT` / `ENABLE_VIRTUAL_TERMINAL_PROCESSING`) : elle comprend donc les mêmes séquences d’échappement qu’un terminal POSIX, et tout le décodeur est partagé. Quelques différences y restent toutefois inévitables :

- La suspension avec `Ctrl+Z` nécessite le contrôle des tâches, qui n’a pas d’équivalent sous Windows. La touche indique qu’elle n’est pas disponible, et la barre d’aide affiche `^G Goto` à la place.
- Le redimensionnement de la fenêtre est détecté par interrogation périodique plutôt que signalé par `SIGWINCH`.
- Le collage entre crochets (bracketed paste) n’est pas disponible : l’ancienne console ne l’a jamais implémenté et ConPTY supprime les marqueurs, si bien qu’un collage arrive sous forme de frappes ordinaires. Le collage reste rapide (la boucle de saisie lit toute la rafale avant de redessiner), mais chaque caractère collé constitue sa propre étape d’annulation : après un collage, `Ctrl+U` annule un caractère à la fois, et non le collage entier.

Windows Terminal est recommandé plutôt que l’ancien hôte de console, en particulier pour la prise en charge de la souris. Les fichiers sont écrits avec des fins de ligne `\n` sur toutes les plateformes.

## Compilation

Nécessite Nim >= 2.0 (testé avec 2.2.10). Aucune dépendance à récupérer.

```sh
nim c -d:release --out:nimo src/nimo.nim
```

Ou avec nimble :

```sh
nimble build          # produit ./nimo
nimble run            # compile puis ouvre le répertoire courant
```

## Lancement

```sh
./nimo                # ouvre l’éditeur à la racine du répertoire courant
./nimo path/file      # ouvre (ou crée) un fichier précis
```

## Raccourcis clavier

### Partout
| Touche | Action |
| --- | --- |
| `Ctrl+S` | Enregistrer (demande un nom si le tampon n’en a pas) |
| `Ctrl+X` | Quitter (`Ctrl+Q` fonctionne aussi ; demande confirmation s’il reste des modifications non enregistrées) |
| `Ctrl+B` | Afficher ou masquer la barre latérale de l’arborescence |
| `Ctrl+O` | Placer le focus dans l’arborescence pour parcourir et ouvrir |
| `Ctrl+Z` | Suspendre vers le shell (reprendre avec `fg` ; POSIX uniquement) |
| `Shift+Tab` | Basculer le focus entre l’éditeur et l’arborescence |

### Panneau d’édition
| Touche | Action |
| --- | --- |
| Flèches / `Home` / `End` | Déplacer le curseur |
| `Ctrl+←` / `Ctrl+→` | Se déplacer mot par mot |
| `Ctrl+Home` / `Ctrl+End` | Aller au début / à la fin du fichier |
| `PageUp` / `PageDown` | Défiler d’un écran |
| `Ctrl+F` | Rechercher (smart case ; `Ctrl+N` répète la dernière recherche) |
| `Ctrl+G` | Aller à un numéro de ligne |
| `Ctrl+U` / `Ctrl+R` | Annuler / rétablir (`Ctrl+Y` rétablit aussi) |
| `Ctrl+A` / `Ctrl+E` | Début / fin de ligne (comme dans nano) |
| `Ctrl+W` | Fermer l’onglet courant |
| `Ctrl+PageUp` / `Ctrl+PageDown` | Passer à l’onglet précédent / suivant |

### Panneau d’arborescence
| Touche | Action |
| --- | --- |
| `↑` / `↓` | Déplacer la sélection |
| `→` / `←` | Déplier / replier un dossier (ou y entrer / en sortir) |
| `Enter` | Ouvrir un fichier, ou déplier/replier un dossier |
| `n` | Créer un nouveau fichier dans le dossier sélectionné |
| `r` / `F5` | Recharger l’arborescence depuis le disque |
| `Tab` | Rendre le focus à l’éditeur |

### Souris
| Action | Résultat |
| --- | --- |
| Clic sur une entrée de l’arborescence | Ouvre le fichier, ou déplie/replie le dossier |
| Clic sur un onglet | Bascule vers cet onglet ; un clic sur son marqueur `×` / `●` le ferme |
| Clic sur les chevrons `‹` / `›` | Fait défiler la barre d’onglets quand elle déborde |
| Clic dans le texte | Place le curseur à cet endroit |
| Molette | Fait défiler l’arborescence, le texte ou la barre d’onglets sous le pointeur |

## Notes de conception

Le code se répartit en quatre modules. `term.nim` gère le mode brut, le décodage du clavier et de la souris, le collage entre crochets, le redimensionnement de la fenêtre et la suspension vers le shell ; il regroupe les deux backends de plateforme (termios/signaux sous POSIX, API de console sous Windows) derrière une même interface, le décodeur de séquences d’échappement étant partagé entre les deux. `textbuffer.nim` est le cœur de l’édition : compatible UTF-8, avec le calcul de l’affichage après expansion des tabulations, un journal d’annulation/rétablissement et la recherche smart case. `filetree.nim` est le modèle de la barre latérale, chargé à la demande et mis en cache. `nimo.nim` relie le tout avec le rendu et la boucle de saisie.

Chaque fichier ouvert possède son propre tampon, avec son propre curseur et sa propre position de défilement. Ouvrir depuis l’arborescence un fichier déjà ouvert bascule vers son onglet, si bien que rien n’est jeté dans votre dos. Le déplacement du curseur, la suppression et le défilement horizontal comptent tous en caractères entiers (runes) et en colonnes d’affichage à l’écran, et le point de modification de la barre d’état suit exactement le point de sauvegarde : annuler jusqu’avant une sauvegarde le fait disparaître. Les fichiers qui semblent binaires, ou qui dépassent 20 Mo, sont refusés plutôt qu’abîmés.

## Tests

```sh
nim c -r tests/test_buffer.nim   # tests unitaires du cœur de l’édition
python3 tests/pty_smoke.py       # pilote la vraie TUI via un pty
python3 tests/pty_suspend.py     # vérifie la suspension / reprise avec Ctrl+Z
```

Les deux premiers tournent en CI. `pty_suspend.py` ne tourne qu’en local, car POSIX ignore un `SIGTSTP` envoyé à un groupe de processus orphelin : sur un runner de CI sans session interactive, Ctrl+Z ne peut donc pas arrêter le processus.

## Capture d’écran

L’image ci-dessus est générée à partir de ce dépôt avec `scripts/screenshot.sh`, qui pilote nimo dans un panneau tmux et rend l’écran capturé avec [freeze](https://github.com/charmbracelet/freeze).

<!-- BEGIN gh-mutual-linking -->

---

### Related projects

- [lpchart](https://github.com/didvc/lpchart): Chart InfluxDB line protocol in your terminal. Browse measurements, fields and tag sets interactively without knowing what is in the file first.
- [totp](https://github.com/tui-apps/totp): Terminal TOTP authenticator: live 2FA codes with countdown (RFC 6238, Go, Bubble Tea)
- [calc](https://github.com/tui-apps/calc): Live terminal calculator: evaluates arithmetic as you type, no Enter key (Go, Bubble Tea)
- [note-cli](https://github.com/didvc/note-cli): Markdown Indexing and Pcre Regular Expression Compatible Full Text Searching for Advanced Note Takers.
<!-- END gh-mutual-linking -->
