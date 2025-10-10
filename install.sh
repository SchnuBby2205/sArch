##!/bin/bash

export sARCH_MAIN="."
export sARCH_SCRIPTS="$sARCH_MAIN/scripts"
export sARCH_CONFIGS="$sARCH_MAIN/configs"
export sARCH_INSTALLCONFIGS="$sARCH_CONFIGS/installConfigs"

source "$sARCH_SCRIPTS/io.sh"
source "$sARCH_SCRIPTS/checks.sh"
source "$sARCH_SCRIPTS/commands.sh"
source "$sARCH_SCRIPTS/installs.sh"

source "$sARCH_INSTALLCONFIGS/constants"
source "$sARCH_INSTALLCONFIGS/install_settings"

sudo -v || exitWithError "You need sudo rights for this script."
[[ -z "$1" ]] && main || "$1"