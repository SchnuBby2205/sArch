#!/bin/bash

export sARCH_MAIN="."
export sARCH_SCRIPTS="$sARCH_MAIN/scripts"
export sARCH_CONFIGS="$sARCH_MAIN/configs"
export sARCH_INSTALLCONFIGS="$sARCH_CONFIGS/installConfigs"

source "$sARCH_SCRIPTS/io.sh"
source "$sARCH_SCRIPTS/presentation.sh"
source "$sARCH_SCRIPTS/checks.sh"
source "$sARCH_SCRIPTS/commands.sh"
source "$sARCH_SCRIPTS/installs.sh"

source "$sARCH_INSTALLCONFIGS/constants"
source "$sARCH_INSTALLCONFIGS/install_settings"

# Beim Beenden (auch Ctrl+C / Fehler) Log-Tail stoppen und Cursor wieder einblenden
trap '_leaveStageScreen' EXIT

# erst ohne Passwort versuchen (Install-Modus mit NOPASSWD), sonst normal nachfragen
sudo -n true 2>/dev/null || sudo -v || exitWithError "You need sudo rights for this script."
# sudo-Zeitstempel frisch halten, damit keine Passwortabfrage mitten in den Stage-Screen fällt
if [[ $EUID -ne 0 ]]; then
    ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) </dev/null &>/dev/null &
fi
[[ -z "$1" ]] && main || "$1"