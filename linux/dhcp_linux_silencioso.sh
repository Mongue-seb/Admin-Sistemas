#!/bin/bash

INET_IFACE="enp0s3"
DHCP_IFACE="enp0s8"

# FUNCION VALIDAR IPv4
validar_ip() {
    [[ $1 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]
}

# ENTRADA DE DATOS
read -rp "Nombre descriptivo del ambito: " SCOPE_NAME

until validar_ip "$IP_INI"; do
    read -rp "IP inicial del rango: " IP_INI
done

until validar_ip "$IP_FIN"; do
    read -rp "IP final del rango: " IP_FIN
done

until validar_ip "$GATEWAY"; do
    read -rp "Gateway: " GATEWAY
done

until validar_ip "$DNS"; do
    read -rp "Servidor DNS: " DNS
done

until [[ $LEASE =~ ^[0-9]+$ ]]; do
    read -rp "Tiempo de concesion (segundos): " LEASE
done

# REPOSITORIOS
if grep -q "^deb cdrom:" /etc/apt/sources.list; then
    sed -i 's/^deb cdrom:/#deb cdrom:/g' /etc/apt/sources.list
fi

cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
EOF

# INSTALACION (IDEMPOTENTE)
if ! dpkg -l | grep -q isc-dhcp-server; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y > /dev/null
    apt-get install isc-dhcp-server isc-dhcp-client -y > /dev/null
else
    echo "DHCP Server ya instalado"
fi

# =========================
# CONFIGURACION DHCP
# =========================
cat <<EOF > /etc/dhcp/dhcpd.conf
authoritative;
default-lease-time $LEASE;
max-lease-time $((LEASE*2));

subnet 192.168.100.0 netmask 255.255.255.0 {
  range $IP_INI $IP_FIN;
  option routers $GATEWAY;
  option domain-name-servers $DNS;
}
EOF

# =========================
# INTERFAZ DHCP
# =========================
cat <<EOF > /etc/default/isc-dhcp-server
INTERFACESv4="$DHCP_IFACE"
INTERFACESv6=""
EOF

# =========================
# RED
# =========================
cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $INET_IFACE
iface $INET_IFACE inet dhcp

auto $DHCP_IFACE
iface $DHCP_IFACE inet static
address 192.168.100.1
netmask 255.255.255.0
EOF

systemctl restart networking
sleep 3

# =========================
# VALIDACION Y SERVICIO
# =========================
dhcpd -t -cf /etc/dhcp/dhcpd.conf || exit 1

systemctl enable isc-dhcp-server > /dev/null
systemctl restart isc-dhcp-server

# =========================
# MONITOREO
# =========================
systemctl is-active isc-dhcp-server