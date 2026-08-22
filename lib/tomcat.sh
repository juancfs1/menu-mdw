#!/bin/bash
# Script_Version=2.0 (common.sh centralizado + formato tecnologias)
# =========================================================
# TOMCAT.SH - Información Tomcat (MDW)
# =========================================================

# Colores (por si no vienen del common)
: "${GREEN:='\033[0;32m'}"
: "${RED:='\033[0;31m'}"
: "${YELLOW:='\033[1;33m'}"
: "${CYAN:='\033[0;36m'}"
: "${NC:='\033[0m'}"

# =========================================================
# CPU / MEM
# =========================================================
get_cpu_cores() {
    local n
    n=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    [[ -z "$n" || "$n" -lt 1 ]] && n=1
    echo "$n"
}

get_total_mem_kb() {
    awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null
}

CPU_CORES=$(get_cpu_cores)
TOTAL_MEM_KB=$(get_total_mem_kb)

get_cpu_usage() {
    local pid=$1
    [[ -z "$pid" ]] && { echo "-|-"; return; }

    local cpu_proc cpu_total
    cpu_proc=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
    [[ -z "$cpu_proc" ]] && cpu_proc="-"

    if [[ "$cpu_proc" != "-" ]]; then
        cpu_total=$(awk -v c="$cpu_proc" -v n="$CPU_CORES" 'BEGIN{ if(n<1)n=1; printf "%.1f", (c/n) }')
    else
        cpu_total="-"
    fi

    echo "${cpu_proc}|${cpu_total}"
}

get_mem_usage() {
    local pid=$1
    [[ -z "$pid" ]] && { echo "-|-"; return; }

    local rss_kb mem_mb mem_pct
    rss_kb=$(ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ')
    [[ -z "$rss_kb" ]] && rss_kb=0

    mem_mb=$(awk -v r="$rss_kb" 'BEGIN{ printf "%.0f", (r/1024) }')

    if [[ -n "$TOTAL_MEM_KB" && "$TOTAL_MEM_KB" -gt 0 ]]; then
        mem_pct=$(awk -v r="$rss_kb" -v t="$TOTAL_MEM_KB" 'BEGIN{ printf "%.1f", (r*100/t) }')
    else
        mem_pct="-"
    fi

    echo "${mem_mb}|${mem_pct}"
}

# =========================================================
# PID / catalina.home
# =========================================================
get_tomcat_pid() {
    local catalina_base="$1"
    ps -eo pid,args 2>/dev/null | awk -v cb="$catalina_base" '
        $0 ~ /java/ && $0 ~ ("-Dcatalina.base=" cb) { print $1; exit }
    '
}

get_catalina_home_from_pid() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo ""; return; }
    ps -p "$pid" -o args= 2>/dev/null | grep -oE -- '-Dcatalina.home=[^ ]+' | sed 's/^-Dcatalina.home=//'
}

# =========================================================
# Java (compacta)
# =========================================================
get_java_version_from_pid() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "-"; return; }

    local java_exec
    java_exec=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
    [[ -z "$java_exec" || ! -x "$java_exec" ]] && { echo "-"; return; }

    "$java_exec" -version 2>&1 | awk -F\" '/version/ {print $2; exit}'
}

# =========================================================
# Heap
# =========================================================
tomcat_get_heap_from_pid() {
    local pid="$1"
    [[ -z "$pid" || ! -r "/proc/$pid/cmdline" ]] && { echo "-|-"; return; }

    local cmd xms xmx
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)

    xms=$(echo "$cmd" | grep -Eo '\-Xms[^ ]+' | head -n1 | sed 's/^-Xms//')
    xmx=$(echo "$cmd" | grep -Eo '\-Xmx[^ ]+' | head -n1 | sed 's/^-Xmx//')

    [[ -z "$xms" ]] && xms="-"
    [[ -z "$xmx" ]] && xmx="-"

    echo "${xms}|${xmx}"
}

