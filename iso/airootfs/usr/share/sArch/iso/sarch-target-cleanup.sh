#!/bin/bash
# Calamares (chroot, direkt nach dem Entpacken): aus der Live-Kopie ein normales System machen
#   - Live-Dateien (Autologin, sudo ohne Passwort, archiso-Konfiguration, Calamares) entfernen
#   - Kernel nach /boot kopieren, normale mkinitcpio-Presets
#   - Pacman-Keyring + Mirrorliste
#   - Live-Pakete (Calamares, archiso, …) und den falschen Microcode entfernen
set -u
D=/usr/share/sArch/iso
log() { echo "[sarch-cleanup] $*"; }

log "Live-Dateien entfernen"
while IFS= read -r f; do
    [[ -n "$f" && "$f" == /* ]] && rm -f -- "$f"
done < "$D/live-files.list"
rm -rf /etc/calamares /etc/mkinitcpio.conf.d/archiso.conf
find /etc/systemd/system -xtype l -delete 2>/dev/null       # verwaiste Dienst-Links
find /etc/systemd/system -mindepth 1 -type d -empty -delete 2>/dev/null

log "Kernel + mkinitcpio"
rm -f /etc/mkinitcpio.d/*.preset
for m in /usr/lib/modules/*/; do
    [[ -f "$m/pkgbase" && -f "$m/vmlinuz" ]] || continue
    kb=$(<"$m/pkgbase")
    install -Dm644 "$m/vmlinuz" "/boot/vmlinuz-$kb"
    cat > "/etc/mkinitcpio.d/$kb.preset" <<PRESET
# mkinitcpio preset file for the '$kb' package (sArch)
ALL_kver="/boot/vmlinuz-$kb"
PRESETS=('default' 'fallback')
default_image="/boot/initramfs-$kb.img"
fallback_image="/boot/initramfs-$kb-fallback.img"
fallback_options="-S autodetect"
PRESET
    log "  $kb"
done

log "Pacman: Keyring + Mirrors"
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux >/dev/null 2>&1
grep -q '^[[:space:]]*Server' /etc/pacman.d/mirrorlist 2>/dev/null \
    || echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' >> /etc/pacman.d/mirrorlist

log "Live-Pakete entfernen"
mapfile -t keep < <(grep -v '^[[:space:]]*$' "$D/target-packages.txt")
mapfile -t expl < <(pacman -Qqe)
(( ${#expl[@]} )) && pacman -D --asdeps "${expl[@]}" >/dev/null 2>&1
mapfile -t have < <(pacman -Qq "${keep[@]}" 2>/dev/null)
(( ${#have[@]} )) && pacman -D --asexplicit "${have[@]}" >/dev/null 2>&1
case "$(grep -m1 vendor_id /proc/cpuinfo)" in
    *GenuineIntel*) pacman -D --asdeps amd-ucode >/dev/null 2>&1 ;;
    *AuthenticAMD*) pacman -D --asdeps intel-ucode >/dev/null 2>&1 ;;
esac
for _ in 1 2 3; do
    mapfile -t orphans < <(pacman -Qtdq 2>/dev/null)
    (( ${#orphans[@]} )) || break
    log "  ${orphans[*]}"
    pacman -Rns --noconfirm "${orphans[@]}" || break
done

usermod -s /bin/bash root 2>/dev/null
exit 0
