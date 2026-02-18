#!/bin/bash

# ==============================================================================
# GESTOR INFRAESTRUCTURA V4: FINAL (DEBIAN/UBUNTU)
# ==============================================================================

# COLORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =========================
# 0. SELECCIÓN DE INTERFAZ
# =========================
seleccionar_interfaz() {
    clear
    echo -e "${CYAN}--- SELECCIÓN DE INTERFAZ DE RED ---${NC}"
    echo "Interfaces disponibles:"
    ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"
    
    echo -e "\n${YELLOW}NOTA: Selecciona la interfaz de RED INTERNA (no la NAT).${NC}"
    read -p "Escribe el nombre de la interfaz (ej. enp0s8): " INTERFACE

    if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
        echo -e "${RED}Error: La interfaz $INTERFACE no existe.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Trabajando sobre: $INTERFACE${NC}"
    sleep 1
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Ejecuta con sudo.${NC}"; exit 1
    fi
}

validar_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

obtener_ip_actual() {
    ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1
}

# =========================
# 1. GESTIÓN DE PAQUETES
# =========================

verificar_instalacion() {
    echo -e "\n${CYAN}--- VERIFICANDO PAQUETES INSTALADOS ---${NC}"
    
    # Verificar DHCP
    if dpkg -s isc-dhcp-server >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] DHCP Server (isc-dhcp-server)${NC}"
    else
        echo -e "${RED}[X]  DHCP Server NO instalado${NC}"
    fi

    # Verificar DNS
    if dpkg -s bind9 >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] DNS Server (bind9)${NC}"
    else
        echo -e "${RED}[X]  DNS Server NO instalado${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

instalar_roles() {
    echo -e "${YELLOW}Actualizando e instalando paquetes...${NC}"
    apt-get update > /dev/null 2>&1
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server bind9 bind9utils bind9-doc dnsutils net-tools > /dev/null 2>&1
    
    echo -e "${GREEN}Instalación completada.${NC}"
    read -p "Presiona Enter para continuar..."
}

# =========================
# 2. IP ESTÁTICA
# =========================

configurar_ip_estatica() {
    CURRENT_IP=$(obtener_ip_actual)
    echo -e "\n${YELLOW}--- CONFIGURACIÓN IP ESTÁTICA ($INTERFACE) ---${NC}"
    echo "IP Actual: ${CURRENT_IP:-Ninguna}"
    
    read -p "¿Configurar IP ESTATICA nueva (ej. 192.168.10.1)? (s/n): " resp
    if [[ "$resp" == "s" ]]; then
        read -p "Ingrese IP: " nueva_ip
        if validar_ip $nueva_ip; then
            echo -e "${CYAN}Escribiendo configuración persistente...${NC}"
            cp /etc/network/interfaces /etc/network/interfaces.bak 2>/dev/null
            
            cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# NAT (Internet - Opcional)
allow-hotplug enp0s3
iface enp0s3 inet dhcp

# RED INTERNA
auto $INTERFACE
iface $INTERFACE inet static
    address $nueva_ip
    netmask 255.255.255.0
EOF

            echo -e "${CYAN}Aplicando IP...${NC}"
            ip addr flush dev $INTERFACE
            ip addr add $nueva_ip/24 dev $INTERFACE
            ip link set $INTERFACE up
            
            echo "nameserver 127.0.0.1" > /etc/resolv.conf
            
            echo -e "${GREEN}IP $nueva_ip asignada a $INTERFACE.${NC}"
        else
            echo -e "${RED}IP Inválida.${NC}"
        fi
    fi
}

# =========================
# 3. CONFIGURACIÓN DHCP (FULL)
# =========================

configurar_dhcp() {
    SERVER_IP=$(obtener_ip_actual)
    if [ -z "$SERVER_IP" ]; then 
        echo -e "${RED}¡ALERTA! La interfaz $INTERFACE no tiene IP. Configura la IP Estática primero.${NC}"
        return
    fi

    echo -e "\n${YELLOW}--- CONFIGURAR SCOPE DHCP ---${NC}"
    # --- AQUI ESTA LA OPCION QUE PEDISTE (NOMBRE DEL AMBITO) ---
    read -p "Nombre del Ámbito DHCP (ej. Laboratorio): " scope_name
    
    read -p "IP Inicial (ej. 192.168.10.100): " ip_ini
    read -p "IP Final (ej. 192.168.10.200): " ip_fin
    
    read -p "Gateway (Enter para vacío): " gateway
    read -p "Tiempo de concesión (segundos) [Enter=28800]: " lease_time
    if [ -z "$lease_time" ]; then lease_time=28800; fi
    
    SUBNET=$(echo $SERVER_IP | cut -d'.' -f1-3).0
    
    echo -e "${CYAN}Generando configuración DHCP...${NC}"
    
    sed -i 's/^INTERFACESv4=.*/INTERFACESv4="'$INTERFACE'"/' /etc/default/isc-dhcp-server
    
    if [ ! -z "$gateway" ]; then
        ROUTER_LINE="option routers $gateway;"
    else
        ROUTER_LINE="# Sin Gateway configurado"
    fi

    # Inyectamos el nombre del ambito como comentario para referencia
    cat > /etc/dhcp/dhcpd.conf <<EOF
# Configuracion DHCP generada por Script
# Nombre del Ambito: $scope_name
default-lease-time 600;
max-lease-time $lease_time;
authoritative;

subnet $SUBNET netmask 255.255.255.0 {
  range $ip_ini $ip_fin;
  $ROUTER_LINE
  option domain-name-servers $SERVER_IP;
}
EOF
    
    echo -e "${YELLOW}Reiniciando servicio DHCP...${NC}"
    systemctl restart isc-dhcp-server
    sleep 2
    
    if systemctl is-active --quiet isc-dhcp-server; then
        echo -e "${GREEN}>>> CONFIGURACIÓN DHCP EXITOSA (Ámbito: $scope_name) <<<${NC}"
    else
        echo -e "${RED}FALLO: El servicio no arranca.${NC}"
        journalctl -xeu isc-dhcp-server | tail -n 5
    fi
}

