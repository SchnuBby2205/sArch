#!/bin/bash
# Calamares (chroot, nach dem Anlegen des Benutzers): sArch-Desktop für den neuen Benutzer einrichten
set -u
U=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' /etc/passwd)
if [[ -n "$U" ]]; then
    echo "[sarch-user] richte $U ein"
    /usr/share/sArch/iso/sarch-setup-user.sh "$U" target
else
    echo "[sarch-user] kein Benutzer gefunden" >&2
fi
rm -rf /opt/sArch /usr/share/sArch
exit 0
