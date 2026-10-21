## Check functions for input partitions flags etc

runCFDiskIfNeeded() {
    [[ -z "${cfdisk:-}" && -n "${disk:-}" ]] && getInput "\nStart cfdisk (y/N) ?\n" cfdisk "N"
    if [[ "${cfdisk:-}" =~ ^[yY]$ ]]; then
        if [[ -z "${disk:-}" ]]; then
            getInput "\nEnter disk\n" disk
        fi
        [[ -b "$disk" ]] || exitWithError "$disk: Not a block device!"
        cfdisk "$disk"
    fi
    return 0
}

# GRUB wird als x86_64-efi installiert -> nur im UEFI-Modus sinnvoll
checkUEFI() {
    [[ -d /sys/firmware/efi ]] || exitWithError "System is not booted in UEFI mode! Please boot the live ISO via UEFI."
    return 0
}

# Akzeptiert "/dev/sda1" und "sda1"
validatePartition() {
    local d=$1
    [[ -n "$d" ]] || exitWithError "No partition given!"
    [[ "$d" == /dev/* ]] || d="/dev/$d"
    [[ -b "$d" ]] || exitWithError "$1: Partition does not exist!"
    return 0
}

_isValidUser()     { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ && ${#1} -le 32 ]]; }
_isValidHostname() { [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; }

validateUser() {
    _isValidUser "$1" || exitWithError "Invalid username!"
    return 0
}

checkDebugFlag() {
    if [[ "${debug:-}" == true ]]; then
        debugstring=""
    else
        # Ausgabe nicht verwerfen, sondern ins Log schreiben (bei Fehlern wird das Log-Ende angezeigt)
        debugstring=" &>>'${logFile:-/dev/null}'"
    fi
    return 0
}

# setSetting key value -> schreibt/ersetzt key="value" in install_settings
# (verankertes Löschen, Sonderzeichen escaped, Format bleibt key="value")
setSetting() {
    local k=$1 v=$2 f="$sARCH_INSTALLCONFIGS/install_settings"
    mkdir -p "$sARCH_INSTALLCONFIGS"
    touch "$f"
    # fehlenden Zeilenumbruch am Dateiende ergänzen, sonst klebt die neue Zeile an der letzten
    [[ -s "$f" && -n "$(tail -c1 "$f")" ]] && printf '\n' >> "$f"
    sed -i "/^${k}=/d" "$f"
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    v=${v//\$/\\\$}
    v=${v//\`/\\\`}
    printf '%s="%s"\n' "$k" "$v" >> "$f"
}

# ── Hardware-Erkennung ───────────────────────────────────────────────────────
# detectCPU -> intel-ucode | amd-ucode | "" (unbekannt)
detectCPU() {
    case "$(grep -m1 vendor_id /proc/cpuinfo 2>/dev/null)" in
        *GenuineIntel*) echo intel-ucode ;;
        *AuthenticAMD*) echo amd-ucode ;;
    esac
}
# detectGPU -> z. B. "amd", "intel nvidia" (Reihenfolge intel amd nvidia) | "" (nichts erkannt, z. B. VM)
# liest /sys (PCI-Klasse 0x03xxxx = Grafik), braucht also kein lspci
detectGPU() {
    local d c v intel="" amd="" nvidia=""
    for d in "${SARCH_SYSFS:-/sys}"/bus/pci/devices/*; do
        [[ -r "$d/class" && -r "$d/vendor" ]] || continue
        c=$(<"$d/class"); v=$(<"$d/vendor")
        [[ "$c" == 0x03* ]] || continue
        case "$v" in
            0x8086) intel=intel ;;
            0x1002|0x1022) amd=amd ;;
            0x10de) nvidia=nvidia ;;
        esac
    done
    echo $intel $amd $nvidia
}
_hwLabel() {
    case "$1" in
        intel-ucode) echo "Intel" ;;
        amd-ucode) echo "AMD" ;;
        *) local g out=() ; for g in $1; do case "$g" in intel) out+=("Intel");; amd) out+=("AMD");; nvidia) out+=("NVIDIA");; esac; done
           local IFS=+; echo "${out[*]}" ;;
    esac
}
# Erkannten Wert vorschlagen; "Andere Auswahl" öffnet die normale Liste
_chooseDetected() {
    local v=$1 det idx
    if [[ "$v" == cpu ]]; then det=$(detectCPU); else det=$(detectGPU); fi
    if [[ -z "$det" ]]; then
        _chooseFromList "$v"
        return
    fi
    idx=$(list "${v^^} erkannt: $(_hwLabel "$det") - übernehmen?" "Ja ($det)" "Andere Auswahl") || exit 1
    printf '\n'
    if [[ "$idx" == 0 ]]; then
        printf -v "$v" '%s' "$det"
        setSetting "$v" "$det"
    else
        Banner
        _chooseFromList "$v"
    fi
}

# Partition wählen (keine leere Liste, keine Doppelbelegung boot/swap/root)
_choosePartition() {
    local p=$1 q idx dup
    local -a partitions
    while true; do
        mapfile -t partitions < <(lsblk -pln -o NAME,TYPE | awk '$2=="part" || $2=="lvm" || $2=="crypt" {print $1}')
        (( ${#partitions[@]} > 0 )) || exitWithError "No partitions found! Create partitions first (cfdisk)."
        idx=$(list "Please select the $p partition:" "${partitions[@]}") || exit 1
        dup=""
        for q in boot swap root; do
            [[ "$q" != "$p" && -n "${!q:-}" && "${!q}" == "${partitions[$idx]}" ]] && dup=$q
        done
        if [[ -n "$dup" ]]; then
            myPrint print red "${partitions[$idx]} is already used as $dup partition!\n"
            sleep 2
            Banner
            continue
        fi
        printf -v "$p" '%s' "${partitions[$idx]}"
        setSetting "$p" "${!p}"
        return 0
    done
}

# Auswahl aus ${sARCH_INSTALLCONFIGS}/<var>s ; "Other" erlaubt freie Eingabe
_chooseFromList() {
    local v=$1 idx name value
    readList "$sARCH_INSTALLCONFIGS/${v}s"
    (( ${#list[@]} > 0 )) || exitWithError "Empty list: $sARCH_INSTALLCONFIGS/${v}s"
    idx=$(list "Please select your ${v^}: " "${list[@]}") || exit 1
    printf '\n'
    if [[ "${list[$idx]}" == "Other" ]]; then
        getInput "Please enter your ${v^} (default is ${checkDefaults[$v]:-}): " "$v" "${checkDefaults[$v]:-}"
    else
        printf -v "$v" '%s' "${list[$idx]}"
    fi
    setSetting "$v" "${!v}"
}

# checkInstallSettings            -> fragt alle fehlenden Werte ab
# checkInstallSettings <name>     -> fragt genau diesen Wert neu ab (kein Rücksprung mehr
#                                    in showSettings, das Menü rendert sich selbst neu)
checkInstallSettings() {
    local only=${1:-} v p
    local -a iter=()
    Banner

    # --- Partitionen
    if [[ -z "$only" || "$only" =~ ^(boot|swap|root)$ ]]; then
        if [[ -n "$only" ]]; then
            iter=("$only")
        else
            for p in boot swap root; do
                [[ -z "${!p:-}" ]] && iter+=("$p")
            done
        fi
        for p in "${iter[@]}"; do
            _choosePartition "$p"
            Banner
        done
    fi

    # --- Hostname / User (mit Validierung)
    if [[ -z "$only" || "$only" =~ ^(hostname|user)$ ]]; then
        iter=(hostname user)
        [[ -n "$only" ]] && iter=("$only")
        for v in "${iter[@]}"; do
            if [[ -z "${!v:-}" || -n "$only" ]]; then
                while true; do
                    getInput "Please enter your ${v^} (default is ${checkDefaults[$v]:-}): " "$v" "${checkDefaults[$v]:-}"
                    if [[ "$v" == user ]]; then
                        _isValidUser "${!v}" && break
                    else
                        _isValidHostname "${!v}" && break
                    fi
                    myPrint print red "Invalid ${v}!\n"
                done
                setSetting "$v" "${!v}"
            fi
            Banner
        done
    fi

    # --- CPU / GPU (Vorschlag aus der Hardware-Erkennung, kann geändert werden)
    if [[ -z "$only" || "$only" =~ ^(cpu|gpu)$ ]]; then
        iter=(cpu gpu)
        [[ -n "$only" ]] && iter=("$only")
        for v in "${iter[@]}"; do
            [[ -z "${!v:-}" || -n "$only" ]] && _chooseDetected "$v"
            Banner
        done
    fi

    # --- Timezone / Locale / Keymap / Kernel (Wert wird immer in die Datei geschrieben)
    if [[ -z "$only" || "$only" =~ ^(timezone|locale|keymap|kernel)$ ]]; then
        iter=(timezone locale keymap kernel)
        [[ -n "$only" ]] && iter=("$only")
        for v in "${iter[@]}"; do
            if [[ -z "${!v:-}" || -n "$only" ]]; then
                _chooseFromList "$v"
            else
                setSetting "$v" "${!v}"
            fi
            Banner
        done
    fi
    return 0
}
