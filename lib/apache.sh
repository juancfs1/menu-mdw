#!/bin/bash
#Script_Version=2.0.5. Filtrado falso VH "is" y omisión de "default server" duplicado

# =========================================================
# APACHE.SH - Información Apache (MDW)
# =========================================================

# =========================================================
# Verificación / autocarga de common.sh (solo bajo demanda)
# =========================================================
_ap_require_common() {
    if ! declare -F mdw_banner_table >/dev/null || ! declare -F mdw_sep >/dev/null; then
        # shellcheck source=/dev/null
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        source "$script_dir/lib/common.sh" 2>/dev/null
    fi

    declare -F mdw_banner_table >/dev/null || {
        echo "ERROR: common.sh no está cargado (faltan mdw_*)."
        declare -F ui_pause >/dev/null && ui_pause
        return 1
    }
    return 0
}

# =========================================================
# Lógica Apache
# =========================================================
has_multiple_apache_instances() {
    local configs_count
    configs_count=$(
        ps -eo args | grep -E '/usr/sbin/httpd|/usr/sbin/apache2' | \
            grep -- '-f ' | \
            sed -n 's/.*-f[[:space:]]*\([^[:space:]]*\).*/\1/p' | \
            sort -u | wc -l
    )
    (( configs_count > 1 ))
}

get_apache_version() {
    local APACHE_BIN=$1
    if [[ -x "$APACHE_BIN" ]]; then
        "$APACHE_BIN" -v 2>/dev/null | awk -F': ' '/Server version/ {print $2}'
    else
        echo "Desconocida"
    fi
}

resolve_apache_bin() {
    local APACHE_BIN=""
    if command -v httpd &>/dev/null; then
        APACHE_BIN=$(command -v httpd)
    elif command -v apache2 &>/dev/null; then
        APACHE_BIN=$(command -v apache2)
    elif [[ -x "/opt/rh/httpd24/root/usr/sbin/httpd" ]]; then
        APACHE_BIN="/opt/rh/httpd24/root/usr/sbin/httpd"
    fi
    echo "$APACHE_BIN"
}

resolve_apache_ctl() {
    local APACHE_BIN="$1"
    local APACHE_CTL=""
    if command -v apache2ctl &>/dev/null; then
        APACHE_CTL=$(command -v apache2ctl)
    elif command -v apachectl &>/dev/null; then
        APACHE_CTL=$(command -v apachectl)
    else
        APACHE_CTL="$APACHE_BIN"
    fi
    echo "$APACHE_CTL"
}

# =========================================================
# Parser robusto de VirtualHosts
# Devuelve: server|puerto
#
# Soporta:
#   *:80 example.com (...)
#   10.0.0.1:443 example.com (...)
#   port 80 namevhost example.com (...)
#
# Ignora:
#   *:80 is a NameVirtualHost
#   default server example.com (...)   <-- redundante si ya sale como namevhost
# =========================================================
_ap_parse_vhosts() {
    awk '
        /^VirtualHost configuration:/ { in_vh=1; next }
        !in_vh { next }

        {
            # Formato Ubuntu/Debian:
            # *:80 example.com (/ruta:linea)
            # o IP:PUERTO
            #
            # Ignorar:
            # *:80 is a NameVirtualHost
            if ($1 ~ /^(\*|[0-9.]+):[0-9]+$/ && $2 != "is") {
                split($1, a, ":")
                print $2 "|" a[2]
                next
            }

            # Formato clásico RHEL/CentOS:
            # port 80 namevhost example.com (/ruta:linea)
            if ($1 == "port" && $3 == "namevhost") {
                print $4 "|" $2
                next
            }

            # Ignoramos a propósito:
            # default server example.com (...)
            # porque normalmente duplica al port XX namevhost
        }
    ' | sort -u
}

