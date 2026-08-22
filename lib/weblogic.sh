# Script_Version=1.4.1 - Revisadas funciones no utilizadas y purgado errores

# =========================================================
# RECURSOS DEL SISTEMA
# =========================================================
wl_get_total_mem_kb() {
    awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null
}

wl_get_cpu_cores() {
    local n
    n=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    [[ -z "$n" || "$n" -lt 1 ]] && n=1
    echo "$n"
}

WL_TOTAL_MEM_KB=$(wl_get_total_mem_kb)
WL_CPU_CORES=$(wl_get_cpu_cores)

# =========================================================
# PYTHON DISPONIBLE
# =========================================================
wl_get_python_bin() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        echo "python"
    else
        echo ""
    fi
}

WL_PYTHON_BIN=$(wl_get_python_bin)

# =========================================================
# HELPERS CONFIG.XML
# =========================================================
wl_get_config_xml() {
    local domain_home="$1"
    echo "${domain_home}/config/config.xml"
}

wl_xml_get() {
    local mode="$1"
    local cfg="$2"

    [[ -n "$WL_PYTHON_BIN" ]] || return 1
    [[ -f "$cfg" ]] || return 1

    "$WL_PYTHON_BIN" - "$mode" "$cfg" <<'PY'
import sys
import xml.etree.ElementTree as ET

mode = sys.argv[1]
cfg = sys.argv[2]

def lname(tag):
    return tag.split('}', 1)[-1]

def child_text(elem, child_name, default=""):
    for ch in list(elem):
        if lname(ch.tag) == child_name:
            return (ch.text or "").strip()
    return default

tree = ET.parse(cfg)
root = tree.getroot()

if mode == "domain_name":
    print(child_text(root, "name", ""))
elif mode == "admin_server":
    print(child_text(root, "admin-server-name", "AdminServer"))
elif mode == "managed_servers":
    admin = child_text(root, "admin-server-name", "AdminServer")
    for ch in list(root):
        if lname(ch.tag) != "server":
            continue
        name = child_text(ch, "name", "")
        port = child_text(ch, "listen-port", "-")
        cluster = child_text(ch, "cluster", "")
        machine = child_text(ch, "machine", "")
        if name and name != admin:
            print(f"{name}|{port}|{cluster}|{machine}")
PY
}

wl_get_domain_name() {
    local domain_home="$1"
    local cfg
    cfg=$(wl_get_config_xml "$domain_home")

    if [[ -n "$WL_PYTHON_BIN" && -f "$cfg" ]]; then
        local out
        out=$(wl_xml_get "domain_name" "$cfg" 2>/dev/null)
        [[ -n "$out" ]] && { echo "$out"; return; }
    fi

    basename "$domain_home"
}

# Devuelve líneas: server|port|cluster|machine
wl_list_managed_servers() {
    local domain_home="$1"
    local cfg
    cfg=$(wl_get_config_xml "$domain_home")

    [[ -n "$WL_PYTHON_BIN" && -f "$cfg" ]] || return 0
    wl_xml_get "managed_servers" "$cfg" 2>/dev/null
}

# =========================================================
# MACHINE / LOCALIDAD
# =========================================================
wl_is_local_server() {
    local server_name="$1"
    local entry svc srv srv_type

    [[ -z "${WEBLOGIC_SERVICE_MAP+x}" ]] && return 1

    for entry in "${WEBLOGIC_SERVICE_MAP[@]}"; do
        IFS=':' read -r svc srv srv_type <<< "$entry"

        if [[ "$srv" == "$server_name" ]]; then
            return 0
        fi
    done

    return 1
}

# =========================================================
# HELPERS PROCESO WEBLOGIC
# =========================================================
resolve_service_pid_custom() {
    local service_name="$1"
    local entry svc srv srv_type

    [[ -z "${WEBLOGIC_SERVICE_MAP+x}" ]] && {
        echo "-"
        return
    }

    for entry in "${WEBLOGIC_SERVICE_MAP[@]}"; do
        IFS=':' read -r svc srv srv_type <<< "$entry"

        [[ "$svc" != "$service_name" ]] && continue

        case "$srv" in
            NodeManager)
                ps -efww 2>/dev/null | grep '[N]odeManager' | awk '{print $2}' | head -n1
                return
                ;;
            *)
                ps -efww 2>/dev/null | grep "[D]weblogic.Name=${srv}" | awk '{print $2}' | head -n1
                return
                ;;
        esac
    done

    echo "-"
}

