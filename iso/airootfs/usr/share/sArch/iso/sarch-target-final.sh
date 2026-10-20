#!/bin/bash
# Calamares (chroot, nach grubcfg, vor bootloader):
#  - resume= aus GRUB und den resume-Hook entfernen: sonst meldet systemd-hibernate-resume bei
#    jedem Start "unable to resume ... continuing boot" (Ruhezustand wird nicht genutzt)
#  - Vorlagen der ISO löschen
set -u
log() { echo "[sarch-final] $*"; }

if [[ -f /etc/default/grub ]]; then
    sed -i -E 's/[[:space:]]*resume(_offset)?=[^[:space:]"]*//g' /etc/default/grub
    log "GRUB: $(grep -E '^GRUB_CMDLINE_LINUX(_DEFAULT)?=' /etc/default/grub | tr '\n' ' ')"
fi
if grep -qE '^HOOKS=.*\bresume\b' /etc/mkinitcpio.conf 2>/dev/null; then
    sed -i -E '/^HOOKS=/ s/[[:space:]]resume\b//' /etc/mkinitcpio.conf
    log "mkinitcpio: resume-Hook entfernt, initramfs neu"
    mkinitcpio -P
fi

rm -rf /opt/sArch /usr/share/sArch
exit 0
