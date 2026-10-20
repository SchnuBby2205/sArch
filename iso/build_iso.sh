#!/bin/bash
# =============================================================================
# sArch Live-ISO bauen (archiso + Calamares)
#
# Läuft als root in einem Arch-Linux-Container (GitHub Actions oder iso/build_local.sh).
# Direkt auf einem Arch-Rechner nur mit --host (legt einen Build-Benutzer "sarchbuild" an
# und installiert die AUR-Pakete dort mit).
#
# Umgebungsvariablen:
#   SARCH_KERNEL   Kernel für Live-System und Installation   (Standard: linux-lts)
#   SARCH_BRANCH   Branch, den ~/sArch auf dem System verfolgt (Standard: aktueller Branch)
#   SARCH_WORK     Arbeitsverzeichnis                         (Standard: iso/work)
#   SARCH_OUT      Ausgabeordner für die ISO                  (Standard: iso/out)
#   SARCH_AUR_CACHE  fertig gebaute AUR-Pakete zwischen Builds (Standard: iso/aurcache)
#   SARCH_ZSTD_LEVEL squashfs-Kompression 1-22               (Standard: 6 – schnell, kaum größer als 15)
#   SARCH_KEEP_WORK=1  Arbeitsverzeichnis nach dem Bauen behalten
# =============================================================================
set -euo pipefail

ISO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$ISO_DIR")
KERNEL=${SARCH_KERNEL:-linux-lts}
WORK=${SARCH_WORK:-$ISO_DIR/work}
OUT=${SARCH_OUT:-$ISO_DIR/out}
PROFILE=$WORK/profile
LOCALREPO=$WORK/localrepo
AURCACHE=${SARCH_AUR_CACHE:-$ISO_DIR/aurcache}
ZSTD_LEVEL=${SARCH_ZSTD_LEVEL:-6}
BUILDER=sarchbuild
GITHUB_URL=https://github.com/SchnuBby2205/sArch.git
WALLPAPER_REPO=https://github.com/SchnuBby2205/wallpaper.git
IC=$REPO/configs/installConfigs

