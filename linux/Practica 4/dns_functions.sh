#!/bin/bash

menu_dns() {
    instalar_paquetes "bind9 bind9utils dnsutils"
    SERVER_IP=$(obtener_ip_actual); [ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"
    
    while true; do
        echo -e "\n${CYAN}--- GESTION DNS (BIND9) ---${NC}"
        echo "1) Agregar Dominio"
        echo "2) Eliminar Dominio"
        echo "3) Ver Dominios"
        echo "4) Volver"
        read -p "Opcion: " opc
        
        case $opc in
            1) 
               read -p "Nombre Dominio: " dom; [ -z "$dom" ] && continue
               
               # Validacion IP Destino
               target_ip=$SERVER_IP
               while true; do
                   read -p "IP Destino (Enter para $SERVER_IP): " input_tip
                   if [ -z "$input_tip" ]; then break; fi
                   validar_ip_completa "$input_tip"
                   if [ $? -eq 0 ]; then target_ip=$input_tip; break; else echo "IP invalida"; fi
               done
               
               FILE="/var/lib/bind/db.$dom"; CONF="/etc/bind/named.conf.local"
               
               if ! grep -q "$dom" "$CONF"; then
                   echo "zone \"$dom\" { type master; file \"$FILE\"; };" >> $CONF
               fi
               
               cat > $FILE <<EOF
\$TTL 604800
@ IN SOA ns1.$dom. root.$dom. ( 2 604800 86400 2419200 604800 )
@ IN NS ns1.$dom.
@ IN A $target_ip
ns1 IN A $SERVER_IP
www IN A $target_ip
EOF
               chown bind:bind $FILE
               systemctl restart bind9
               echo -e "${GREEN}Zona $dom creada.${NC}"
               ;;
            2) 
               grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
               read -p "Nombre exacto a borrar: " del
               if [ ! -z "$del" ] && grep -q "$del" /etc/bind/named.conf.local; then
                   cp /etc/bind/named.conf.local /etc/bind/named.conf.local.bak
                   sed -i "/zone \"$del\" {/,/};/d" /etc/bind/named.conf.local
                   rm -f "/var/lib/bind/db.$del"
                   systemctl restart bind9
                   echo -e "${GREEN}Eliminado.${NC}"
               else
                   echo -e "${RED}No encontrado.${NC}"
               fi
               ;;
            3) grep "zone" /etc/bind/named.conf.local | awk '{print $2}' | tr -d '"' ;;
            4) break ;;
        esac
    done
}