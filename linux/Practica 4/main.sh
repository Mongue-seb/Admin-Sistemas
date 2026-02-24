#!/bin/bash

# Cargar Modulos (Source)
source ./utils_functions.sh
source ./ssh_functions.sh
source ./dhcp_functions.sh
source ./dns_functions.sh

# Ejecucion Inicial
verificar_root
# Fix por si se copio de Windows
sed -i 's/\r$//' ./*.sh 2>/dev/null

seleccionar_interfaz
configurar_firewall_base

while true; do
    echo -e "\n${YELLOW}======== MAIN: GESTOR LINUX MODULAR ($INTERFACE) ========${NC}"
    echo "0) [HITO CRITICO] Instalar SSH para Acceso Remoto"
    echo "1) Verificar Instalacion"
    echo "2) Instalar Roles (Manual)"
    echo "3) Configurar IP Estatica"
    echo "4) Configurar DHCP (Scope)"
    echo "5) Gestion DNS (ABC Dominios)"
    echo "6) Pruebas de Resolucion"
    echo "7) Salir"
    
    read -p "Seleccione opcion: " MAIN_OPC
    
    case $MAIN_OPC in
        0) instalar_ssh ;;
        1) 
           echo "--- ESTADO ---"
           if dpkg -s isc-dhcp-server >/dev/null 2>&1; then echo -e "${GREEN}[OK] DHCP${NC}"; else echo -e "${RED}[X] DHCP${NC}"; fi
           if dpkg -s bind9 >/dev/null 2>&1; then echo -e "${GREEN}[OK] DNS${NC}"; else echo -e "${RED}[X] DNS${NC}"; fi
           ;;
        2) instalar_paquetes "isc-dhcp-server bind9 bind9utils dnsutils net-tools" ;;
        3) configurar_ip_estatica ;;
        4) configurar_dhcp ;;
        5) menu_dns ;;
        6) ejecutar_pruebas ;;
        7) exit 0 ;;
        *) echo "Opcion invalida" ;;
    esac
done