wl_get_server_pid() {
    local domain_home="$1"
    local server_name="$2"

    ps -efww 2>/dev/null | grep "[D]weblogic.Name=${server_name}" | awk '{ print $2 }' | head -n1
}

wl_get_java_cmdline() {
    local pid="$1"
    [[ -z "$pid" ]] && return

    if [[ -r "/proc/$pid/cmdline" ]]; then
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null
        return
    fi

    ps -p "$pid" -o args= -ww 2>/dev/null
}

wl_get_xms() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "-"; return; }

    local cmd val
    cmd=$(wl_get_java_cmdline "$pid")
    val=$(echo "$cmd" | grep -oE -- '-Xms[^[:space:]]+' | head -n1)
    [[ -n "$val" ]] && echo "${val#-Xms}" || echo "-"
}

wl_get_xmx() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "-"; return; }

    local cmd val
    cmd=$(wl_get_java_cmdline "$pid")
    val=$(echo "$cmd" | grep -oE -- '-Xmx[^[:space:]]+' | head -n1)
    [[ -n "$val" ]] && echo "${val#-Xmx}" || echo "-"
}

# CPU: proc/total
wl_get_cpu_usage() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "-/-"; return; }

    local cpu_proc cpu_total
    cpu_proc=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}')
    [[ -z "$cpu_proc" ]] && { echo "-/-"; return; }

    cpu_total=$(awk -v c="$cpu_proc" -v n="$WL_CPU_CORES" 'BEGIN{ if(n<1)n=1; printf "%.1f", (c/n) }')
    echo "${cpu_proc}/${cpu_total}"
}

# MEM: MB/%
wl_get_mem_usage() {
    local pid="$1"
    [[ -z "$pid" ]] && { echo "-/-"; return; }

    local rss_kb mem_mb mem_pct
    rss_kb=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print $1}')
    [[ -z "$rss_kb" || ! "$rss_kb" =~ ^[0-9]+$ ]] && { echo "-/-"; return; }

    mem_mb=$(awk -v r="$rss_kb" 'BEGIN{ printf "%.0f", (r/1024) }')

    if [[ -n "$WL_TOTAL_MEM_KB" && "$WL_TOTAL_MEM_KB" -gt 0 ]]; then
        mem_pct=$(awk -v r="$rss_kb" -v t="$WL_TOTAL_MEM_KB" 'BEGIN{ printf "%.1f", (r*100/t) }')
    else
        mem_pct="-"
    fi

    echo "${mem_mb}/${mem_pct}"
}

# =========================================================
# XMS / XMX EN PARADO
# =========================================================
wl_get_xms_from_domain_scripts() {
    local domain_home="$1"
    local xms file

    for file in \
        "$domain_home/bin/setUserOverrides.sh" \
        "$domain_home/bin/setDomainEnv.sh" \
        "$domain_home/bin/startManagedWebLogic.sh"
    do
        [[ -f "$file" ]] || continue

        xms=$(grep -Eo -- '-Xms[0-9]+[mMgGkK]?' "$file" 2>/dev/null | head -n1)
        if [[ -n "$xms" ]]; then
            echo "${xms#-Xms}"
            return
        fi
    done

    echo "-"
}

wl_get_xmx_from_domain_scripts() {
    local domain_home="$1"
    local xmx file

    for file in \
        "$domain_home/bin/setUserOverrides.sh" \
        "$domain_home/bin/setDomainEnv.sh" \
        "$domain_home/bin/startManagedWebLogic.sh"
    do
        [[ -f "$file" ]] || continue

        xmx=$(grep -Eo -- '-Xmx[0-9]+[mMgGkK]?' "$file" 2>/dev/null | head -n1)
        if [[ -n "$xmx" ]]; then
            echo "${xmx#-Xmx}"
            return
        fi
    done

    echo "-"
}

