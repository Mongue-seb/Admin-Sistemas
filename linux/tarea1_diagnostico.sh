echo "Nombre del equipo:"
hostname

echo -e "\nIP actual:"
ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(.\d+){3}'

echo -e "\nEspacio en disco:"
df -h /