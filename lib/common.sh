#Script_Version=5.0. Se permite que TECHNOLOGIES sea una matriz vacia para poder gestionar de forma básica cualquier servicio
#
# =========================================================
# COMMON.SH - Motor central + Servicios + Menús + Formato
# =========================================================

WEBLOGIC_STOP_TIMEOUT=120

# =========================================================
# DETECCIÓN GESTOR SERVICIOS
# =========================================================
detect_service_manager() {
    if command -v systemctl &>/dev/null && pidof systemd &>/dev/null; then
        SERVICE_MANAGER="systemd"
    else
        SERVICE_MANAGER="sysv"
    fi
}
detect_service_manager

# =========================================================
# FORMATO TABLAS (mdw_*)
# =========================================================
mdw_cols() {
    local c
    c=$(tput cols 2>/dev/null)
    [[ "$c" =~ ^[0-9]+$ ]] || c=160
    echo "$c"
}

mdw_banner_table() {
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

mdw_trunc() {
    local s="$1" w="$2"
    [[ -z "$s" ]] && { echo ""; return; }
    if (( ${#s} <= w )); then
        printf "%s" "$s"
    else
        printf "%s…" "${s:0:w-1}"
    fi
}

mdw_wrap() {
    echo -n "$1" | fold -s -w "$2"
}

mdw_yellow_pipes() {
    echo -e "$(echo "$1" | sed "s/|/${YELLOW}|${NC}/g")"
}

mdw_sep() {
    local fmt="+"
    local args=()
    local w
    for w in "$@"; do
        fmt+="-%-*s-+"
        args+=("$w" "")
    done
    fmt+="\n"

    local line
    # shellcheck disable=SC2059
    line=$(printf "$fmt" "${args[@]}" | tr ' ' '-')
    echo -e "${YELLOW}${line}${NC}"
}

mdw_clamp() {
    local v="$1" min="$2" max="$3"
    (( v < min )) && v=$min
    (( v > max )) && v=$max
    echo "$v"
}

# =========================================================
# UI HELPERS (ui_*) -> menús
# =========================================================
ui_cols() {
    local c
    c=$(tput cols 2>/dev/null)
    [[ "$c" =~ ^[0-9]+$ ]] || c=120
    echo "$c"
}

ui_line() {
    local cols="${1:-$(ui_cols)}"
    printf '%*s\n' "$cols" '' | tr ' ' '='
}

ui_line_color() {
    local color="$1"
    local cols="${2:-$(ui_cols)}"
    echo -e "${color}$(ui_line "$cols")${NC}"
}

ui_center_text() {
    local text="$1"
    local cols="${2:-$(ui_cols)}"

    local len=${#text}

    if (( len >= cols )); then
        printf "%s\n" "${text:0:cols}"
        return
    fi

    local left=$(( (cols - len) / 2 ))
    printf "%*s%s\n" "$left" "" "$text"
}

ui_title_line() {
    local title="$1"
    local cols="${2:-$(ui_cols)}"

    local mid=" ${title} "
    local mid_len=${#mid}

    if (( mid_len >= cols )); then
        printf "%s\n" "${mid:0:cols}"
        return
    fi

    local left=$(( (cols - mid_len) / 2 ))
    local right=$(( cols - mid_len - left ))

    local left_pad right_pad
    left_pad=$(printf '%*s' "$left" '' | tr ' ' '=')
    right_pad=$(printf '%*s' "$right" '' | tr ' ' '=')

    printf "%s%s%s\n" "$left_pad" "$mid" "$right_pad"
}

ui_banner() {
    local title="$1"
    local cols="${2:-$(ui_cols)}"
    local color="${3:-$CYAN}"
    echo -e "${color}"
    ui_line "$cols"
    ui_title_line "$title" "$cols"
    ui_line "$cols"
    echo -e "${NC}"
}

ui_pause() {
    read -rp "Pulsa Enter para continuar..."
}

# =========================================================
# MOTOR MENÚ REUTILIZABLE
# =========================================================
menu_run_actions() {
    local title="$1"; shift
    local prompt="${1:-Selecciona una opción: }"; shift
    local mode="${1:-back}"; shift
    local banner_color="${1:-$CYAN}"; shift

    local -a labels=()
    local -a funcs=()
    while (( $# >= 2 )); do
        labels+=( "$1" )
        funcs+=( "$2" )
        shift 2
    done

    while true; do
        clear
        local cols
        cols=$(ui_cols)
        ui_banner "$title" "$cols" "$banner_color"
        echo ""

        local i
        for i in "${!labels[@]}"; do
            if [[ -z "${labels[$i]}" ]]; then
                echo ""
                continue
            fi
            echo -e " $((i+1))) ${labels[$i]}${NC}"
        done

        echo ""

        if [[ "$mode" == "back" ]]; then
            echo " 0) Volver"
        else
            echo -e " ${MAGENTA}0) Salir${NC}"
        fi

        ui_line "$cols"
        local choice
        read -rp "$prompt" choice

        if [[ "$choice" == "0" ]]; then
            if [[ "$mode" == "back" ]]; then
                return 0
            else
                menu_exit
            fi
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#labels[@]} )); then
            local fn="${funcs[$((choice-1))]}"
            "$fn"
        else
            echo "Opción inválida"
            sleep 1
        fi
    done
}

# =========================================================
# MENÚ TECNOLOGÍAS
# =========================================================
declare -Ag MENU_ACTIONS=()

menu_register() {
    local label="$1"
    local fn="$2"
    [[ -n "$label" && -n "$fn" ]] || return 1
    MENU_ACTIONS["$label"]="$fn"
}

menu_run_registered() {
    local title="$1"; shift
    local prompt="${1:-Selecciona una opción: }"; shift
    local show_back="${1:-1}"; shift
    local banner_color="${1:-$CYAN}"; shift
    local -a items=( "$@" )

    while true; do
        clear
        local cols
        cols=$(ui_cols)
        ui_banner "$title" "$cols" "$banner_color"
        echo ""

        local i=1 item
        for item in "${items[@]}"; do
            echo " $i) $item"
            ((i++))
        done

        if [[ "$show_back" == "1" ]]; then
            echo " 0) Volver"
        fi

        ui_line "$cols"
        local choice
        read -rp "$prompt" choice

        if [[ "$show_back" == "1" && "$choice" == "0" ]]; then
            return 0
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<i )); then
            local selected="${items[$((choice-1))]}"
            local fn="${MENU_ACTIONS[$selected]:-}"

            if [[ -n "$fn" ]] && declare -F "$fn" >/dev/null; then
                "$fn"
            else
                echo "No hay acción registrada para: $selected"
                ui_pause
            fi
        else
            echo "Opción inválida"
            sleep 1
        fi
    done
}

technology_management_menu() {
    local host_upper
    host_upper=$(hostname -s | tr '[:lower:]' '[:upper:]')

    local -a available=()
    local tech
    for tech in "${TECHNOLOGIES[@]}"; do
        if [[ -n "${MENU_ACTIONS[$tech]:-}" ]] && declare -F "${MENU_ACTIONS[$tech]}" >/dev/null; then
            available+=( "$tech" )
        fi
    done

    if (( ${#available[@]} == 0 )); then
        echo "No hay tecnologías registradas."
        ui_pause
        return 0
    fi

    menu_run_registered "TECNOLOGIAS MIDDLEWARE ${host_upper}" "Selecciona la tecnología: " 1 "$CYAN" "${available[@]}"
}

# =========================================================
# SERVICIOS
# =========================================================

# ---------------------------------------------------------
# Helpers WebLogic
# ---------------------------------------------------------
wl_get_map_entry() {
    local service_name="$1"
    local entry cfg_service wl_name wl_type

    [[ -z "${WEBLOGIC_SERVICE_MAP[*]}" ]] && return 1

    for entry in "${WEBLOGIC_SERVICE_MAP[@]}"; do
        IFS=':' read -r cfg_service wl_name wl_type <<< "$entry"
        if [[ "$cfg_service" == "$service_name" ]]; then
            echo "$entry"
            return 0
        fi
    done

    return 1
}

is_weblogic_service() {
    local service_name="$1"
    wl_get_map_entry "$service_name" >/dev/null 2>&1
}

wl_get_real_name() {
    local service_name="$1"
    local entry cfg_service wl_name wl_type

    entry="$(wl_get_map_entry "$service_name")" || return 1
    IFS=':' read -r cfg_service wl_name wl_type <<< "$entry"
    echo "$wl_name"
}

wl_get_type() {
    local service_name="$1"
    local entry cfg_service wl_name wl_type

    entry="$(wl_get_map_entry "$service_name")" || return 1
    IFS=':' read -r cfg_service wl_name wl_type <<< "$entry"
    echo "$wl_type"
}

wl_get_domain() {
    [[ ${#WEBLOGIC_DOMAINS[@]} -gt 0 ]] || return 1
    echo "${WEBLOGIC_DOMAINS[0]}"
}

wl_get_stop_script() {
    local domain="$1"
    local wl_type="$2"

    case "$wl_type" in
        adminserver) echo "$domain/bin/stopWebLogic.sh" ;;
        nodemanager) echo "$domain/bin/stopNodeManager.sh" ;;
        managed)     echo "$domain/bin/stopManagedWebLogic.sh" ;;
        *) return 1 ;;
    esac
}

wl_build_stop_command() {
    local service_name="$1"
    local domain wl_name wl_type script

    domain="$(wl_get_domain)" || return 1
    wl_name="$(wl_get_real_name "$service_name")" || return 1
    wl_type="$(wl_get_type "$service_name")" || return 1
    script="$(wl_get_stop_script "$domain" "$wl_type")" || return 1

    case "$wl_type" in
        managed)
            printf '"%s" "%s"' "$script" "$wl_name"
            ;;
        adminserver|nodemanager)
            printf '"%s"' "$script"
            ;;
        *)
            return 1
            ;;
    esac
}

wl_run_as_oracle_bg() {
    local raw_cmd="$1"
    local wl_user="${WEBLOGIC_OS_USER:-oracle}"

    [[ -z "$raw_cmd" ]] && return 1

    local wrapped_cmd
    wrapped_cmd="nohup bash -c $(printf "%q" "$raw_cmd") >/dev/null 2>&1 &"

    if command -v runuser >/dev/null 2>&1; then
        runuser -l "$wl_user" -c "$wrapped_cmd"
    else
        su - "$wl_user" -c "$wrapped_cmd"
    fi
}

# ---------------------------------------------------------
# Nombre visible
# ---------------------------------------------------------
resolve_service_display_name() {
    local service_name="$1"
    local display_name="$service_name"

    if [[ -n "${WEBLOGIC_SERVICE_MAP[*]}" ]]; then
        local entry wl_service wl_name wl_type
        for entry in "${WEBLOGIC_SERVICE_MAP[@]}"; do
            IFS=':' read -r wl_service wl_name wl_type <<< "$entry"
            if [[ "$wl_service" == "$service_name" ]]; then
                display_name="$wl_name"
                break
            fi
        done
    fi

    echo "$display_name"
}

# ---------------------------------------------------------
# PID
# ---------------------------------------------------------
resolve_service_pid() {
    local service_name="$1"
    local pid="-"

    if declare -F resolve_service_pid_custom >/dev/null; then
        pid=$(resolve_service_pid_custom "$service_name")
        [[ -n "$pid" && "$pid" != "-" ]] && { echo "$pid"; return; }
    fi

    if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
        pid=$(systemctl show "$service_name" -p MainPID 2>/dev/null | cut -d= -f2)
        [[ -z "$pid" || "$pid" == "0" ]] && pid="-"
        [[ "$pid" != "-" ]] && { echo "$pid"; return; }
    fi

    pid=$(pgrep -f "$service_name" 2>/dev/null | head -n1)
    [[ -n "$pid" ]] && { echo "$pid"; return; }

    echo "-"
}

# ---------------------------------------------------------
# Estado servicio SO
# ---------------------------------------------------------
get_system_service_status() {
    local service_name="$1"

    if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
        systemctl is-active --quiet "$service_name"
        [[ $? -eq 0 ]] && echo "RUNNING" || echo "STOPPED"
    else
        service "$service_name" status &>/dev/null
        [[ $? -eq 0 ]] && echo "RUNNING" || echo "STOPPED"
    fi
}

# ---------------------------------------------------------
# Estado proceso real
# ---------------------------------------------------------
get_process_status() {
    local service_name="$1"
    local pid

    pid=$(resolve_service_pid "$service_name")
    if [[ -n "$pid" && "$pid" != "-" ]]; then
        echo "RUNNING"
    else
        echo "STOPPED"
    fi
}

# ---------------------------------------------------------
# Estado efectivo
# - WebLogic: servicio o proceso
# - Resto: solo servicio
# ---------------------------------------------------------
get_effective_runtime_status() {
    local service_name="$1"

    if is_weblogic_service "$service_name"; then
        local proc_status
        proc_status=$(get_process_status "$service_name")

        if [[ "$proc_status" == "RUNNING" ]]; then
            echo "RUNNING"
        else
            echo "STOPPED"
        fi
        return
    fi

    get_system_service_status "$service_name"
}
is_service_running() {
    local service_name="$1"
    [[ "$(get_effective_runtime_status "$service_name")" == "RUNNING" ]]
}

# ---------------------------------------------------------
# Validaciones
# - Solo WebLogic hace doble comprobación en arranque
# ---------------------------------------------------------
can_start_service() {
    local service_name="$1"

    if is_weblogic_service "$service_name"; then
        local service_status process_status
        service_status=$(get_system_service_status "$service_name")
        process_status=$(get_process_status "$service_name")
        [[ "$service_status" == "STOPPED" && "$process_status" == "STOPPED" ]]
        return $?
    fi

    [[ "$(get_system_service_status "$service_name")" == "STOPPED" ]]
}

can_stop_service() {
    local service_name="$1"

    if is_weblogic_service "$service_name"; then
        local service_status process_status
        service_status=$(get_system_service_status "$service_name")
        process_status=$(get_process_status "$service_name")
        [[ "$service_status" == "RUNNING" || "$process_status" == "RUNNING" ]]
        return $?
    fi

    [[ "$(get_system_service_status "$service_name")" == "RUNNING" ]]
}

# ---------------------------------------------------------
# Espera a parada completa
# ---------------------------------------------------------
wait_until_stopped() {
    local s="$1"
    local timeout="${2:-30}"
    local i

    for ((i=0; i<timeout; i++)); do
        if ! is_service_running "$s"; then
            return 0
        fi
        sleep 1
    done

    return 1
}

# ---------------------------------------------------------
# Operaciones estándar
# ---------------------------------------------------------
start_standard_service() {
    local s="$1"
    local display_name
    display_name=$(resolve_service_display_name "$s")

    if ! can_start_service "$s"; then
        if is_weblogic_service "$s"; then
            echo -e "${YELLOW}INFO:${NC} No se puede arrancar '${display_name}' porque ya existe un servicio o proceso WebLogic en ejecución."
        else
            echo -e "${YELLOW}INFO:${NC} El servicio '${display_name}' ya está ${GREEN}RUNNING${NC}."
        fi
        return 0
    fi

    [[ "$SERVICE_MANAGER" == "systemd" ]] && systemctl start "$s" || service "$s" start
    local rc=$?

    (( rc == 0 )) \
        && echo -e "${GREEN}OK:${NC} Servicio '${display_name}' arrancado." \
        || echo -e "${RED}ERROR:${NC} No se pudo arrancar '${display_name}' (rc=${rc})."

    return "$rc"
}

stop_standard_service() {
    local s="$1"
    local display_name
    display_name=$(resolve_service_display_name "$s")

    if ! can_stop_service "$s"; then
        if is_weblogic_service "$s"; then
            echo -e "${YELLOW}INFO:${NC} El servicio '${display_name}' ya está ${RED}STOPPED${NC} y no existe proceso WebLogic activo asociado."
        else
            echo -e "${YELLOW}INFO:${NC} El servicio '${display_name}' ya está ${RED}STOPPED${NC}."
        fi
        return 0
    fi

    [[ "$SERVICE_MANAGER" == "systemd" ]] && systemctl stop "$s" || service "$s" stop
    local rc=$?

    (( rc == 0 )) \
        && echo -e "${GREEN}OK:${NC} Servicio '${display_name}' parado." \
        || echo -e "${RED}ERROR:${NC} No se pudo parar '${display_name}' (rc=${rc})."

    return "$rc"
}

restart_standard_service() {
    local s="$1"
    local display_name
    display_name=$(resolve_service_display_name "$s")

    echo -e "${YELLOW}INFO:${NC} Reiniciando '${display_name}'..."

    if can_stop_service "$s"; then
        [[ "$SERVICE_MANAGER" == "systemd" ]] && systemctl stop "$s" || service "$s" stop
        local rc=$?
        (( rc != 0 )) && {
            echo -e "${RED}ERROR:${NC} No se pudo parar '${display_name}' (rc=${rc})."
            return "$rc"
        }

        if ! wait_until_stopped "$s" 30; then
            echo -e "${RED}ERROR:${NC} '${display_name}' no terminó de parar en el tiempo esperado."
            return 1
        fi
    else
        echo -e "${YELLOW}INFO:${NC} '${display_name}' ya estaba parado. Se procederá al arranque."
    fi

    [[ "$SERVICE_MANAGER" == "systemd" ]] && systemctl start "$s" || service "$s" start
    local rc=$?

    (( rc == 0 )) \
        && echo -e "${GREEN}OK:${NC} Servicio '${display_name}' arrancado." \
        || echo -e "${RED}ERROR:${NC} No se pudo arrancar '${display_name}' (rc=${rc})."

    return "$rc"
}

# ---------------------------------------------------------
# Operaciones WebLogic especiales
# ---------------------------------------------------------
stop_weblogic_by_script() {
    local s="$1"
    local display_name cmd rc

    display_name=$(resolve_service_display_name "$s")

    cmd="$(wl_build_stop_command "$s")" || {
        echo -e "${RED}ERROR:${NC} No se pudo construir el comando de parada por script para '${display_name}'."
        return 1
    }

    echo -e "${CYAN}INFO:${NC} Lanzando parada por script como usuario oracle..."

    wl_run_as_oracle_bg "$cmd"
    rc=$?

    if (( rc != 0 )); then
        echo -e "${RED}ERROR:${NC} No se pudo lanzar la parada por script."
        return "$rc"
    fi

    #Esperamos 120 sg antes de matar
    wl_wait_and_force_kill "$s" "${WEBLOGIC_STOP_TIMEOUT:-120}"
    return $?
}

start_weblogic_service() {
    local s="$1"
    local display_name service_status process_status rc

    display_name=$(resolve_service_display_name "$s")
    service_status=$(get_system_service_status "$s")
    process_status=$(get_process_status "$s")

    if [[ "$process_status" == "RUNNING" ]]; then
        echo -e "${YELLOW}INFO:${NC} No se puede arrancar '${display_name}' porque ya existe un proceso WebLogic en ejecución."
        return 0
    fi

    if [[ "$service_status" == "RUNNING" && "$process_status" == "STOPPED" ]]; then
        echo -e "${YELLOW}INFO:${NC} Detectado servicio activo pero proceso caído para '${display_name}'. Se reiniciará el servicio."

        [[ "$SERVICE_MANAGER" == "systemd" ]] && systemctl stop "$s" || service "$s" stop
        rc=$?
        if (( rc != 0 )); then
            echo -e "${RED}ERROR:${NC} No se pudo parar '${display_name}' antes de relanzarlo (rc=${rc})."
            return "$rc"
        fi

        sleep 2
    fi

    if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
        systemctl start "$s"
    else
        service "$s" start
    fi
    rc=$?

    if (( rc != 0 )); then
        echo -e "${RED}ERROR:${NC} No se pudo lanzar el arranque de '${display_name}' (rc=${rc})."
        return "$rc"
    fi

    wl_wait_until_started "$s" "${WEBLOGIC_START_TIMEOUT:-120}"
}

stop_weblogic_service() {
    local s="$1"
    local display_name service_status process_status

    display_name=$(resolve_service_display_name "$s")
    service_status=$(get_system_service_status "$s")
    process_status=$(get_process_status "$s")

    if [[ "$service_status" == "RUNNING" ]]; then
        [[ "$SERVICE_MANAGER" == "systemd" ]] && systemctl stop "$s" || service "$s" stop
        local rc=$?

        (( rc == 0 )) \
            && echo -e "${GREEN}OK:${NC} Servicio '${display_name}' parado por servicio." \
            || echo -e "${RED}ERROR:${NC} No se pudo parar '${display_name}' por servicio (rc=${rc})."

        return "$rc"
    fi

    if [[ "$service_status" == "STOPPED" && "$process_status" == "RUNNING" ]]; then
        stop_weblogic_by_script "$s"
        return $?
    fi

    echo -e "${YELLOW}INFO:${NC} El servicio '${display_name}' ya está ${RED}STOPPED${NC} y no existe proceso WebLogic activo asociado."
    return 0
}

restart_weblogic_service() {
    local s="$1"
    local display_name
    display_name=$(resolve_service_display_name "$s")

    echo -e "${YELLOW}INFO:${NC} Reiniciando '${display_name}'..."

    if can_stop_service "$s"; then
        stop_weblogic_service "$s" || return 1

        if ! wait_until_stopped "$s" 60; then
            echo -e "${RED}ERROR:${NC} '${display_name}' no terminó de parar en el tiempo esperado."
            return 1
        fi
    else
        echo -e "${YELLOW}INFO:${NC} '${display_name}' ya estaba parado. Se procederá al arranque."
    fi

    start_weblogic_service "$s"
}

wl_wait_and_force_kill() {
    local s="$1"
    local display_name pid timeout i

    display_name=$(resolve_service_display_name "$s")
    timeout="${2:-${WEBLOGIC_STOP_TIMEOUT:-120}}"

    echo -e "${CYAN}INFO:${NC} Esperando hasta ${timeout}s a que '${display_name}' termine de parar..."

    for ((i=1; i<=timeout; i++)); do
        pid=$(resolve_service_pid "$s")

        # ✔️ Si ya ha parado → salir
        if [[ -z "$pid" || "$pid" == "-" ]]; then
            echo -e "${GREEN}OK:${NC} '${display_name}' parado correctamente en ${i}s."
            return 0
        fi

        # Mostrar progreso cada 15s
        if (( i % 15 == 0 )); then
            echo -e "${YELLOW}INFO:${NC} '${display_name}' sigue en ejecución tras ${i}s..."
        fi

        sleep 1
    done

    # Timeout → kill
    pid=$(resolve_service_pid "$s")

    if [[ -n "$pid" && "$pid" != "-" ]]; then
        echo -e "${YELLOW}WARN:${NC} '${display_name}' no se ha parado tras ${timeout}s. Forzando parada (kill)..."

        kill -9 "$pid" 2>/dev/null
        sleep 2

        pid=$(resolve_service_pid "$s")
        if [[ -z "$pid" || "$pid" == "-" ]]; then
            echo -e "${GREEN}OK:${NC} '${display_name}' forzado a parada correctamente."
            return 0
        else
            echo -e "${RED}ERROR:${NC} No se pudo matar el proceso de '${display_name}'."
            return 1
        fi
    fi

    return 0
}

wl_wait_until_started() {
    local s="$1"
    local display_name pid timeout i

    display_name=$(resolve_service_display_name "$s")
    timeout="${2:-${WEBLOGIC_START_TIMEOUT:-120}}"

    echo -e "${CYAN}INFO:${NC} Esperando hasta ${timeout}s a que '${display_name}' arranque..."

    for ((i=1; i<=timeout; i++)); do
        pid=$(resolve_service_pid "$s")

        if [[ -n "$pid" && "$pid" != "-" ]]; then
            echo -e "${GREEN}OK:${NC} '${display_name}' arrancado correctamente en ${i}s (PID=${pid})."
            return 0
        fi

        if (( i % 15 == 0 )); then
            echo -e "${YELLOW}INFO:${NC} '${display_name}' sigue sin levantar tras ${i}s..."
        fi

        sleep 1
    done

    echo -e "${RED}ERROR:${NC} '${display_name}' no ha arrancado tras ${timeout}s."
    return 1
}

# ---------------------------------------------------------
# Dispatcher único
# ---------------------------------------------------------
start_service() {
    local s="$1"

    if is_weblogic_service "$s"; then
        start_weblogic_service "$s"
    else
        start_standard_service "$s"
    fi
}

stop_service() {
    local s="$1"

    if is_weblogic_service "$s"; then
        stop_weblogic_service "$s"
    else
        stop_standard_service "$s"
    fi
}

restart_service() {
    local s="$1"

    if is_weblogic_service "$s"; then
        restart_weblogic_service "$s"
    else
        restart_standard_service "$s"
    fi
}

# ---------------------------------------------------------
# Estado formateado
# ---------------------------------------------------------
get_formatted_service_status() {
    local service_name="$1"
    local display_name status pid owner status_col status_pad

    display_name=$(resolve_service_display_name "$service_name")
    pid=$(resolve_service_pid "$service_name")
    status=$(get_effective_runtime_status "$service_name")

    owner="-"
    if [[ "$pid" != "-" ]]; then
        owner=$(ps -o user= -p "$pid" 2>/dev/null | awk '{print $1}')
        [[ -z "$owner" ]] && owner="-"
    fi

    status_pad=$(printf "%-8s" "$status")

    case "$status" in
        RUNNING)
            status_col="${GREEN}${status_pad}${NC}"
            ;;
        STOPPED)
            status_col="${RED}${status_pad}${NC}"
            ;;
        *)
            status_col="$status_pad"
            ;;
    esac

    printf "| %-32s | %s | %-10s | %-8s |\n" \
        "$display_name" "$status_col" "$pid" "$owner"
}

# =========================================================
# LISTAR SERVICIOS
# =========================================================
list_processes() {
    clear
    local cols
    cols=$(ui_cols)
    ui_banner "ESTADO SERVICIOS $(hostname -s | tr '[:lower:]' '[:upper:]')" "$cols" "$BLUE"
    echo ""

    printf "| %-32s | %-8s | %-10s | %-8s |\n" "Servicio" "Status" "PID" "User"
    ui_line "$cols"

    local service
    for service in "${SERVICES[@]}"; do
        get_formatted_service_status "$service"
    done

    ui_line "$cols"
    ui_pause
}

# =========================================================
# SUBMENÚ SERVICIOS
# =========================================================
service_select_menu() {
    local action="$1"
    local color title

    case "$action" in
        start)   title="ARRANCAR SERVICIO"; color="$GREEN" ;;
        stop)    title="PARAR SERVICIO"; color="$RED" ;;
        restart) title="REINICIAR SERVICIO"; color="$YELLOW" ;;
        *)       title="SERVICIOS"; color="$CYAN" ;;
    esac

    while true; do
        clear
        ui_banner "$title" "$(ui_cols)" "$color"
        echo ""

        local i=1
        local service display_name status status_col status_pad
        for service in "${SERVICES[@]}"; do
            display_name=$(resolve_service_display_name "$service")
            status=$(get_effective_runtime_status "$service")
            status_pad=$(printf "%-8s" "$status")

            case "$status" in
                RUNNING)
                    status_col="${GREEN}${status_pad}${NC}"
                    ;;
                STOPPED)
                    status_col="${RED}${status_pad}${NC}"
                    ;;
                *)
                    status_col="$status_pad"
                    ;;
            esac

            printf " %d) %-32s [%s]\n" "$i" "$display_name" "$status_col"
            ((i++))
        done

        echo ""
        echo ""
        echo ""
        echo " 0) Volver"
        ui_line_color "$color"

        local choice
        read -rp "Selecciona servicio: " choice
        [[ "$choice" == "0" ]] && return

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<i )); then
            local s="${SERVICES[$((choice-1))]}"

            case "$action" in
                start)
                    start_service "$s"
                    ;;
                stop)
                    stop_service "$s"
                    ;;
                restart)
                    restart_service "$s"
                    ;;
                *)
                    echo "Acción no soportada"
                    ;;
            esac
            ui_pause
        fi
    done
}