wl_get_xms_effective() {
    local domain_home="$1"
    local pid="$2"

    if [[ -n "$pid" ]]; then
        wl_get_xms "$pid"
    else
        wl_get_xms_from_domain_scripts "$domain_home"
    fi
}

wl_get_xmx_effective() {
    local domain_home="$1"
    local pid="$2"

    if [[ -n "$pid" ]]; then
        wl_get_xmx "$pid"
    else
        wl_get_xmx_from_domain_scripts "$domain_home"
    fi
}

# =========================================================
# APLICACIONES DESPLEGADAS
# =========================================================
wl_get_managed_apps() {
    local domain_home="$1"
    local server_name="$2"
    local cluster_name="$3"
    local cfg
    cfg=$(wl_get_config_xml "$domain_home")

    [[ -n "$WL_PYTHON_BIN" && -f "$cfg" ]] || return 0

    "$WL_PYTHON_BIN" - "apps" "$cfg" "$server_name" "$cluster_name" <<'PY'
import sys
import xml.etree.ElementTree as ET

cfg = sys.argv[2]
server_name = sys.argv[3]
cluster_name = sys.argv[4]

def lname(tag):
    return tag.split('}', 1)[-1]

def child_text(elem, child_name, default=""):
    for ch in list(elem):
        if lname(ch.tag) == child_name:
            return (ch.text or "").strip()
    return default

tree = ET.parse(cfg)
root = tree.getroot()

apps = set()
for ch in list(root):
    if lname(ch.tag) != "app-deployment":
        continue
    name = child_text(ch, "name", "")
    target = child_text(ch, "target", "")
    if not name or not target:
        continue

    targets = [x.strip() for x in target.split(",") if x.strip()]
    if server_name in targets or (cluster_name and cluster_name != "-" and cluster_name in targets):
        apps.add(name)

for name in sorted(apps):
    print(name)
PY
}

wl_print_apps_block() {
    local apps="$1"
    local full_w="$2"

    local count=0
    if [[ -z "$apps" ]]; then
        local r1 r2
        r1=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$full_w" "Aplicaciones desplegadas (0):" "${NC}")
        r2=$(printf "| %-*s |\n" "$full_w" "  (ninguna)")
        mdw_yellow_pipes "$r1"
        mdw_yellow_pipes "$r2"
        return
    fi

    while IFS= read -r app; do
        [[ -n "$app" ]] && ((count++))
    done <<< "$apps"

    local header
    header=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$full_w" "Aplicaciones desplegadas (${count}):" "${NC}")
    mdw_yellow_pipes "$header"

    while IFS= read -r app; do
        [[ -z "$app" ]] && continue
        local row
        row=$(printf "| %-*s |\n" "$full_w" "  - $app")
        mdw_yellow_pipes "$row"
    done <<< "$apps"
}

# =========================================================
# DATASOURCES JDBC
# =========================================================
wl_get_managed_jdbcs() {
    local domain_home="$1"
    local server_name="$2"
    local cluster_name="$3"
    local cfg

    cfg=$(wl_get_config_xml "$domain_home")
    [[ -n "$WL_PYTHON_BIN" && -f "$cfg" ]] || return 0

    "$WL_PYTHON_BIN" - "$cfg" "$domain_home" "$server_name" "$cluster_name" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

cfg = sys.argv[1]
domain_home = sys.argv[2]
server_name = sys.argv[3]
cluster_name = sys.argv[4]

def lname(tag):
    return tag.split('}', 1)[-1]

def child_text(elem, child_name, default=""):
    for ch in list(elem):
        if lname(ch.tag) == child_name:
            return (ch.text or "").strip()
    return default

def find_first_desc_text(elem, names, default=""):
    wanted = set(names)
    for sub in elem.iter():
        if lname(sub.tag) in wanted:
            txt = (sub.text or "").strip()
            if txt:
                return txt
    return default

try:
    tree = ET.parse(cfg)
    root = tree.getroot()
except Exception:
    sys.exit(0)

jdbc_resources = []

for ch in list(root):
    if lname(ch.tag) != "jdbc-system-resource":
        continue

    ds_name = child_text(ch, "name", "")
    ds_file = child_text(ch, "descriptor-file-name", "")
    target = child_text(ch, "target", "")

    if not ds_name or not ds_file or not target:
        continue

    targets = [x.strip() for x in target.split(",") if x.strip()]
    applies = server_name in targets or (cluster_name and cluster_name != "-" and cluster_name in targets)
    if not applies:
        continue

    full_path = os.path.join(domain_home, "config", ds_file)
    url = "-"

    if os.path.isfile(full_path):
        try:
            ds_tree = ET.parse(full_path)
            ds_root = ds_tree.getroot()

            real_name = find_first_desc_text(ds_root, ["name"], ds_name)
            if real_name:
                ds_name = real_name

            url = find_first_desc_text(ds_root, ["url"], "-")
        except Exception:
            pass

    jdbc_resources.append((ds_name, url))

for ds_name, url in sorted(set(jdbc_resources), key=lambda x: x[0].lower()):
    print(f"{ds_name}|{url}")
PY
}

