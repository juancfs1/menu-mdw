#!/bin/bash
# Script_Version=2.0 (common.sh centralizado + formato tecnologias)

# ==============================
# FUNCIONES WILDFLY
# ==============================

# Colores ANSI
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# ==============================
# Recursos del sistema
# ==============================

get_total_mem_kb() {
    awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null
}

get_cpu_cores() {
    local n
    n=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    [[ -z "$n" || "$n" -lt 1 ]] && n=1
    echo "$n"
}

TOTAL_MEM_KB=$(get_total_mem_kb)
CPU_CORES=$(get_cpu_cores)

# ==============================
# WildFly helpers
# ==============================

resolve_wildfly_home() {
    local jhome=$1
    [[ -L "$jhome" ]] && readlink -f "$jhome" || echo "$jhome"
}

get_wildfly_version() {
    local resolved_home=$1
    basename "$resolved_home"
}

get_wildfly_pid() {
    local jhome=$1
    local resolved_home=$2

    local pid
    pid=$(ps -ef | grep java | grep -v grep | grep "\-Djboss.home.dir=$jhome" | awk '{print $2}' | head -n1)

    if [[ -z "$pid" && -n "$resolved_home" ]]; then
        pid=$(ps -ef | grep java | grep -v grep | grep "\-Djboss.home.dir=$resolved_home" | awk '{print $2}' | head -n1)
    fi

    echo "$pid"
}

# Java compacta (igual que Tomcat)
get_java_version() {
    local pid=$1
    [[ -z "$pid" ]] && { echo "-"; return; }

    local java_exec
    java_exec=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
    [[ -z "$java_exec" || ! -x "$java_exec" ]] && { echo "-"; return; }

    "$java_exec" -version 2>&1 | awk -F\" '/version/ {print $2; exit}'
}

# CPU: "cpu_proc|cpu_total"
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

# MEM: "mem_mb|mem_pct"
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

# Puertos TCP LISTEN asociados al PID (ej: "8080,9990")
get_wildfly_listen_ports() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "-"; return; }

    local ports=""

    # Preferido: ss
    if command -v ss &>/dev/null; then
        ports=$(ss -ltnp 2>/dev/null | awk -v p="$pid" '
            $0 ~ "pid="p"," {
                split($4,a,":"); prt=a[length(a)];
                if (prt ~ /^[0-9]+$/) print prt;
            }' | sort -n | uniq | paste -sd, -)
    fi

    # Fallback: lsof
    if [[ -z "$ports" ]] && command -v lsof &>/dev/null; then
        ports=$(lsof -Pan -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null | awk '
            /TCP/ {
                split($9,a,":"); prt=a[length(a)];
                if (prt ~ /^[0-9]+$/) print prt;
            }' | sort -n | uniq | paste -sd, -)
    fi

    echo "${ports:-"-"}"
}

# Listar aplicaciones (igual que tu versión original)
get_wildfly_apps() {
    local resolved_home=$1
    local mode=$2
    local apps=""

    if [[ "$mode" == "standalone" ]]; then
        local deploy_dir="$resolved_home/standalone/deployments"
        local tmp_dir="$resolved_home/standalone/tmp"

        if [[ -d "$deploy_dir" ]]; then
            apps=$(find "$deploy_dir" -mindepth 1 -maxdepth 1 -type f \( -name "*.war" -o -name "*.ear" \) -printf '%f\n' 2>/dev/null | sort -u)
        fi

        if [[ -z "$apps" && -d "$tmp_dir" ]]; then
            apps=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d \( -name "*.war" -o -name "*.ear" \) -printf '%f\n' 2>/dev/null | sort -u)
        fi
    else
        local servers_dir="$resolved_home/domain/servers"
        if [[ -d "$servers_dir" ]]; then
            apps=$(
                {
                    find "$servers_dir" -type f \( -name "*.war" -o -name "*.ear" \) -printf '%f\n' 2>/dev/null
                    find "$servers_dir" -type d \( -name "*.war" -o -name "*.ear" \) -printf '%f\n' 2>/dev/null
                } | sort -u
            )
        fi
    fi

    [[ -z "$apps" ]] && echo "(ninguna)" || echo "$apps"
}

# ==============================
# Mostrar información de WildFly
# ==============================