# =========================================================
# Puertos HTTP/HTTPS desde server.xml (multilínea)
#   OJO: separador interno por COMAS (nunca '|', rompe tabla)
# =========================================================
tomcat_get_ports_from_serverxml() {
    local base="$1"
    local xml="$base/conf/server.xml"
    [[ -r "$xml" ]] || { echo "-,-"; return; }

    local connectors
    connectors=$(tr '\n' ' ' < "$xml" | sed 's/<Connector/\n<Connector/g' | grep '<Connector')

    local http="-" https="-"

    http=$(echo "$connectors" | \
        grep -vi ajp | \
        grep -vi 'SSLEnabled="true"' | \
        grep -vi 'scheme="https"' | \
        sed -n 's/.*port="\([0-9]\+\)".*/\1/p' | \
        sort -u | paste -sd',' -)
    [[ -z "$http" ]] && http="-"

    https=$(echo "$connectors" | \
        grep -vi ajp | \
        grep -Ei 'SSLEnabled="true"|scheme="https"' | \
        sed -n 's/.*port="\([0-9]\+\)".*/\1/p' | \
        sort -u | paste -sd',' -)
    [[ -z "$https" ]] && https="-"

    echo "${http},${https}"
}

# =========================================================
# Version Tomcat (base o catalina.home)
# =========================================================
get_tomcat_version_from_home() {
    local home="$1"
    local jar="$home/lib/catalina.jar"
    [[ -f "$jar" ]] || { echo ""; return; }
    unzip -p "$jar" META-INF/MANIFEST.MF 2>/dev/null | awk -F': ' '/Implementation-Version/ {print $2; exit}'
}

get_tomcat_version() {
    local catalina_base="$1"
    local pid="$2"

    local v=""
    v=$(get_tomcat_version_from_home "$catalina_base")
    if [[ -z "$v" && -n "$pid" ]]; then
        local ch
        ch=$(get_catalina_home_from_pid "$pid")
        [[ -n "$ch" ]] && v=$(get_tomcat_version_from_home "$ch")
    fi
    [[ -z "$v" ]] && v="-"
    echo "$v" | sed 's/[[:space:]]*$//'
}

