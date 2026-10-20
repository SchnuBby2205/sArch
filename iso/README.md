# sArch Live-ISO (Calamares)

Bootfähige ISO, die direkt in den sArch-Desktop (Hyprland + Quickshell) startet und sich mit
**Calamares** grafisch installieren lässt. Die Installation läuft **offline**, weil das komplette
Live-System auf die Platte kopiert wird. Internet braucht erst die optionale Ersteinrichtung.

## ISO bekommen

### Fertiges Release herunterladen

Unter **[Releases](https://github.com/SchnuBby2205/sArch/releases/latest)** liegt die ISO in Teilen
(GitHub erlaubt pro Datei höchstens 2 GB). Alle `.part`-Dateien und die `.sha256`-Datei in **einen** Ordner
laden und dort zusammensetzen. `sarch-JJJJ.MM.TT-x86_64.iso` durch den echten Namen ersetzen,
die fertigen Befehle stehen auch im jeweiligen Release.

**Linux**
```bash
cat sarch-JJJJ.MM.TT-x86_64.iso.part* > sarch-JJJJ.MM.TT-x86_64.iso
sha256sum -c sarch-JJJJ.MM.TT-x86_64.iso.sha256        # muss "OK" melden
```

**Windows** (Eingabeaufforderung `cmd`, im Download-Ordner)
```bat
copy /b sarch-JJJJ.MM.TT-x86_64.iso.part1 + sarch-JJJJ.MM.TT-x86_64.iso.part2 sarch-JJJJ.MM.TT-x86_64.iso
certutil -hashfile sarch-JJJJ.MM.TT-x86_64.iso SHA256
```
Die angezeigte Prüfsumme mit dem Inhalt der `.sha256`-Datei vergleichen (z. B. `type sarch-…iso.sha256`).
In PowerShell funktioniert dasselbe mit `cmd /c copy /b …` bzw. `Get-FileHash sarch-…iso`.

USB-Stick: unter Linux `dd` (siehe unten), unter Windows z. B. **Rufus** (bei Nachfrage „DD-Modus“ wählen)
oder **balenaEtcher**.

### Selbst bauen über GitHub Actions

| Tag | Ergebnis |
|---|---|
| `iso-…` (z. B. `iso-2026.10.20`) | Testbuild – ISO als Artifact am Workflow-Lauf, 14 Tage |
| `release-…` (z. B. `release-2026.11`) | GitHub-Release mit ISO in Teilen + Prüfsumme, bleibt dauerhaft |

```bash
git checkout sArch-QS && git pull
git tag release-2026.11
git push origin release-2026.11
```

Der Lauf ist unter **Actions → „sArch ISO bauen“** zu sehen. Auf `main` geht ein Testbuild auch ohne Tag
über **Run workflow**.

### Lokal

```bash
sudo pacman -S --needed docker && sudo systemctl start docker   # oder: podman
./iso/build_local.sh                    # Ergebnis: iso/out/sarch-*.iso (+ .sha256)
SARCH_KERNEL=linux ./iso/build_local.sh # anderer Kernel (Standard: linux-lts)
```

**Größe:** ca. 2,5–3,5 GB, je nach Umfang des Wallpaper-Repos.

**Bauzeit:** Der erste Build kompiliert Calamares (dauert am längsten). Fertige AUR-Pakete landen in
`iso/aurcache` (bei GitHub im Actions-Cache) und werden beim nächsten Mal nur neu gebaut, wenn es im
AUR eine neuere Version gibt. Das Live-System wird mit zstd Stufe 6 gepackt
(`SARCH_ZSTD_LEVEL=15` für eine etwas kleinere, aber deutlich langsamer gebaute ISO).

Gebaut wird der **letzte Commit**, nicht committete Änderungen sind nicht dabei. Der Build läuft
in einem Arch-Container, dein System bleibt unverändert.

Auf einen USB-Stick schreiben: `sudo dd if=iso/out/sarch-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`.

## Ablauf

| Schritt | Was passiert |
|---|---|
| **Live-Start** | Autologin als `live` (ohne Passwort), Hyprland + Quickshell starten, zufälliges Wallpaper + Matugen-Farben. Der Installer öffnet sich automatisch (sonst: App-Launcher → „sArch installieren“ oder `sarch-install`). WLAN: `nmtui`. |
| **Calamares** | Sprache, Zeitzone, Tastatur, Partitionierung (inkl. LUKS, ext4/btrfs/xfs), Benutzer + Passwörter. |
| **Installation** | Live-System wird kopiert, danach: Live-Reste und Live-Pakete (Calamares, archiso …) entfernt, passender Microcode, Kernel + mkinitcpio, GRUB (UEFI + BIOS), SDDM, NetworkManager, WLAN-Verbindungen aus dem Live-System übernommen. Dein Benutzer bekommt `~/sArch` (git-Repo, verfolgt den Branch der ISO), verlinkte Configs, Schriften, GTK-Theme, Wallpaper und ein fertiges Farbschema. |
| **Erster Start** | Ersteinrichtung im Vollbild-kitty (`install.sh installISOFirstboot`): NVIDIA-Treiber (wenn erkannt), Zusatzprogramme (Steam, Lutris, TeamSpeak 3, VS Code, dxvk), Backups/Specifics (GRUB, Autologin etc.), Firefox-Profil. Erneut aufrufbar: `~/sArch/install.sh` → Install → ISO-Ersteinrichtung. |

## Aufbau

```
iso/
├── build_iso.sh          # Build im Arch-Container: AUR-Pakete → lokales Repo, releng-Profil + sArch, mkarchiso
├── build_local.sh        # startet build_iso.sh in Docker/Podman
├── packages/
│   ├── target.txt        # bleibt auf dem System (+ Listen aus configs/installConfigs)
│   └── live.txt          # nur Live-ISO, wird bei der Installation entfernt
└── airootfs/             # Overlay auf das Live-Dateisystem
    ├── etc/calamares/    # Calamares: settings.conf, Module, Branding
    ├── usr/local/bin/sarch-install
    └── usr/share/sArch/iso/
        ├── sarch-live-setup.sh      # Live-Benutzer (systemd beim Booten)
        ├── sarch-setup-user.sh      # Desktop für einen Benutzer einrichten (live + Ziel)
        ├── sarch-target-cleanup.sh  # Calamares: Live-Reste/-Pakete entfernen, Kernel, Keyring
        └── sarch-target-user.sh     # Calamares: Desktop für den neuen Benutzer
```

Pakete, die nicht in den offiziellen Repos sind (z. B. `calamares`, `ttf-material-symbols-variable`,
`yay-bin`), erkennt der Build automatisch und baut sie aus dem AUR. Pakete, die es nirgends
(mehr) gibt, werden mit einer Warnung übersprungen.