# =========================================================
# Mostrar info Apache (una instancia)
# =========================================================
show_apache_info() {
    _ap_require_common || return 1

    local COLS
    COLS=$(mdw_cols)

    # Columnas: ServerName/Alias | Puerto
    local W_PORT=6
    local W_SERVER_MIN=36
    local W_SERVER_MAX=80

    local ncols=2
    local overhead=$((3 * ncols + 1))
    local sum_fixed=$((W_PORT))

    local W_SERVER=$((COLS - (sum_fixed + overhead)))
    W_SERVER=$(mdw_clamp "$W_SERVER" "$W_SERVER_MIN" "$W_SERVER_MAX")

    local TABLE_W=$((W_SERVER + W_PORT + overhead))

    clear

    local APACHE_BIN
    APACHE_BIN=$(resolve_apache_bin)

    if [[ -z "$APACHE_BIN" ]]; then
        echo "No se ha encontrado Apache en la máquina"
        ui_pause
        return 1
    fi

    if has_multiple_apache_instances; then
        echo -e "${YELLOW}Detectadas múltiples instancias de Apache${NC}"
        show_all_apache_info
        return 0
    fi

    local APACHE_CTL
    APACHE_CTL=$(resolve_apache_ctl "$APACHE_BIN")

    local apache_version
    apache_version=$(get_apache_version "$APACHE_BIN")

    local SEP
    SEP="$(mdw_sep "$W_SERVER" "$W_PORT")"

    echo ""
    mdw_banner_table "LISTADO DE INFORMACION APACHE" "$TABLE_W"
    echo ""

    echo -e "${CYAN}Apache Version:${NC} $apache_version"
    echo -e "${CYAN}Binario:${NC} $APACHE_BIN"
    echo ""

    echo "$SEP"

    local header
    header=$(printf "| %-*s | %-*s |\n" \
        "$W_SERVER" "ServerName / Alias" \
        "$W_PORT" "Puerto")
    header="${YELLOW}${header}${NC}"
    mdw_yellow_pipes "$header"

    echo "$SEP"

    local -a vhosts=()
    mapfile -t vhosts < <(
        "$APACHE_CTL" -S 2>&1 | _ap_parse_vhosts
    )

    if [[ ${#vhosts[@]} -eq 0 ]]; then
        local row
        row=$(printf "| %-*s | %-*s |\n" \
            "$W_SERVER" "No hay VirtualHost definidos" \
            "$W_PORT" "-")
        mdw_yellow_pipes "$row"
        echo "$SEP"
        ui_pause
        return 0
    fi

    local vh servername port
    for vh in "${vhosts[@]}"; do
        servername=${vh%%|*}
        port=${vh##*|}

        servername=$(mdw_trunc "$servername" "$W_SERVER")

        local row
        row=$(printf "| %-*s | %-*s |\n" \
            "$W_SERVER" "$servername" \
            "$W_PORT" "$port")
        mdw_yellow_pipes "$row"
    done

    echo "$SEP"
    ui_pause
}

# =========================================================
# Mostrar info Apache (multi-instancia)
# =========================================================
show_all_apache_info() {
    _ap_require_common || return 1

    local COLS
    COLS=$(mdw_cols)

    local W_PORT=6
    local W_SERVER_MIN=36
    local W_SERVER_MAX=90

    local ncols=2
    local overhead=$((3 * ncols + 1))
    local sum_fixed=$((W_PORT))

    local W_SERVER=$((COLS - (sum_fixed + overhead)))
    W_SERVER=$(mdw_clamp "$W_SERVER" "$W_SERVER_MIN" "$W_SERVER_MAX")

    local TABLE_W=$((W_SERVER + W_PORT + overhead))
    local SEP
    SEP="$(mdw_sep "$W_SERVER" "$W_PORT")"

    clear
    echo ""
    mdw_banner_table "LISTADO DE INFORMACION APACHE (MULTI-INSTANCE)" "$TABLE_W"
    echo ""

    local -a CONFS=()
    while IFS= read -r conf; do
        [[ -n "$conf" ]] && CONFS+=("$conf")
    done < <(
        ps -ef | grep -E 'httpd|apache2' | grep root | grep -v grep | \
            sed -n 's/.*-f[[:space:]]*\([^[:space:]]*\).*/\1/p' | \
            sort -u
    )

    if (( ${#CONFS[@]} == 0 )); then
        echo "No se han detectado instancias Apache con -f"
        ui_pause
        return 0
    fi

    local conf
    for conf in "${CONFS[@]}"; do
        [[ -f "$conf" ]] || continue

        local bin
        bin=$(ps -ef | grep -E 'httpd|apache2' | grep root | grep -v grep | grep -F -- "$conf" | awk '{print $8}' | head -n1)
        [[ -x "$bin" ]] || bin=$(resolve_apache_bin)
        [[ -x "$bin" ]] || bin="(desconocido)"

        local apache_version
        if [[ -x "$bin" ]]; then
            apache_version=$(get_apache_version "$bin")
        else
            apache_version="Desconocida"
        fi

        echo -e "${CYAN}Instancia:${NC} $conf"
        echo -e "${CYAN}Apache Version:${NC} $apache_version"
        echo -e "${CYAN}Binario:${NC} $bin"
        echo ""

        echo "$SEP"
        local header
        header=$(printf "| %-*s | %-*s |\n" \
            "$W_SERVER" "ServerName / Alias" \
            "$W_PORT" "Puerto")
        header="${YELLOW}${header}${NC}"
        mdw_yellow_pipes "$header"
        echo "$SEP"

        local -a vhosts=()
        mapfile -t vhosts < <(
            "$bin" -f "$conf" -S 2>&1 | _ap_parse_vhosts
        )

        if (( ${#vhosts[@]} == 0 )); then
            local row
            row=$(printf "| %-*s | %-*s |\n" \
                "$W_SERVER" "No hay VirtualHost definidos" \
                "$W_PORT" "-")
            mdw_yellow_pipes "$row"
            echo "$SEP"
            echo ""
            continue
        fi

        local vh server port
        for vh in "${vhosts[@]}"; do
            server=${vh%%|*}
            port=${vh##*|}

            server=$(mdw_trunc "$server" "$W_SERVER")

            local row
            row=$(printf "| %-*s | %-*s |\n" \
                "$W_SERVER" "$server" \
                "$W_PORT" "$port")
            mdw_yellow_pipes "$row"
        done

        echo "$SEP"
        echo ""
    done

    ui_pause
}

# =========================================================
# MENÚ APACHE
# =========================================================
apache_menu() {
    menu_run_actions "APACHE" "Selecciona una opción: " back "$CYAN" \
        "Resumen / Tabla" "show_apache_info"
}