# =========================================================
# VALIDACIÓN DE CONFIGURACIÓN
# =========================================================

config_error() {
    local msg="$1"
    echo -e "${RED}ERROR CONFIG:${NC} ${msg}"
}

config_warn() {
    local msg="$1"
    echo -e "${YELLOW}WARN CONFIG:${NC} ${msg}"
}

is_array_declared() {
    local var_name="$1"
    declare -p "$var_name" >/dev/null 2>&1
}

array_length() {
    local var_name="$1"
    eval "echo \${#$var_name[@]}"
}

validate_required_array_nonempty() {
    local var_name="$1"
    local description="$2"

    if ! is_array_declared "$var_name"; then
        config_error "Falta definir ${var_name} (${description})."
        return 1
    fi

    local len
    len=$(array_length "$var_name")
    if [[ -z "$len" || "$len" -eq 0 ]]; then
        config_error "${var_name} está definido pero vacío (${description})."
        return 1
    fi

    return 0
}

validate_weblogic_service_map_format() {
    local entry
    local idx=0
    local ok=0

    for entry in "${WEBLOGIC_SERVICE_MAP[@]}"; do
        ((idx++))

        # Formato esperado: alias:nombre_real:tipo
        if [[ ! "$entry" =~ ^[^:]+:[^:]+:[^:]+$ ]]; then
            config_error "WEBLOGIC_SERVICE_MAP entrada #${idx} inválida: '${entry}'. Formato esperado: alias:nombre_real:tipo"
            ok=1
            continue
        fi

        local alias real_name wl_type
        IFS=':' read -r alias real_name wl_type <<< "$entry"

        if [[ -z "$alias" || -z "$real_name" || -z "$wl_type" ]]; then
            config_error "WEBLOGIC_SERVICE_MAP entrada #${idx} incompleta: '${entry}'."
            ok=1
            continue
        fi

        case "$wl_type" in
            adminserver|nodemanager|managed)
                ;;
            *)
                config_error "WEBLOGIC_SERVICE_MAP entrada #${idx} con tipo no válido: '${wl_type}'. Valores admitidos: adminserver, nodemanager, managed."
                ok=1
                ;;
        esac
    done

    [[ "$ok" -eq 0 ]]
}

