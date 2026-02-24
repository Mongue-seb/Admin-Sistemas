#!/bin/bash

configurar_dhcp() {
    SERVER_IP=$(obtener_ip_actual)
    if [ -z "$SERVER_IP" ]; then echo -e "${RED}Error: Configura IP Estatica primero.${NC}"; return; fi

    echo -e "\n${YELLOW}--- CONFIGURACION DHCP ---${NC}"
    instalar_paquetes "isc-dhcp-server"

    read -p "Nombre del Ambito: " scope_name
    
    # Input Loop: IP Inicial
    while true; do
        read -p "IP Inicial: " ip_ini
        validar_ip_completa "$ip_ini"
        if [ $? -eq 0 ]; then break; else echo -e "${RED}IP invalida.${NC}"; fi
    done

    # Input Loop: IP Final
    while true; do
        read -p "IP Final: " ip_fin
        validar_ip_completa "$ip_fin"
        if [ $? -eq 0 ]; then break; else echo -e "${RED}IP invalida.${NC}"; fi
    done
    
    # Gateway Opcional
    gateway=""
    while true; do
        read -p "Gateway (Enter para vacio): " input_gw
        if [ -z "$input_gw" ]; then break; fi
        validar_ip_completa "$input_gw"
        if [ $? -eq 0 ]; then gateway=$input_gw; break; else echo -e "${RED}IP invalida.${NC}"; fi
    done

    # Lease Time (Enteros positivos)
    lease_time=28800
    while true; do
        read -p "Tiempo concesion [Enter=28800]: " input_lease
        if [ -z "$input_lease" ]; then break; fi
        if [[ "$input_lease" =~ ^[0-9]+$ ]] && [ "$input_lease" -gt 0 ]; then
            lease_time=$input_lease; break
        else echo -e "${RED}Debe ser entero positivo.${NC}"; fi
    done
    
    SUBNET=$(echo $SERVER_IP | cut -d'.' -f1-3).0
    
    # Configuracion
    sed -i 's/^INTERFACESv4=.*/INTERFACESv4="'$INTERFACE'"/' /etc/default/isc-dhcp-server
    
    ROUTER_LINE=$([ ! -z "$gateway" ] && echo "option routers $gateway;" || echo "# Sin Gateway")

    cat > /etc/dhcp/dhcpd.conf <<EOF
# Ambito: $scope_name
default-lease-time 600;
max-lease-time $lease_time;
authoritative;
subnet $SUBNET netmask 255.255.255.0 {
  range $ip_ini $ip_fin;
  $ROUTER_LINE
  option domain-name-servers $SERVER_IP;
}
EOF
    
    echo "Reiniciando servicio..."
    systemctl restart isc-dhcp-server; sleep 2
    if systemctl is-active --quiet isc-dhcp-server; then
        echo -e "${GREEN}DHCP Configurado Exitosamente.${NC}"
    else
        echo -e "${RED}Fallo al iniciar DHCP.${NC}"
        journalctl -xeu isc-dhcp-server | tail -n 3
    fi
}