# =========================================================
# SHOW TOMCAT INFO (tabla “como WildFly”)
# =========================================================
show_tomcat_info() {
    if [[ -z "${TOMCAT_INSTANCES+x}" ]]; then
        echo "Error: El array 'TOMCAT_INSTANCES' no está definido."
        ui_pause
        return 1
    fi

    local COLS
    COLS=$(tput cols 2>/dev/null)
    [[ "$COLS" =~ ^[0-9]+$ ]] || COLS=180

    # Columnas (fijas salvo Puertos, que se adapta)
    local W_INST=16
    local W_VER=10
    local W_STATE=9
    local W_PID=8
    local W_CPU=10
    local W_MEM=11
    local W_HEAP=11

    # Java: más estrecha (fija). Ajusta aquí si quieres 9/8/etc.
    local W_JAVA=10
    (( W_JAVA < 8 )) && W_JAVA=8

    # Puertos: ocupa el resto del ancho disponible (con mínimo)
    local ncols=9
    local overhead=$((3*ncols + 1)) # separadores/espacios del printf de la tabla
    local sum_fixed=$((W_INST+W_VER+W_STATE+W_PID+W_JAVA+W_CPU+W_MEM+W_HEAP))
    local W_PORTS=$((COLS - (sum_fixed + overhead)))
    (( W_PORTS < 18 )) && W_PORTS=18

    local TABLE_W=$((sum_fixed + W_PORTS + overhead))
    local FULL_W=$((TABLE_W - 4))

        _tc_sep() {
        local line
        line=$(printf "+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+\n" \
            "$W_INST" "" "$W_VER" "" "$W_STATE" "" "$W_PID" "" "$W_JAVA" "" \
            "$W_CPU" "" "$W_MEM" "" "$W_PORTS" "" "$W_HEAP" "" | tr ' ' '-')
        echo -e "${YELLOW}${line}${NC}"
    }


    _tc_banner_table() {
        local title="$1" cols="$2"
        local mid=" ${title} "
        local mid_len=${#mid}
        if (( mid_len >= cols )); then
            printf "%s\n" "${mid:0:cols}"
            return
        fi
        local left=$(( (cols - mid_len) / 2 ))
        local right=$(( cols - mid_len - left ))
        printf "%*s%s%*s\n" "$left" "" "$mid" "$right" "" | tr ' ' '='
    }

    _tc_trunc() {
        local s="$1" w="$2"
        [[ -z "$s" ]] && { echo ""; return; }
        if (( ${#s} <= w )); then printf "%s" "$s"; else printf "%s…" "${s:0:w-1}"; fi
    }

    _tc_wrap() { echo -n "$1" | fold -s -w "$2"; }

    # Convierte "8080,8443/18080,18443" -> líneas tipo:
    # 8080
    # 8443
    # /
    # 18080
    # 18443
        # Si cabe, una línea: "8080,8443 / 18080,18443"
    # Si no cabe, se parte por comas y por ancho, pero manteniendo " / " como separador lógico.
        # Render de puertos con etiquetas:
    # "HTTP: 8080,8081 | HTTPS: 8443,8444"
    _tc_ports_to_lines() {
        local s="$1"
        [[ -z "$s" || "$s" == "-" ]] && { echo "-"; return; }

        local http_part=""
        local https_part=""

        if [[ "$s" == */* ]]; then
            http_part="${s%%/*}"
            https_part="${s#*/}"
        else
            http_part="$s"
            https_part="-"
        fi

        [[ -z "$http_part" ]] && http_part="-"
        [[ -z "$https_part" ]] && https_part="-"

        # Limpieza de espacios accidentales
        http_part=$(echo "$http_part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        https_part=$(echo "$https_part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        echo "HTTP: ${http_part} | HTTPS: ${https_part}"
    }



        _tc_print_row() {
        local inst="$1" ver="$2" state_col="$3" pid="$4" java="$5" cpu="$6" mem="$7" ports="$8" heap="$9"

        inst=$(_tc_trunc "$inst" "$W_INST")
        ver=$(_tc_trunc "$ver" "$W_VER")
        java=$(_tc_trunc "$java" "$W_JAVA")
        cpu=$(_tc_trunc "$cpu" "$W_CPU")
        mem=$(_tc_trunc "$mem" "$W_MEM")
        heap=$(_tc_trunc "$heap" "$W_HEAP")

        local ports_pretty
        ports_pretty=$(_tc_ports_to_lines "$ports")
        mapfile -t L_PORTS < <(_tc_wrap "$ports_pretty" "$W_PORTS")
        (( ${#L_PORTS[@]} < 1 )) && L_PORTS=("-")

        local max=${#L_PORTS[@]}
        local i

        for ((i=0; i<max; i++)); do
            local row

            if [[ $i -eq 0 ]]; then
                row=$(printf "| %-*s | %-*s | %s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
                    "$W_INST" "$inst" \
                    "$W_VER" "$ver" \
                    "$state_col" \
                    "$W_PID" "$pid" \
                    "$W_JAVA" "$java" \
                    "$W_CPU" "$cpu" \
                    "$W_MEM" "$mem" \
                    "$W_PORTS" "${L_PORTS[i]}" \
                    "$W_HEAP" "$heap")
            else
                row=$(printf "| %-*s | %-*s | %s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
                    "$W_INST" "" \
                    "$W_VER" "" \
                    "$(printf "%-*s" "$W_STATE" "")" \
                    "$W_PID" "" \
                    "$W_JAVA" "" \
                    "$W_CPU" "" \
                    "$W_MEM" "" \
                    "$W_PORTS" "${L_PORTS[i]}" \
                    "$W_HEAP" "")
            fi

            # Pintar separadores verticales en amarillo
            echo -e "$(echo "$row" | sed "s/|/${YELLOW}|${NC}/g")"
        done
    }


        _tc_print_apps_block() {
        local apps="$1"
        local count=0

        if [[ -z "$apps" || "$apps" == "(ninguna)" ]]; then
            local row1 row2
            row1=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$FULL_W" "Aplicaciones desplegadas (0):" "${NC}")
            row2=$(printf "| %-*s |\n" "$FULL_W" "  (ninguna)")

            echo -e "$(echo "$row1" | sed "s/|/${YELLOW}|${NC}/g")"
            echo -e "$(echo "$row2" | sed "s/|/${YELLOW}|${NC}/g")"
            return
        fi

        while IFS= read -r a; do
            [[ -n "$a" ]] && ((count++))
        done <<< "$apps"

        local header
        header=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$FULL_W" "Aplicaciones desplegadas (${count}):" "${NC}")
        echo -e "$(echo "$header" | sed "s/|/${YELLOW}|${NC}/g")"

        while IFS= read -r a; do
            [[ -z "$a" ]] && continue
            local row
            row=$(printf "| %-*s |\n" "$FULL_W" "  - $a")
            echo -e "$(echo "$row" | sed "s/|/${YELLOW}|${NC}/g")"
        done <<< "$apps"
    }


    local SEP_RAW="$(_tc_sep)"
    local SEP="${YELLOW}${SEP_RAW}${NC}"


    clear
    echo ""
    _tc_banner_table "LISTADO DE INFORMACION TOMCAT" "$TABLE_W"
    echo ""
    echo "$SEP"

    local header
    header=$(printf "| %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
        "$W_INST" "Instancia" \
        "$W_VER"  "Version" \
        "$W_STATE" "Estado" \
        "$W_PID"  "PID" \
        "$W_JAVA" "Java" \
        "$W_CPU"  "CPU(p/t)" \
        "$W_MEM"  "Mem(MB/%)" \
        "$W_PORTS" "Puertos" \
        "$W_HEAP" "Xms/Xmx")

    echo -e "$(echo "$header" | sed "s/|/${YELLOW}|${NC}/g")"

echo "$SEP"


    for catalina_base in "${TOMCAT_INSTANCES[@]}"; do
        local inst pid state pid_print java cpu_p cpu_t mem_mb mem_pct ver http https ports xms xmx heap
        inst=$(basename "$catalina_base")
        pid=$(get_tomcat_pid "$catalina_base")

        if [[ -n "$pid" ]]; then
            state="RUNNING"
            pid_print="$pid"
            java=$(get_java_version_from_pid "$pid")
            IFS="|" read -r cpu_p cpu_t <<< "$(get_cpu_usage "$pid")"
            IFS="|" read -r mem_mb mem_pct <<< "$(get_mem_usage "$pid")"
        else
            state="STOPPED"
            pid_print="-"
            java="-"
            cpu_p="-"; cpu_t="-"
            mem_mb="-"; mem_pct="-"
        fi

        ver=$(get_tomcat_version "$catalina_base" "$pid")

        IFS="," read -r http https <<< "$(tomcat_get_ports_from_serverxml "$catalina_base")"
        ports="${http}/${https}"

        IFS="|" read -r xms xmx <<< "$(tomcat_get_heap_from_pid "$pid")"
        heap="${xms}/${xmx}"

        local state_pad state_col
        state_pad=$(printf "%-*s" "$W_STATE" "$state")
        if [[ "$state" == "RUNNING" ]]; then
            state_col="${GREEN}${state_pad}${NC}"
        else
            state_col="${RED}${state_pad}${NC}"
        fi

        _tc_print_row \
            "$inst" \
            "$ver" \
            "$state_col" \
            "$pid_print" \
            "$java" \
            "${cpu_p}/${cpu_t}" \
            "${mem_mb}/${mem_pct}" \
            "$ports" \
            "$heap"

        echo "$SEP"

        # Apps
        local apps=""
        if [[ -d "$catalina_base/webapps" ]]; then
            while IFS= read -r d; do
                local name
                name=$(basename "$d")
                case "$name" in
                    ROOT|docs|examples|host-manager|manager) continue ;;
                    *) apps+="${name}"$'\n' ;;
                esac
                #Incluimos el -L en el find para que siga los symlinks (si no no detecta las apps desplegadas)
            done < <(find -L "$catalina_base/webapps" -mindepth 1 -maxdepth 1 -type d -printf '%p\n' 2>/dev/null | sort)
        fi
        [[ -z "$apps" ]] && apps="(ninguna)"

        _tc_print_apps_block "$apps"
        echo "$SEP"
    done

    ui_pause
}

# =========================================================
# MENÚ TOMCAT (para menu_register)
# =========================================================
tomcat_menu() {
    menu_run_actions "TOMCAT" "Selecciona una opción: " 1 "$CYAN" \
        "Resumen / Tabla" "show_tomcat_info"
}
