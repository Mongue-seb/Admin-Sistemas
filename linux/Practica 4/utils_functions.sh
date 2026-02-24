#!/bin/bash

# COLORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- ENCAPSULAMIENTO: Verificar Root ---
verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Ejecuta este script con sudo.${NC}"
        exit 1
    fi
}

# --- ENCAPSULAMIENTO: Instalar Paquetes ---
instalar_paquetes() {
    local paquetes=$1
    echo -e "${YELLOW}Verificando paquetes: $paquetes ...${NC}"
    apt-get update > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y $paquetes > /dev/null 2>&1
    echo -e "${GREEN}Paquetes instalados/actualizados.${NC}"
}

# --- ENCAPSULAMIENTO: Validaciones IP ---
validar_ip_sintaxis() {
    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then return 0; else return 1; fi
}

es_ip_prohibida() {
    local ip=$1
    # Bloquear 0.0.0.0, Broadcast, Loopback y Multicast
    if [[ "$ip" == "0.0.0.0" ]] || [[ "$ip" == "255.255.255.255" ]]; then return 0; fi
    if [[ "$ip" == 127.* ]]; then return 0; fi
    local primer_octeto=$(echo $ip | cut -d'.' -f1)
    if (( primer_octeto >= 224 )); then return 0; fi
    return 1 # No es prohibida
}

validar_ip_completa() {
    local ip=$1
    if validar_ip_sintaxis "$ip"; then
        if ! es_ip_prohibida "$ip"; then return 0; else return 2; fi # 2 = Prohibida
    else return 1; fi # 1 = Mal formato
}

# --- HERRAMIENTAS DE RED ---
seleccionar_interfaz() {
    clear
    echo -e "${CYAN}--- SELECCION DE INTERFAZ ---${NC}"
    ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"
    echo -e "${YELLOW}Nota: Selecciona la red INTERNA (ej. enp0s8).${NC}"
    read -p "Nombre de la interfaz: " INTERFACE
    if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
        echo -e "${RED}Interfaz no encontrada.${NC}"; exit 1
    fi
    export INTERFACE
}

obtener_ip_actual() {
    ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1
}

configurar_firewall_base() {
    echo -e "${CYAN}Configurando reglas base de Firewall (ICMP/SSH)...${NC}"
    # UFW
    if command -v ufw >/dev/null 2>&1; then
        ufw allow in on $INTERFACE proto icmp > /dev/null 2>&1
        ufw allow ssh > /dev/null 2>&1
        ufw reload > /dev/null 2>&1
    fi
    # IPTABLES (Fallback)
    if command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT > /dev/null 2>&1
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT > /dev/null 2>&1
    fi
}

configurar_ip_estatica() {
    CURRENT_IP=$(obtener_ip_actual)
    echo -e "\n${YELLOW}--- CONFIGURAR IP ESTATICA ($INTERFACE) ---${NC}"
    echo "IP Actual: ${CURRENT_IP:-Ninguna}"
    
    read -p "Configurar nueva IP Estatica? (s/n): " resp
    if [[ "$resp" == "s" ]]; then
        while true; do
            read -p "Ingrese IP: " nueva_ip
            validar_ip_completa "$nueva_ip"
            res=$?
            if [ $res -eq 0 ]; then break;
            elif [ $res -eq 2 ]; then echo -e "${RED}IP Prohibida.${NC}";
            else echo -e "${RED}Formato invalido.${NC}"; fi
        done

        cp /etc/network/interfaces /etc/network/interfaces.bak 2>/dev/null
        cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback
allow-hotplug enp0s3
iface enp0s3 inet dhcp
auto $INTERFACE
iface $INTERFACE inet static
    address $nueva_ip
    netmask 255.255.255.0
EOF
        # Aplicacion inmediata sin bloqueo
        ip addr flush dev $INTERFACE
        ip addr add $nueva_ip/24 dev $INTERFACE
        ip link set $INTERFACE up
        echo "nameserver 127.0.0.1" > /etc/resolv.conf
        configurar_firewall_base
        echo -e "${GREEN}IP $nueva_ip asignada.${NC}"
    fi
}

ejecutar_pruebas() {
    echo -e "\n${CYAN}--- PRUEBAS DE RESOLUCION ---${NC}"
    read -p "Dominio a probar (ej. reprobados.com): " dom
    if [ -z "$dom" ]; then return; fi
    echo "Probando nslookup..."
    nslookup $dom localhost
    echo "Probando ping..."
    ping -c 2 $dom
}