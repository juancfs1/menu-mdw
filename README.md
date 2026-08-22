# Middleware Management Menu

A Bash-based administration and inventory tool for Linux middleware environments.

The project provides an interactive menu for inspecting and managing middleware services while keeping technology-specific logic separated into reusable modules.

## Features

- Interactive middleware management menu.
- Service detection through `systemd` with SysV fallback.
- Basic service status, PID and user information.
- Technology-specific inventory and operational information.
- Apache instance and VirtualHost discovery.
- Tomcat instance, Java, ports and deployed application discovery.
- WildFly standalone/domain discovery, ports and deployments.
- Oracle WebLogic server, Java, memory, CPU, ports, deployments and JDBC datasource discovery.
- Configuration-driven service and middleware mappings.
- Reusable configuration templates for different middleware technologies.
- Terminal-friendly tables that adapt to the available terminal width.

## Supported technologies

| Technology | Inventory / management capabilities |
|---|---|
| Apache HTTP Server | Instances, version, PID, status and VirtualHosts |
| Apache Tomcat | Instances, version, Java, CPU, memory, ports and applications |
| WildFly | Standalone/domain mode, version, Java, CPU, memory, ports and deployments |
| Oracle WebLogic | Servers, Java, CPU, memory, ports, applications and JDBC datasources |

## Architecture

```text
MENU_MDW.sh
    |
    +-- lib/common.sh       # Shared service, menu and formatting functions
    +-- lib/apache.sh       # Apache-specific logic
    +-- lib/tomcat.sh       # Tomcat-specific logic
    +-- lib/wildfly.sh      # WildFly-specific logic
    +-- lib/weblogic.sh     # WebLogic-specific logic
    +-- lib/menu_mdw.conf   # Host-specific configuration (not committed)
    |
    +-- templates/          # Example configurations
```

The main script loads the shared engine and technology modules, while the configuration file describes the middleware services present on a target host.

## Requirements

- Linux host.
- Bash 4+ recommended.
- `systemd` or SysV-style service management.
- Standard Linux utilities such as `ps`, `awk`, `sed`, `grep`, `find` and `ss` where applicable.
- Access permissions appropriate for inspecting and managing the target services.
- Python 3 is recommended for the WebLogic XML parsing features.

The tool is designed for administration environments where middleware components are registered as operating-system services.

## Installation

Clone or copy the repository to the target Linux host. The application is portable and does not require a fixed installation directory.

```bash
git clone <repository-url>
cd menu_mdw
cp lib/menu_mdw.conf.example lib/menu_mdw.conf
chmod +x MENU_MDW.sh
./MENU_MDW.sh
```

The configuration file is intentionally excluded from Git so host-specific infrastructure information is not accidentally committed.

## Configuration

Edit `lib/menu_mdw.conf` according to the middleware installed on the target host.

The main configuration variables are:

- `SERVICES` — operating-system services managed by the tool.
- `TECHNOLOGIES` — middleware technologies enabled on the host.
- `TOMCAT_INSTANCES` — Tomcat installation directories.
- `WILDFLY_INSTANCES` — WildFly installation directories.
- `WILDFLY_MODES` — WildFly operating mode for each configured instance.
- `WEBLOGIC_SERVICE_MAP` — mapping between OS services and WebLogic server names/types.
- `WEBLOGIC_DOMAINS` — WebLogic domain directories.

Use the files under `templates/` as starting points for technology-specific configurations.

## Usage

Run:

```bash
./MENU_MDW.sh
```

The interactive menu provides three main areas:

1. **Basic status** — service state, PID and user.
2. **Detailed technology information** — middleware-specific inventory.
3. **Service operations** — stop, restart and start configured services.

> Service operations require the appropriate operating-system privileges.

## Security considerations

This project is intended for controlled Linux administration environments.

- Keep `lib/menu_mdw.conf` local to the target host.
- Do not commit internal hostnames, IP addresses, database URLs, domain paths or other infrastructure-specific information.
- Run service operations only with the privileges required by the target environment.
- Review the configuration before using start/stop/restart operations on production systems.

## Project structure

```text
menu_mdw/
├── MENU_MDW.sh
├── README.md
├── .gitignore
├── lib/
│   ├── common.sh
│   ├── apache.sh
│   ├── menu_mdw.conf.example
│   ├── tomcat.sh
│   ├── weblogic.sh
│   └── wildfly.sh
└── templates/
    ├── menu_mdw_apache_template.conf
    ├── menu_mdw_tomcat_template.conf
    ├── menu_mdw_weblogic_template.conf
    └── menu_mdw_wildfly_template.conf
```

## Roadmap

Potential future improvements include:

- More robust PID resolution across custom service definitions.
- Automated configuration validation and self-checks.
- Non-interactive command-line operations for automation.
- Additional middleware technologies.
- Automated tests for parsers and inventory functions.
- Optional Python-based infrastructure automation components.

## Project background

This project is based on practical middleware administration requirements and focuses on making repetitive Linux middleware inspection and service-management tasks faster and more consistent.