show_wildfly_info() {
    if [[ -z "${WILDFLY_INSTANCES+x}" ]]; then
        echo "Error: El array 'WILDFLY_INSTANCES' no está definido."
        read -rp "Pulsa Enter para continuar..."
        return 1
    fi

    local COLS
    COLS=$(tput cols 2>/dev/null)
    [[ "$COLS" =~ ^[0-9]+$ ]] || COLS=180

    # Columnas (alineado con Tomcat)
    local W_VER=22
    local W_STATE=9
    local W_PID=8
    local W_JAVA=10          # Java compacta
    local W_CPU=14
    local W_MEM=14

    # Puertos dinámico pero con min/max (para que no se coma el espacio)
    local W_PORTS_MIN=26
    local W_PORTS_MAX=42

    local ncols=7
    local overhead=$((3*ncols + 1))
    local sum_fixed=$((W_VER + W_STATE + W_PID + W_JAVA + W_CPU + W_MEM))
    local W_PORTS=$((COLS - (sum_fixed + overhead)))
    (( W_PORTS < W_PORTS_MIN )) && W_PORTS=$W_PORTS_MIN
    (( W_PORTS > W_PORTS_MAX )) && W_PORTS=$W_PORTS_MAX

    local TABLE_W=$((sum_fixed + W_PORTS + overhead))
    local FULL_W=$((TABLE_W - 4))

    # -----------------------------
    # Helpers de impresión (estilo Tomcat)
    # -----------------------------
    _wf_sep() {
        local line
        line=$(printf "+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+-%-*s-+\n" \
            "$W_VER" "" "$W_STATE" "" "$W_PID" "" "$W_JAVA" "" "$W_CPU" "" "$W_MEM" "" "$W_PORTS" "" | tr ' ' '-')
        echo -e "${YELLOW}${line}${NC}"
    }

    _wf_banner_table() {
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

    _wf_trunc() {
        local s="$1" w="$2"
        [[ -z "$s" ]] && { echo ""; return; }
        if (( ${#s} <= w )); then printf "%s" "$s"; else printf "%s…" "${s:0:w-1}"; fi
    }

    _wf_wrap() { echo -n "$1" | fold -s -w "$2"; }

    _wf_yellow_pipes() {
        echo -e "$(echo "$1" | sed "s/|/${YELLOW}|${NC}/g")"
    }

    _wf_ports_label() {
        local ports_csv="$1"
        [[ -z "$ports_csv" || "$ports_csv" == "-" ]] && { echo "-"; return; }

        # Normaliza (quita espacios)
        mapfile -t P < <(tr ',' '\n' <<<"$ports_csv" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')

        local http="" https="" mgmt_http="" mgmt_https="" otros=""
        local p
        for p in "${P[@]}"; do
            case "$p" in
                8080) http+="${http:+,}$p" ;;
                8443) https+="${https:+,}$p" ;;
                9990) mgmt_http+="${mgmt_http:+,}$p" ;;
                9993) mgmt_https+="${mgmt_https:+,}$p" ;;
                *)    otros+="${otros:+,}$p" ;;
            esac
        done

        local out=""
        [[ -n "$http" ]]      && out+="HTTP: $http"
        [[ -n "$https" ]]     && out+="${out:+ | }HTTPS: $https"
        [[ -n "$mgmt_http" ]] && out+="${out:+ | }MGMT: $mgmt_http"
        [[ -n "$mgmt_https" ]]&& out+="${out:+ | }MGMT-SSL: $mgmt_https"
        [[ -n "$otros" ]]     && out+="${out:+ | }OTROS: $otros"

        [[ -z "$out" ]] && out="PORTS: $ports_csv"
        echo "$out"
    }

    _wf_print_row() {
        local ver="$1" state_col="$2" pid="$3" java="$4" cpu="$5" mem="$6" ports_csv="$7"

        ver=$(_wf_trunc "$ver" "$W_VER")
        java=$(_wf_trunc "$java" "$W_JAVA")

        local ports_pretty
        ports_pretty=$(_wf_ports_label "$ports_csv")

        mapfile -t L_PORTS < <(_wf_wrap "$ports_pretty" "$W_PORTS")
        local max=${#L_PORTS[@]}
        (( max < 1 )) && max=1

        local i row
        for ((i=0; i<max; i++)); do
            if [[ $i -eq 0 ]]; then
                row=$(printf "| %-*s | %s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
                    "$W_VER" "$ver" \
                    "$state_col" \
                    "$W_PID" "$pid" \
                    "$W_JAVA" "$java" \
                    "$W_CPU" "$cpu" \
                    "$W_MEM" "$mem" \
                    "$W_PORTS" "${L_PORTS[i]:-}")
            else
                row=$(printf "| %-*s | %s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
                    "$W_VER" "" \
                    "$(printf "%-*s" "$W_STATE" "")" \
                    "$W_PID" "" \
                    "$W_JAVA" "" \
                    "$W_CPU" "" \
                    "$W_MEM" "" \
                    "$W_PORTS" "${L_PORTS[i]:-}")
            fi
            _wf_yellow_pipes "$row"
        done
    }

    _wf_print_apps_block() {
        local apps="$1"

        local count=0
        if [[ -z "$apps" || "$apps" == "(ninguna)" ]]; then
            local r1 r2
            r1=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$FULL_W" "Aplicaciones desplegadas (0):" "${NC}")
            r2=$(printf "| %-*s |\n" "$FULL_W" "  (ninguna)")
            _wf_yellow_pipes "$r1"
            _wf_yellow_pipes "$r2"
            return
        fi

        while IFS= read -r app; do [[ -n "$app" ]] && ((count++)); done <<< "$apps"

        local header
        header=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$FULL_W" "Aplicaciones desplegadas (${count}):" "${NC}")
        _wf_yellow_pipes "$header"

        while IFS= read -r app; do
            [[ -z "$app" ]] && continue
            local row
            row=$(printf "| %-*s |\n" "$FULL_W" "  - $app")
            _wf_yellow_pipes "$row"
        done <<< "$apps"
    }

    local SEP
    SEP="$(_wf_sep)"

    clear
    echo ""
    _wf_banner_table "LISTADO DE INFORMACION WILDFLY" "$TABLE_W"
    echo ""
    echo "$SEP"

    # Cabecera en amarillo + pipes amarillos
    local header
    header=$(printf "| %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
        "$W_VER"   "Version" \
        "$W_STATE" "Estado" \
        "$W_PID"   "PID" \
        "$W_JAVA"  "Java" \
        "$W_CPU"   "CPU(p/t)" \
        "$W_MEM"   "Mem(MB/%)" \
        "$W_PORTS" "Puertos")
    header="${YELLOW}${header}${NC}"
    _wf_yellow_pipes "$header"

    echo "$SEP"

    # -----------------------------
    # Cuerpo (con modos + apps)
    # -----------------------------
    for idx in "${!WILDFLY_INSTANCES[@]}"; do
        local jhome="${WILDFLY_INSTANCES[$idx]}"
        local mode="standalone"
        if [[ -n "${WILDFLY_MODES[$idx]+x}" ]]; then
            mode="${WILDFLY_MODES[$idx]}"
        fi

        local resolved_home
        resolved_home=$(resolve_wildfly_home "$jhome")

        local version
        version=$(get_wildfly_version "$resolved_home")

        local pid
        pid=$(get_wildfly_pid "$jhome" "$resolved_home")

        local estado estado_pad estado_colored pid_print java_version cpu_proc cpu_tot mem_mb mem_pct ports
        if [[ -n "$pid" ]]; then
            estado="RUNNING"
            pid_print="$pid"
            java_version=$(get_java_version "$pid")
            IFS="|" read -r cpu_proc cpu_tot <<< "$(get_cpu_usage "$pid")"
            IFS="|" read -r mem_mb mem_pct <<< "$(get_mem_usage "$pid")"
            ports=$(get_wildfly_listen_ports "$pid")
        else
            estado="STOPPED"
            pid_print="-"
            java_version="-"
            cpu_proc="-"; cpu_tot="-"
            mem_mb="-"; mem_pct="-"
            ports="-"
        fi

        estado_pad=$(printf "%-*s" "$W_STATE" "$estado")
        if [[ "$estado" == "RUNNING" ]]; then
            estado_colored="${GREEN}${estado_pad}${NC}"
        else
            estado_colored="${RED}${estado_pad}${NC}"
        fi

        _wf_print_row \
            "$version" \
            "$estado_colored" \
            "$pid_print" \
            "$java_version" \
            "${cpu_proc}/${cpu_tot}" \
            "${mem_mb}/${mem_pct}" \
            "$ports"

        echo "$SEP"

        local apps
        apps=$(get_wildfly_apps "$resolved_home" "$mode")
        _wf_print_apps_block "$apps"

        echo "$SEP"
    done

    read -rp "Pulsa Enter para continuar..."
}

wildfly_menu() {
    menu_run_actions "WILDFLY" "Selecciona una opción: " back "$CYAN" \
        "Resumen / Tabla" "show_wildfly_info"
}
