## Functions that run commands or alter the script run aka "dry run"
runCMDS() { local s=$1 m=$2 msg=$3 cur=$4 fin=$5 max=$6; shift 6
  [[ "$debug" == false ]] && { ((cur>0)) && printf "${CLEAR}${UP}${CLEAR}"; printf "["; for((i=0;i<cur;i++));do printf "#";done; for((i=cur;i<max;i++));do printf " ";done; printf "]\n$m ${WHITE}$msg${NC}"; }
  for c in "$@";do log "$c"; $([ "$s" = 1 ] && echo sudo) bash -c "$c" || exitWithError "Command failed: $c"; done
  [[ "$debug" == false ]] && { printf "${UP}\r["; for((i=0;i<fin;i++));do printf "#";done; for((i=fin;i<max;i++));do printf " ";done; printf "]\n"; }
}
safeCMD() { [[ $1 =~ ^(rm|mv)$ ]]&&{ [[ -e $2 ]]&&"$@"||{ myPrint print yellow "Warning: $2 doesnt exist, skipping $1."; log "Warning: $2 doesnt exist, skipping $1."; }; }||{ "$@"||{ myPrint print red "Error: $* failed."; log "Error: $* failed."; exitWithError "$1 fehlgeschlagen für ${*:2}"; }; }; }
dryRun() { $dryRun&&{ echo "[DRY RUN]: $*"; log "[DRY RUN]: $*"; }||"$@"; }