log()  { printf '\n\e[1;36m==>\e[0m \e[1m%s\e[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\e[1;33m  ! %s\e[0m\n' "$*" >&2; }
die()  { printf '\e[1;31m!! %s\e[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Bitte als root starten (am einfachsten: iso/build_local.sh)."
[[ -f /etc/arch-release ]] || die "Läuft nur unter Arch Linux (Container: iso/build_local.sh)."
if [[ ! -f /.dockerenv && ! -f /run/.containerenv && "${1:-}" != --host ]]; then
    die "Nicht in einem Container. iso/build_local.sh benutzen – oder bewusst mit --host direkt auf diesem Rechner bauen."
fi

# -----------------------------------------------------------------------------
log "Build-Umgebung vorbereiten"
# -----------------------------------------------------------------------------
sed -i '/^\[multilib\]/,/^Include/ s/^#//; /^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
grep -q '^\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
pacman -Syu --noconfirm --needed archiso git base-devel sudo curl pacman-contrib
git config --global --add safe.directory '*'
BRANCH=${SARCH_BRANCH:-$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}
[[ "$BRANCH" == HEAD || "$BRANCH" == iso-* ]] && BRANCH=main
info "Branch: $BRANCH   Kernel: $KERNEL"

# -----------------------------------------------------------------------------
log "Paketlisten zusammenstellen"
# -----------------------------------------------------------------------------
# sArch-Liste (1. Zeile Name, 2. Zeile Fortschritt, danach Pakete mit {a,b}-Klammern)
sarchList() { local l; tail -n +3 "$1" | while read -r l; do [[ -n "$l" ]] && eval "printf '%s\n' $l"; done; }
plainList() { sed 's/#.*//; s/[[:space:]]\+$//; /^[[:space:]]*$/d' "$1"; }

mapfile -t WANT_TARGET < <({
    for f in systemdeps audiodeps programs fonts amd; do sarchList "$IC/$f"; done
    plainList "$ISO_DIR/packages/target.txt"
    echo "$KERNEL"
} | sort -u)
mapfile -t WANT_LIVE < <(plainList "$ISO_DIR/packages/live.txt" | sort -u)

inAUR() { curl -fsS --retry 3 "https://aur.archlinux.org/rpc/v5/info?arg[]=$1" 2>/dev/null | grep -q '"resultcount":[1-9]'; }
REPO_PKGS=() AUR_PKGS=() TARGET=() LIVE=()
classify() { # $1 = Paket, $2 = Zielliste (TARGET|LIVE)
    local p=$1
    if pacman -Si "$p" &>/dev/null; then REPO_PKGS+=("$p")
    elif inAUR "$p"; then AUR_PKGS+=("$p")
    elif inAUR "$p-git"; then warn "'$p' nur als '$p-git' im AUR – nehme das"; p=$p-git; AUR_PKGS+=("$p")
    else warn "Paket '$p' weder in den Repos noch im AUR – übersprungen"; return; fi
    local -n dst=$2; dst+=("$p")
}
for p in "${WANT_TARGET[@]}"; do classify "$p" TARGET; done
for p in "${WANT_LIVE[@]}"; do classify "$p" LIVE; done
[[ " ${LIVE[*]} " == *" calamares "* || " ${LIVE[*]} " == *" calamares-git "* ]] || die "calamares nicht gefunden – ohne Installer keine ISO."
info "Repo-Pakete: ${#REPO_PKGS[@]}   AUR-Pakete: ${AUR_PKGS[*]}"

# -----------------------------------------------------------------------------
log "AUR-Pakete bauen (lokales Repo)"
# -----------------------------------------------------------------------------
rm -rf "$LOCALREPO"; mkdir -p "$LOCALREPO"
id "$BUILDER" &>/dev/null || useradd -m "$BUILDER"
echo "$BUILDER ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-sarchbuild
chmod 440 /etc/sudoers.d/90-sarchbuild
BH=$(getent passwd "$BUILDER" | cut -d: -f6)
install -d -o "$BUILDER" -g "$BUILDER" "$BH/aur"
# keine -debug-Pakete (spart beim Calamares-Build Zeit)
sed -i -E '/^OPTIONS=/ s/([( ])debug([ )])/\1!debug\2/' /etc/makepkg.conf
asBuilder() { sudo -u "$BUILDER" env HOME="$BH" MAKEFLAGS="-j$(nproc)" "$@"; }

# Cache: schon gebaute AUR-Pakete vorab installieren -> yay --needed baut nur, was im AUR neuer ist
mkdir -p "$AURCACHE"
find "$AURCACHE" -name '*-debug-*.pkg.tar.zst' -delete
mapfile -t CACHED < <(find "$AURCACHE" -maxdepth 1 -name '*.pkg.tar.zst' | sort)
if (( ${#CACHED[@]} )); then
    info "${#CACHED[@]} AUR-Pakete aus dem Cache"
    if ! pacman -U --noconfirm --needed "${CACHED[@]}" >/dev/null; then
        warn "Cache nicht komplett installierbar – einzeln (Rest wird neu gebaut)"
        for _ in 1 2; do for f in "${CACHED[@]}"; do pacman -U --noconfirm --needed "$f" &>/dev/null || true; done; done
    fi
fi

# yay-bin zuerst (fertiges Binary, braucht kein Go); baut danach auch AUR-Abhängigkeiten mit
if ! command -v yay >/dev/null; then
    asBuilder bash -c "rm -rf '$BH/yay-bin' && git clone --depth 1 https://aur.archlinux.org/yay-bin.git '$BH/yay-bin' && cd '$BH/yay-bin' && makepkg -si --noconfirm"
fi
# --needed: was aus dem Cache schon aktuell installiert ist, wird übersprungen
asBuilder yay -S --noconfirm --needed --builddir "$BH/aur" \
    --answerdiff None --answerclean None --answeredit None --removemake \
    "${AUR_PKGS[@]}"
# neu gebaute Pakete in den Cache, dort nur die neueste Version behalten
find "$BH/yay-bin" "$BH/aur" -name '*.pkg.tar.zst' ! -name '*-debug-*' -exec cp -t "$AURCACHE" {} + 2>/dev/null || true
paccache -q -r -k1 -c "$AURCACHE" >/dev/null 2>&1 || true
cp "$AURCACHE"/*.pkg.tar.zst "$LOCALREPO"/ 2>/dev/null || die "Keine AUR-Pakete vorhanden."
repo-add -q "$LOCALREPO/sarch-local.db.tar.gz" "$LOCALREPO"/*.pkg.tar.zst
info "$(ls "$LOCALREPO"/*.pkg.tar.zst | wc -l) Pakete im lokalen Repo"

# -----------------------------------------------------------------------------
log "archiso-Profil (releng + sArch)"
# -----------------------------------------------------------------------------
rm -rf "$PROFILE"; mkdir -p "$WORK"
cp -a /usr/share/archiso/configs/releng "$PROFILE"
A=$PROFILE/airootfs

# Pakete: eigene Liste statt der releng-Liste
printf '%s\n' "${TARGET[@]}" "${LIVE[@]}" | sort -u > "$PROFILE/packages.x86_64"

# pacman.conf: multilib an; zum Bauen zusätzlich das lokale AUR-Repo
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$PROFILE/pacman.conf"
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' "$PROFILE/pacman.conf"
mkdir -p "$A/etc"
cp "$PROFILE/pacman.conf" "$A/etc/pacman.conf"         # Live + installiertes System (ohne lokales Repo)
printf '\n[sarch-local]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$LOCALREPO" >> "$PROFILE/pacman.conf"

# Live-System: NetworkManager statt systemd-networkd/iwd, kein sshd
S=$A/etc/systemd/system
rm -f "$S"/multi-user.target.wants/{iwd,systemd-networkd,sshd}.service \
      "$S"/sockets.target.wants/systemd-networkd*.socket \
      "$S"/network-online.target.wants/systemd-networkd-wait-online.service
mkdir -p "$S"/{multi-user,network-online}.target.wants
ln -sfn /usr/lib/systemd/system/NetworkManager.service "$S/multi-user.target.wants/NetworkManager.service"
ln -sfn /usr/lib/systemd/system/NetworkManager-dispatcher.service "$S/dbus-org.freedesktop.nm-dispatcher.service"
ln -sfn /usr/lib/systemd/system/NetworkManager-wait-online.service "$S/network-online.target.wants/NetworkManager-wait-online.service"

# sArch-Overlay (Live-Benutzer, Autologin, Calamares, Skripte)
cp -a "$ISO_DIR/airootfs/." "$A/"
ln -sfn /etc/systemd/system/sarch-live-setup.service "$S/multi-user.target.wants/sarch-live-setup.service"

# Kernel: Bootmenüs und mkinitcpio-Preset auf $KERNEL umstellen
if [[ "$KERNEL" != linux ]]; then
    grep -rlE 'vmlinuz-linux|initramfs-linux' "$PROFILE"/{efiboot,grub,syslinux} 2>/dev/null \
        | xargs -r sed -i -E "s/(vmlinuz|initramfs)-linux([^-a-z0-9]|\$)/\1-$KERNEL\2/g"
    if [[ -f "$A/etc/mkinitcpio.d/linux.preset" ]]; then
        sed -E "s/(vmlinuz|initramfs)-linux([^-a-z0-9]|\$)/\1-$KERNEL\2/g" "$A/etc/mkinitcpio.d/linux.preset" \
            > "$A/etc/mkinitcpio.d/$KERNEL.preset"
        rm "$A/etc/mkinitcpio.d/linux.preset"
    fi
fi
grep -rl 'Arch Linux install medium' "$PROFILE"/{efiboot,grub,syslinux} 2>/dev/null \
    | xargs -r sed -i 's/Arch Linux install medium/sArch Live/g'

# sArch-Repo als ~/sArch-Vorlage (git-Kopie des aktuellen Commits, Remote = GitHub)
log "sArch-Repo und Wallpaper einbetten"
git -C "$REPO" diff --quiet HEAD 2>/dev/null || warn "Nicht committete Änderungen werden NICHT übernommen (es zählt der Commit)."
mkdir -p "$A/opt"
git clone -q --no-local "file://$REPO" "$A/opt/sArch"
git -C "$A/opt/sArch" checkout -q -B "$BRANCH" "$(git -C "$REPO" rev-parse HEAD)"
git -C "$A/opt/sArch" remote set-url origin "$GITHUB_URL"
git -C "$A/opt/sArch" config "branch.$BRANCH.remote" origin
git -C "$A/opt/sArch" config "branch.$BRANCH.merge" "refs/heads/$BRANCH"
git -C "$A/opt/sArch" config --unset-all http.https://github.com/.extraheader 2>/dev/null || true
git -C "$A/opt/sArch" gc -q --prune=now 2>/dev/null || true

mkdir -p "$A/usr/share/sArch"
if git clone -q --depth 1 "$WALLPAPER_REPO" "$A/usr/share/sArch/wallpapers"; then
    rm -rf "$A/usr/share/sArch/wallpapers/.git"
else
    warn "Wallpaper-Repo nicht erreichbar – ISO ohne Wallpaper"
fi

# Metadaten für die Installation
D=$A/usr/share/sArch/iso
printf '%s\n' "${TARGET[@]}" | sort -u > "$D/target-packages.txt"
echo "$KERNEL" > "$D/kernel"
# alles, was releng + sArch nur fürs Live-System nach /etc, /root, /usr/local legen
( cd "$A" && find etc root usr/local usr/share/applications/sarch-install.desktop \
        \( -type f -o -type l \) 2>/dev/null ) \
    | grep -vxE 'etc/(passwd|group|shadow|gshadow|pacman\.conf|fstab)' \
    | sed 's|^|/|' | sort > "$D/live-files.list"
info "$(wc -l < "$D/live-files.list") Live-Dateien werden bei der Installation entfernt"

# profiledef: Name/Label + Dateirechte (archiso kopiert airootfs ohne Rechte)
cat >> "$PROFILE/profiledef.sh" <<EOF

# --- sArch ---
iso_name="sarch"
iso_label="SARCH_$(date +%Y%m)"
iso_publisher="SchnuBby2205 <https://github.com/SchnuBby2205/sArch>"
iso_application="sArch Live/Installer"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '$ZSTD_LEVEL' '-b' '1M')
file_permissions["/etc/sudoers.d/sarch-live"]="0:0:440"
file_permissions["/usr/local/bin/sarch-install"]="0:0:755"
EOF
( cd "$A" && find usr/share/sArch/iso opt/sArch -path '*/.git' -prune -o -type f -perm -u+x -print ) \
    | while read -r f; do printf 'file_permissions["/%s"]="0:0:755"\n' "$f"; done >> "$PROFILE/profiledef.sh"

# -----------------------------------------------------------------------------
log "ISO bauen (mkarchiso)"
# -----------------------------------------------------------------------------
rm -rf "$WORK/build"; mkdir -p "$OUT"
mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"
( cd "$OUT" && for f in *.iso; do sha256sum "$f" > "$f.sha256"; done )
[[ "${SARCH_KEEP_WORK:-0}" == 1 ]] || rm -rf "$WORK/build"

log "Fertig:"
ls -lh "$OUT"
