#!/bin/bash

instalar_ssh() {
    echo -e "\n${CYAN}--- INSTALACION SSH (ACCESO REMOTO) ---${NC}"
    
    # Usamos la funcion encapsulada
    instalar_paquetes "openssh-server"
    
    echo -e "${YELLOW}Habilitando servicio...${NC}"
    systemctl enable ssh > /dev/null 2>&1
    systemctl start ssh
    
    configurar_firewall_base
    
    echo -e "${GREEN}SSH Instalado y Activo.${NC}"
    echo -e "${CYAN}HITO CRITICO: Conectate ahora desde tu cliente usando:${NC}"
    echo -e "ssh usuario@$(obtener_ip_actual)"
}