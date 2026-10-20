# sArch Live-ISO (Calamares)

Bootfähige ISO, die direkt in den sArch-Desktop (Hyprland + Quickshell) startet und sich mit
**Calamares** grafisch installieren lässt. Die Installation läuft **offline**, weil das komplette
Live-System auf die Platte kopiert wird. Internet braucht erst die optionale Ersteinrichtung.

## ISO bekommen

### GitHub Actions (empfohlen)

1. Im Repo auf **Actions → „sArch ISO bauen“ → Run workflow** gehen, Branch (z. B. `sArch-QS`) und Kernel wählen.
2. Nach ca. 1–2 Stunden liegt die ISO unter **Artifacts → `sarch-iso`** (14 Tage lang).
   Alternativ baut ein Tag wie `iso-2026.10` automatisch: `git tag iso-2026.10 && git push origin iso-2026.10`.

### Lokal

```bash
sudo pacman -S --needed docker && sudo systemctl start docker   # oder: podman
./iso/build_local.sh                    # Ergebnis: iso/out/sarch-*.iso (+ .sha256)
SARCH_KERNEL=linux ./iso/build_local.sh # anderer Kernel (Standard: linux-lts)
```

Gebaut wird der **letzte Commit**, nicht committete Änderungen sind nicht dabei. Der Build läuft
in einem Arch-Container, dein System bleibt unverändert.

Auf einen USB-Stick schreiben: `sudo dd if=iso/out/sarch-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`.

## Ablauf

| Schritt | Was passiert |
|---|---|
| **Live-Start** | Autologin als `live` (ohne Passwort), Hyprland + Quickshell starten, zufälliges Wallpaper + Matugen-Farben. Der Installer öffnet sich automatisch (sonst: App-Launcher → „sArch installieren“ oder `sarch-install`). WLAN: `nmtui`. |
| **Calamares** | Sprache, Zeitzone, Tastatur, Partitionierung (inkl. LUKS, ext4/btrfs/xfs), Benutzer + Passwörter. |
| **Installation** | Live-System wird kopiert, danach: Live-Reste und Live-Pakete (Calamares, archiso …) entfernt, passender Microcode, Kernel + mkinitcpio, GRUB (UEFI + BIOS), SDDM, NetworkManager, WLAN-Verbindungen aus dem Live-System übernommen. Dein Benutzer bekommt `~/sArch` (git-Repo, verfolgt den Branch der ISO), verlinkte Configs, Schriften, GTK-Theme, Wallpaper und ein fertiges Farbschema. |
| **Erster Start** | Ersteinrichtung im Vollbild-kitty (`install.sh installISOFirstboot`): NVIDIA-Treiber (wenn erkannt), Zusatzprogramme (Steam, Lutris, TeamSpeak 3, VS Code, dxvk), Backups/SchnuBby-Specifics, Firefox-Profil. Erneut aufrufbar: `~/sArch/install.sh` → Install → ISO-Ersteinrichtung. |

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
