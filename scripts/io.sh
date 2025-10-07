## Functions that output something or read something
Banner() {
  clear
  myPrint print green ".▄▄ ·  ▄▄·  ▄ .▄ ▐ ▄ ▄• ▄▌▄▄▄▄· ▄▄▄▄·  ▄· ▄▌            \n"
  myPrint print green "▐█ ▀. ▐█ ▌▪██▪▐█•█▌▐██▪██▌▐█ ▀█▪▐█ ▀█▪▐█▪██▌            \n"
  myPrint print green "▄▀▀▀█▄██ ▄▄██▀▐█▐█▐▐▌█▌▐█▌▐█▀▀█▄▐█▀▀█▄▐█▌▐█▪            \n"
  myPrint print green "▐█▄▪▐█▐███▌██▌▐▀██▐█▌▐█▄█▌██▄▪▐███▄▪▐█ ▐█▀·.            \n"
  myPrint print green " ▀▀▀▀ ·▀▀▀ ▀▀▀ ·▀▀ █▪ ▀▀▀ ·▀▀▀▀ ·▀▀▀▀   ▀ •             \n"
  myPrint print green " ▄▄▄· ▄▄▄   ▄▄·  ▄ .▄▪   ▐ ▄ .▄▄ · ▄▄▄▄▄ ▄▄▄· ▄▄▌  ▄▄▌  \n"
  myPrint print green "▐█ ▀█ ▀▄ █·▐█ ▌▪██▪▐███ •█▌▐█▐█ ▀. •██  ▐█ ▀█ ██•  ██•  \n"
  myPrint print green "▄█▀▀█ ▐▀▀▄ ██ ▄▄██▀▐█▐█·▐█▐▐▌▄▀▀▀█▄ ▐█.▪▄█▀▀█ ██▪  ██▪  \n"
  myPrint print green "▐█ ▪▐▌▐█•█▌▐███▌██▌▐▀▐█▌██▐█▌▐█▄▪▐█ ▐█▌·▐█ ▪▐▌▐█▌▐▌▐█▌▐▌\n"
  myPrint print green " ▀  ▀ .▀  ▀·▀▀▀ ▀▀▀ ·▀▀▀▀▀ █▪ ▀▀▀▀  ▀▀▀  ▀  ▀ .▀▀▀ .▀▀▀ \n\n"
}
#TESTEN: function myPrint() { local c=$1 m=$2; printf "%b" "${!c^^}${m}${NC:-}"; }
myPrint(){ case "$1" in
  step) [ "$2" = ok ] && printf "${CLEAR}${UP}${CLEAR}" || printf "${RUNNING} $2 ${WHITE}$3${NC}\n";;
  countdown) for((i=$2;i>0;i--));do myPrint print green "\r$3 $i..."; sleep 1; done; echo;;
  print) c=${2^^}; printf "%b" "${!c}${3}${NC:-}";;  
esac; }
exitWithError() { printf "\n${ERROR} %s\n" "$1"; exit 1; }
getInput(){ local p=$1 v=$2 d=$3 i; printf "${YELLOW}${p} ${NC}"; read -r i; printf -v "$v" "%s" "${i:-$d}"; [[ -z "${!v}" ]] && exitWithError "Input value can not be empty!"; }
myPasswd() {
  for ((a=0; a<3; a++)); do
    read -s -p "Password: " p1; echo
    read -s -p "Retype: " p2; echo
    [[ "$p1" != "$p2" || -z "$p1" ]] && echo "Passwords didn't match." && continue
    echo "$1:$p1" | sudo chpasswd && { myPrint print yellow "\nPassword updated successfully.\n"; return; }
    exitWithError "Error setting the password."
  done
  myPrint print red "Maximum tries reached. Script will end now."; exit 1
}
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$logFile"; }
addToBashrc() { grep -qxF "$1" $HOME/.bashrc || echo "$1" >> $HOME/.bashrc; }
readList(){ { read -r name; read -r value; mapfile -t list; } < "$1"; }
