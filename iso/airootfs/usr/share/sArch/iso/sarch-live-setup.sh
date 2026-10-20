#!/bin/bash
# Live-ISO (systemd, vor dem Autologin): Benutzer "live" anlegen und den sArch-Desktop einrichten
set -u
U=live
if ! id "$U" &>/dev/null; then
    getent group wheel >/dev/null || groupadd -r wheel
    groups=()
    for g in wheel audio video input storage; do getent group "$g" >/dev/null && groups+=("$g"); done
    useradd -m -G "$(IFS=,; echo "${groups[*]}")" -s /bin/bash "$U"
fi
passwd -d "$U" >/dev/null
/usr/share/sArch/iso/sarch-setup-user.sh "$U" live

# Hyprland auf tty1 automatisch starten
H=$(getent passwd "$U" | cut -d: -f6)
cat > "$H/.bash_profile" <<'PROFILE'
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty)" == /dev/tty1 ]]; then
    command -v start-hyprland >/dev/null && exec start-hyprland
    exec Hyprland
fi
PROFILE
chown "$U:$U" "$H/.bash_profile"
exit 0