wl_print_jdbcs_block() {
    local jdbcs="$1"
    local full_w="$2"

    local count=0
    if [[ -z "$jdbcs" ]]; then
        local r1 r2
        r1=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$full_w" "Datasources configurados (0):" "${NC}")
        r2=$(printf "| %-*s |\n" "$full_w" "  (ninguno)")
        mdw_yellow_pipes "$r1"
        mdw_yellow_pipes "$r2"
        return
    fi

    while IFS= read -r ds; do
        [[ -n "$ds" ]] && ((count++))
    done <<< "$jdbcs"

    local header
    header=$(printf "| %b%-*s%b |\n" "${YELLOW}" "$full_w" "Datasources configurados (${count}):" "${NC}")
    mdw_yellow_pipes "$header"

    local line ds_name ds_url text
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        IFS='|' read -r ds_name ds_url <<< "$line"

        text="  - ${ds_name}"
        [[ -n "$ds_url" && "$ds_url" != "-" ]] && text="${text} -> ${ds_url}"

        mapfile -t LINES < <(mdw_wrap "$text" "$full_w")

        local i row
        for ((i=0; i<${#LINES[@]}; i++)); do
            if [[ $i -eq 0 ]]; then
                row=$(printf "| %-*s |\n" "$full_w" "${LINES[i]}")
            else
                row=$(printf "| %-*s |\n" "$full_w" "    ${LINES[i]}")
            fi
            mdw_yellow_pipes "$row"
        done
    done <<< "$jdbcs"
}

# =========================================================
# UI
# =========================================================
show_weblogic_info() {
    if [[ -z "${WEBLOGIC_DOMAINS+x}" || "${#WEBLOGIC_DOMAINS[@]}" -eq 0 ]]; then
        echo "No hay dominios WebLogic definidos en WEBLOGIC_DOMAINS."
        ui_pause
        return 0
    fi

    if [[ -z "$WL_PYTHON_BIN" ]]; then
        echo "No se ha encontrado python/python3. Este módulo necesita uno de ellos para parsear config.xml."
        ui_pause
        return 1
    fi

    local W_SERVER=30
    local W_DOMAIN=18
    local W_CLUSTER=18
    local W_PORT=8
    local W_RUN=9
    local W_PID=8
    local W_CPU=12
    local W_MEM=14
    local W_XMS=10
    local W_XMX=10

    local TABLE_W=$((W_SERVER + W_DOMAIN + W_CLUSTER + W_PORT + W_RUN + W_PID + W_CPU + W_MEM + W_XMS + W_XMX + (3*10) + 1))
    local FULL_W=$((TABLE_W - 4))

    clear
    echo ""
    mdw_banner_table "LISTADO DE INFORMACION WEBLOGIC" "$TABLE_W"
    echo ""

    local SEP
    SEP="$(mdw_sep "$W_SERVER" "$W_DOMAIN" "$W_CLUSTER" "$W_PORT" "$W_RUN" "$W_PID" "$W_CPU" "$W_MEM" "$W_XMS" "$W_XMX")"
    echo "$SEP"

    local header
    header=$(printf "| %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
        "$W_SERVER"  "Managed Server" \
        "$W_DOMAIN"  "Dominio" \
        "$W_CLUSTER" "Cluster" \
        "$W_PORT"    "Puerto" \
        "$W_RUN"     "Run" \
        "$W_PID"     "PID" \
        "$W_CPU"     "CPU(p/t)" \
        "$W_MEM"     "Mem(MB/%)" \
        "$W_XMS"     "XMS" \
        "$W_XMX"     "XMX")
    header="${YELLOW}${header}${NC}"
    mdw_yellow_pipes "$header"
    echo "$SEP"

    local domain_home
    for domain_home in "${WEBLOGIC_DOMAINS[@]}"; do
        local domain_name
        domain_name=$(wl_get_domain_name "$domain_home")
        [[ -z "$domain_name" ]] && domain_name=$(basename "$domain_home")

        local found=0
        local sorted_entries

        sorted_entries=$(
            while IFS= read -r entry; do
                [[ -z "$entry" ]] && continue

                local server_name port cluster machine
                IFS='|' read -r server_name port cluster machine <<< "$entry"

                wl_is_local_server "$server_name" || continue

                printf "%s\n" "$entry"
            done < <(wl_list_managed_servers "$domain_home") | sort -t'|' -k1,1
        )

        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            found=1

            local server_name port cluster machine
            IFS='|' read -r server_name port cluster machine <<< "$entry"

            [[ -z "$port" ]] && port="-"
            [[ -z "$cluster" ]] && cluster="-"

            local pid runtime_state pid_print cpu mem xms xmx
            pid=$(wl_get_server_pid "$domain_home" "$server_name")

            if [[ -n "$pid" ]]; then
                runtime_state="RUNNING"
                pid_print="$pid"
                cpu=$(wl_get_cpu_usage "$pid")
                mem=$(wl_get_mem_usage "$pid")
            else
                runtime_state="STOPPED"
                pid_print="-"
                cpu="-/-"
                mem="-/-"
            fi

            xms=$(wl_get_xms_effective "$domain_home" "$pid")
            xmx=$(wl_get_xmx_effective "$domain_home" "$pid")

            local run_col run_pad
            run_pad=$(printf "%-*s" "$W_RUN" "$runtime_state")

            case "$runtime_state" in
                RUNNING) run_col="${GREEN}${run_pad}${NC}" ;;
                STOPPED) run_col="${RED}${run_pad}${NC}" ;;
                *)       run_col="$run_pad" ;;
            esac

            local row
            row=$(printf "| %-*s | %-*s | %-*s | %-*s | %s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
                "$W_SERVER"  "$(mdw_trunc "$server_name" "$W_SERVER")" \
                "$W_DOMAIN"  "$(mdw_trunc "$domain_name" "$W_DOMAIN")" \
                "$W_CLUSTER" "$(mdw_trunc "$cluster" "$W_CLUSTER")" \
                "$W_PORT"    "$port" \
                "$run_col" \
                "$W_PID"     "$pid_print" \
                "$W_CPU"     "$cpu" \
                "$W_MEM"     "$mem" \
                "$W_XMS"     "$xms" \
                "$W_XMX"     "$xmx")
            mdw_yellow_pipes "$row"

            local apps
            apps=$(wl_get_managed_apps "$domain_home" "$server_name" "$cluster")
            wl_print_apps_block "$apps" "$FULL_W"

            local jdbcs
            jdbcs=$(wl_get_managed_jdbcs "$domain_home" "$server_name" "$cluster")
            wl_print_jdbcs_block "$jdbcs" "$FULL_W"

            echo "$SEP"
        done <<< "$sorted_entries"

        if [[ "$found" -eq 0 ]]; then
            local row
            row=$(printf "| %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s | %-*s |\n" \
                "$W_SERVER"  "(sin manageds)" \
                "$W_DOMAIN"  "$(mdw_trunc "$domain_name" "$W_DOMAIN")" \
                "$W_CLUSTER" "-" \
                "$W_PORT"    "-" \
                "$W_RUN"     "-" \
                "$W_PID"     "-" \
                "$W_CPU"     "-" \
                "$W_MEM"     "-" \
                "$W_XMS"     "-" \
                "$W_XMX"     "-")
            mdw_yellow_pipes "$row"
            echo "$SEP"
        fi
    done

    ui_pause
}