# =========================
# 4. GESTIÓN DNS
# =========================

agregar_zona() {
    SERVER_IP=$(obtener_ip_actual)
    if [ -z "$SERVER_IP" ]; then SERVER_IP="127.0.0.1"; fi
    
    echo -e "\n${YELLOW}--- AGREGAR ZONA DNS ---${NC}"
    read -p "Nombre del Dominio (ej. reprobados.com): " dominio
    [ -z "$dominio" ] && return
    
    read -p "IP destino (Enter para $SERVER_IP): " target_ip
    [ -z "$target_ip" ] && target_ip=$SERVER_IP
    
    CONF="/etc/bind/named.conf.local"
    FILE="/var/lib/bind/db.$dominio"
    
    if grep -q "$dominio" "$CONF"; then
        echo -e "${RED}La zona ya existe.${NC}"
        read -p "¿Recrear? (s/n): " rec
        if [ "$rec" != "s" ]; then return; fi
    else
        cat >> $CONF <<EOF

zone "$dominio" {
    type master;
    file "$FILE";
};
EOF
    fi
    
    cat > $FILE <<EOF
; Data file for $dominio
\$TTL 604800
@ IN SOA ns1.$dominio. root.$dominio. ( 2 604800 86400 2419200 604800 )
@ IN NS ns1.$dominio.
@ IN A $target_ip
ns1 IN A $SERVER_IP
www IN A $target_ip
EOF
    
    chown bind:bind $FILE
    systemctl restart bind9
    echo -e "${GREEN}Zona '$dominio' CREADA exitosamente.${NC}"
}

eliminar_zona() {
    echo -e "\n${YELLOW}--- ELIMINAR ZONA DNS ---${NC}"
    CONF="/etc/bind/named.conf.local"
    echo "Zonas actuales:"
    grep "zone" "$CONF" | cut -d'"' -f2
    
    read -p "Nombre EXACTO de la zona a borrar: " zona_del
    if [ -z "$zona_del" ]; then return; fi
    
    if grep -q "$zona_del" "$CONF"; then
        cp $CONF "$CONF.bak"
        sed -i "/zone \"$zona_del\" {/,/};/d" $CONF
        rm -f "/var/lib/bind/db.$zona_del"
        systemctl restart bind9
        echo -e "${GREEN}Zona '$zona_del' ELIMINADA.${NC}"
    else
        echo -e "${RED}Zona no encontrada.${NC}"
    fi
}

listar_zonas() {
    echo -e "\n${CYAN}--- LISTADO DE DOMINIOS ---${NC}"
    if grep -q "zone" "/etc/bind/named.conf.local"; then
        grep "zone" "/etc/bind/named.conf.local" | awk '{print $2}' | tr -d '"'
    else
        echo "No hay zonas configuradas."
    fi
    read -p "Enter para volver..."
}

submenu_dns() {
    while true; do
        clear
        echo -e "\n${CYAN}=== GESTIÓN DE DOMINIOS DNS ===${NC}"
        echo "1) Agregar Dominio (Zona + www)"
        echo "2) Eliminar Dominio"
        echo "3) Ver Dominios Actuales"
        echo "4) Volver al Menú Principal"
        
        read -p "Seleccione opción: " subopc
        case $subopc in
            1) agregar_zona; read -p "Enter..." ;;
            2) eliminar_zona; read -p "Enter..." ;;
            3) listar_zonas ;;
            4) return ;;
            *) echo "Inválido" ;;
        esac
    done
}

# =========================
# 5. PRUEBAS
# =========================

ejecutar_pruebas() {
    echo -e "\n${CYAN}--- PRUEBAS DE RESOLUCIÓN ---${NC}"
    read -p "Dominio a probar (ej. reprobados.com): " dom
    if [ -z "$dom" ]; then return; fi
    nslookup $dom localhost
    ping -c 2 $dom
}

# =========================
# MENU PRINCIPAL
# =========================

check_root
sed -i 's/\r$//' "$0" 2>/dev/null # Fix saltos de linea Windows
seleccionar_interfaz

while true; do
    echo -e "\n${YELLOW}=======================================${NC}"
    echo -e "${YELLOW}   GESTOR DEBIAN V4 ($INTERFACE)   ${NC}"
    echo -e "${YELLOW}=======================================${NC}"
    echo "1) Verificar Instalación"
    echo "2) Instalar Roles (DHCP + DNS)"
    echo "3) Configurar IP Estática"
    echo "4) Configurar DHCP (Scope)"
    echo "5) Gestión de Dominios DNS (Submenú)"
    echo "6) Pruebas de Resolución"
    echo "7) Salir"
    
    read -p "Seleccione opción: " MAIN_OPC
    
    case $MAIN_OPC in
        1) verificar_instalacion ;;
        2) instalar_roles ;;
        3) configurar_ip_estatica ;;
        4) configurar_dhcp ;;
        5) submenu_dns ;;
        6) ejecutar_pruebas ;;
        7) exit 0 ;;
        *) echo "Opción inválida" ;;
    esac
done