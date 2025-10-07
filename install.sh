#!/bin/bash

export sARCH_MAIN="sARCH"
export sARCH_SCRIPTS="$sARCH_MAIN/scripts"
export sARCH_CONFIGS="$sARCH_MAIN/configs"

source "$sARCH_SCRIPTS/io.sh"
source "$sARCH_SCRIPTS/checks.sh"
source "$sARCH_SCRIPTS/commands.sh"
source "$sARCH_SCRIPTS/installs.sh"

source "$sARCH_CONFIGS/constants"
source "$sARCH_CONFIGS/install_settings"

sudo -v || exitWithError "You need sudo rights for this script."
[[ -z "$1" ]] && installBaseSystem || "$1"
