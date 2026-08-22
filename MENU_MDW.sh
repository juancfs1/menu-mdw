#!/bin/bash
# Script_Version=2.1.2

# Menu principal. Cargamos las funciones de los diferentes ficheros, asi como la personalizacion de este host en el fichero ./lib/menu_mdw.conf

# GENERAL VARS - Colores ANSI para Bash
BLACK=$'\033[0;30m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
CYAN=$'\033[0;36m'
BROWN=$'\033[0;33m'
ORANGE=$'\033[38;5;208m'
NC=$'\033[0m'


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
current_machine=$(hostname -s)
MENU_CONF="$LIB_DIR/menu_mdw.conf"

if [[ ! -f "$MENU_CONF" ]]; then
    echo "ERROR: El fichero de configuración $MENU_CONF no existe."
    read -rp "Pulsa Enter para continuar..."
    exit 1
fi

source "$MENU_CONF"

if [[ -z "${SERVICES+x}" || ${#SERVICES[@]} -eq 0 ]]; then
    echo "ERROR: El fichero $MENU_CONF no contiene SERVICES o está vacío."
    read -rp "Pulsa Enter para continuar..."
    exit 1
fi

source "$LIB_DIR/common.sh"
source "$LIB_DIR/apache.sh"
source "$LIB_DIR/tomcat.sh"
source "$LIB_DIR/wildfly.sh"
source "$LIB_DIR/weblogic.sh"


validate_config || exit 1

menu_register "Apache"  "show_apache_info"
menu_register "Tomcat"  "show_tomcat_info"
menu_register "Wildfly" "show_wildfly_info"
menu_register "Weblogic" "show_weblogic_info"


#################### MAIN

main_menu
