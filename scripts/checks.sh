## Check functions for input partitions flags etc
runCFDiskIfNeeded(){ 
  [[ -z "$cfdisk" && -n "$disk" ]] && getInput "\nStart cfdisk (y/N) ?\n" cfdisk "N"
  [[ "$cfdisk" =~ ^[yY]$ ]] && { 
    [[ -z "$disk" ]] && { getInput "\nEnter disk\n" disk; [[ -z "$disk" ]] && exitWithError "No disk entered -> exit\n"; }
    cfdisk "$disk"
  }
}
validatePartition() { lsblk -o NAME|grep -qw "${1#/dev/}"||{ exitWithError "$1: Partition does not exist!"; }; }
checkPartitions() { [[ -z "$boot" ]] && getInput "Enter boot partition: " boot; [[ -z "$swap" ]] && getInput "Enter swap partition: " swap; [[ -z "$root" ]] && getInput "Enter root partition: " root; }
validateUser() { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] || exitWithError "Invalid username!"; }
checkDebugFlag() { debugstring=$([[ "$debug" == true ]] && echo "" || echo " &>/dev/null"); }
