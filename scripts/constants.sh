scriptname=$(basename "$0")
logFile="/var/log/ArchInstall.log"
RED="\e[31m" GREEN="\e[32m" YELLOW="\e[1;33m" WHITE="\e[1;37m" NC="\e[0m"
CROSS="\u2717" CHECK="\u2713"
RUNNING="${YELLOW}•${NC}" ERROR="${RED}${CROSS}${NC}" MYOK="${GREEN}${CHECK}${NC}"
UP="\e[A" CLEAR="\r                                        \r"
