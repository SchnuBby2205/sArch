## Check functions for input partitions flags etc
runCFDiskIfNeeded(){ 
  [[ -z "$cfdisk" && -n "$disk" ]] && getInput "\nStart cfdisk (y/N) ?\n" cfdisk "N"
  [[ "$cfdisk" =~ ^[yY]$ ]] && { 
    [[ -z "$disk" ]] && { getInput "\nEnter disk\n" disk; [[ -z "$disk" ]] && exitWithError "No disk entered -> exit\n"; }
    cfdisk "$disk"
  }
}
validatePartition() { lsblk -o NAME|grep -qw "${1#/dev/}"||{ exitWithError "$1: Partition does not exist!"; }; }
#checkPartitions() { [[ -z "$boot" ]] && getInput "Enter boot partition: " boot; [[ -z "$swap" ]] && getInput "Enter swap partition: " swap; [[ -z "$root" ]] && getInput "Enter root partition: " root; }
checkPartitions() {
  retval=0
  [[ -z "$boot" ]] && retval=$(($retval+1)) 
  [[ -z "$swap" ]] && retval=$(($retval+10))
  [[ -z "$root" ]] && retval=$(($retval+100))
  return $retval
}
validateUser() { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] || exitWithError "Invalid username!"; }
checkDebugFlag() { debugstring=$([[ "$debug" == true ]] && echo "" || echo " &>/dev/null"); }
checkInstallSettings() {
  if [[ ("$1" == "boot" || "$1" == "swap" || "$1" == "root") || -z "$1" ]]; then
    checkPartitions
    parts="$?"
    if [[ -z "$1" ]]; then
      myIter=${arrPartitions[$parts]}
    else
      myIter=$1
    fi
    if [[ $parts -gt 0 || -n "$1" ]]; then
      mapfile -t partitions < <(lsblk -ln -o NAME,TYPE | awk '$2=="part" {print "/dev/" $1}') 
      for p in ${myIter[@]}; do
        part=$(list "Please select the $p partition:" ${partitions[@]})
        printf -v "$p" "${partitions[$part]}"
        sed -i "/$p/d" "$sARCH_INSTALLCONFIGS/install_settings"
        echo -e "$p=\"${!p}\"" >> "$sARCH_INSTALLCONFIGS/install_settings"
        clear;Banner
      done
    fi
    [[ -n "$1" ]] && showSettings
  fi
  if [[ ("$1" == "hostname" || "$1" == "user") || -z "$1" ]]; then
    if [[ -z "$1" ]]; then
      myIter=("hostname" "user")
    else
      myIter=$1
    fi
    for v in ${myIter[@]}; do
      if [[ -z "${!v}" || -n "$1" ]]; then
        getInput "Please enter your ${v^} (default is ${checkDefaults[$v]}): " ${v} "${checkDefaults[$v]}"
        sed -i "/$v/d" "$sARCH_INSTALLCONFIGS/install_settings"
        echo -e "$v=\"${!v}\"" >> "$sARCH_INSTALLCONFIGS/install_settings"
      fi
      clear;Banner
    done
    [[ -n "$1" ]] && showSettings
  fi
  if [[ ("$1" == "cpu" || "$1" == "gpu") || -z "$1" ]]; then
    if [[ -z "$1" ]]; then
      myIter=("cpu" "gpu")
    else
      myIter=$1
    fi
    for v in ${myIter[@]}; do
      if [[ -z "${!v}" || -n "$1" ]]; then
        readList "$sARCH_INSTALLCONFIGS/${v}s"
        _v=$(list "Please select your ${v^}: " ${list[@]})
        printf -v "$v" "${list[$_v]}"
        printf "\n"
        sed -i "/$v/d" "$sARCH_INSTALLCONFIGS/install_settings"
        echo -e "$v=\"${!v}\"" >> "$sARCH_INSTALLCONFIGS/install_settings"
      fi
      clear;Banner
    done
    [[ -n "$1" ]] && showSettings
  fi
  if [[ ("$1" == "timezone" || "$1" == "locale" || "$1" == "keymap" || "$1" == "kernel" ) || -z "$1" ]]; then
    if [[ -z "$1" ]]; then
      myIter=("timezone" "locale" "keymap" "kernel")
    else
      myIter=$1
    fi
    for v in ${myIter[@]}; do
      if [[ -z "${!v}" || -n "$1" ]]; then
        readList "$sARCH_INSTALLCONFIGS/${v}s"
        _v=$(list "Please select your ${v^}: " ${list[@]})
        printf "\n"
        if [[ "${list[$_v]}" == "Other" ]]; then
          getInput "Please enter your ${v^} (default is ${checkDefaults[$v]}): " ${v} "${checkDefaults[$v]}"
        else
          printf -v "$v" "${list[$_v]}"
        fi
      fi
      sed -i "/$v/d" "$sARCH_INSTALLCONFIGS/install_settings"
      echo -e "$v=\"${!v}\"" >> "$sARCH_INSTALLCONFIGS/install_settings"
      clear;Banner
    done 
    [[ -n "$1" ]] && showSettings
  fi
}