validate_weblogic_services_vs_map() {
    local services_len map_len
    local entry map_alias found service
    local rc=0

    services_len=${#SERVICES[@]}
    map_len=${#WEBLOGIC_SERVICE_MAP[@]}

    if [[ "$services_len" -lt "$map_len" ]]; then
        config_error "SERVICES (${services_len}) no puede tener menos elementos que WEBLOGIC_SERVICE_MAP (${map_len})."
        rc=1
    fi

    for entry in "${WEBLOGIC_SERVICE_MAP[@]}"; do
        IFS=':' read -r map_alias _ <<< "$entry"
        found=0

        for service in "${SERVICES[@]}"; do
            if [[ "$service" == "$map_alias" ]]; then
                found=1
                break
            fi
        done

        if [[ "$found" -eq 0 ]]; then
            config_error "La entrada '${map_alias}' de WEBLOGIC_SERVICE_MAP no aparece en SERVICES."
            rc=1
        fi
    done

    return "$rc"
}

validate_weblogic_domains() {
    local domain
    local rc=0

    for domain in "${WEBLOGIC_DOMAINS[@]}"; do
        if [[ ! -d "$domain" ]]; then
            config_warn "El dominio WebLogic '${domain}' no existe o no es accesible."
            continue
        fi

        if [[ ! -f "$domain/config/config.xml" ]]; then
            config_warn "No existe config.xml en '${domain}/config/config.xml'."
        fi
    done

    return "$rc"
}

validate_weblogic_config() {
    local rc=0

    validate_required_array_nonempty "WEBLOGIC_SERVICE_MAP" "mapa alias:nombre_real:tipo de WebLogic" || rc=1
    validate_required_array_nonempty "WEBLOGIC_DOMAINS" "lista de dominios WebLogic" || rc=1

    if [[ "$rc" -eq 0 ]]; then
        validate_weblogic_service_map_format || rc=1
        validate_weblogic_services_vs_map || rc=1
        validate_weblogic_domains
    fi

    return "$rc"
}

validate_tomcat_instances_format() {
    local entry
    local idx=0
    local rc=0

    for entry in "${TOMCAT_INSTANCES[@]}"; do
        ((idx++))
        [[ -z "$entry" ]] && {
            config_error "TOMCAT_INSTANCES contiene una entrada vacía en posición ${idx}."
            rc=1
        }
    done

    return "$rc"
}

validate_tomcat_config() {
    local rc=0

    validate_required_array_nonempty "TOMCAT_INSTANCES" "lista de instancias Tomcat" || rc=1

    if [[ "$rc" -eq 0 ]]; then
        validate_tomcat_instances_format || rc=1
    fi

    return "$rc"
}

validate_apache_config() {
    # De momento no imponemos obligatorios específicos.
    # Se deja la función preparada para crecer.
    return 0
}

validate_common_config() {
    local rc=0

    validate_required_array_nonempty "SERVICES" "lista de servicios gestionables" || rc=1

    if [[ "$rc" -eq 0 ]]; then
        validate_services_exist|| rc=1
    fi

    return "$rc"
}

validate_config() {
    local rc=0
    local tech

    validate_common_config || rc=1

    if [[ "$rc" -ne 0 ]]; then
        return 1
    fi

    if [[ -z "${TECHNOLOGIES+x}" || ${#TECHNOLOGIES[@]} -eq 0 ]]; then
        return "$rc"
    fi

    for tech in "${TECHNOLOGIES[@]}"; do
        case "${tech,,}" in
            weblogic)
                validate_weblogic_config || rc=1
                ;;
            tomcat)
                validate_tomcat_config || rc=1
                ;;
            apache|httpd)
                validate_apache_config || rc=1
                ;;
            *)
                config_warn "No hay validación específica implementada para la tecnología '${tech}'."
                ;;
        esac
    done

    return "$rc"
}

validate_services_exist (){
    local rc=0
    local service

    if [[ "$SERVICE_MANAGER" != "systemd" ]]; then
        config_warn "No se valida existencia en systemctl porque el gestor detectado no es systemd."
        return 0
    fi

    for service in "${SERVICES[@]}"; do
        if ! systemctl list-unit-files "${service}.service" --no-legend 2>/dev/null | grep -q "^${service}.service"; then
            if ! systemctl status "$service" >/dev/null 2>&1; then
                config_error "El servicio '${service}' no existe o no está definido en systemd."
                rc=1
            fi
        fi
    done

    return "$rc"
}

# =========================================================
# MENÚ PRINCIPAL
# =========================================================
main_menu() {
    local host_upper
    host_upper=$(hostname -s | tr '[:lower:]' '[:upper:]')

    while true; do
        clear
        local cols
        cols=$(ui_cols)

        ui_banner "MENÚ GESTIÓN MIDDLEWARE - NODO ${host_upper}" "$cols" "$BLUE"
        echo ""

        ui_line_color "$YELLOW" "$cols"
        ui_center_text "Listar información" "$cols"
        ui_line_color "$YELLOW" "$cols"
        echo " 1) Estado básico General"
        echo " 2) Estado detallado por tecnología"
        echo ""

        ui_line_color "$YELLOW" "$cols"
        ui_center_text "Arranque/parada de servicios" "$cols"
        ui_line_color "$YELLOW" "$cols"
        echo -e " 3) ${RED}Parar un servicio${NC}"
        echo -e " 4) Reiniciar un servicio${NC}"
        echo -e " 5) ${GREEN}Arrancar un servicio${NC}"
        echo ""
        echo ""
        echo ""

        ui_line_color "$YELLOW" "$cols"
        echo -e "0) Salir${NC}"
        ui_line_color "$YELLOW" "$cols"

        local choice
        read -rp "Selecciona una opción: " choice

        case "$choice" in
            1) list_processes ;;
            2) technology_management_menu ;;
            3) menu_stop_service ;;
            4) menu_restart_service ;;
            5) menu_start_service ;;
            0) menu_exit ;;
            *)
                echo "Opción inválida"
                sleep 1
                ;;
        esac
    done
}

menu_start_service() { service_select_menu "start"; }
menu_stop_service() { service_select_menu "stop"; }
menu_restart_service() { service_select_menu "restart"; }
menu_exit() { exit 0; }
