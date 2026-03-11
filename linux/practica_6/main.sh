#!/bin/bash
# ==========================================
# MAIN SCRIPT - PROVISIONAMIENTO HTTP LINUX
# ==========================================

# Importar funciones
source ./http_functions.sh

# Verificar privilegios de root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit 1
fi

echo "======================================"
echo " SISTEMA DE APROVISIONAMIENTO HTTP "
echo "======================================"
echo "1) Instalar Apache2"
echo "2) Instalar Nginx"
echo "3) Instalar Tomcat (Binarios tar.gz)"
read -p "Elige un servicio HTTP: " opcion

paquete=""
case $opcion in
    1) paquete="apache2" ;;
    2) paquete="nginx" ;;
    3) paquete="tomcat" ;;
    *) echo "Opción no válida."; exit 1 ;;
esac

# Lógica Dinámica de Versiones
echo -e "\nVersiones disponibles para $paquete:"
versiones=($(obtener_versiones "$paquete"))

if [ ${#versiones[@]} -eq 0 ]; then
    echo "Error: No se encontraron versiones. Verifica tu conexión o repositorios."
    exit 1
fi

# Listar opciones de versión
for i in "${!versiones[@]}"; do
    echo "$((i+1))) ${versiones[$i]}"
done

read -p "Selecciona el número de versión a instalar: " sel_version
# Validación de entrada
if ! [[ "$sel_version" =~ ^[0-9]+$ ]] || [ "$sel_version" -lt 1 ] || [ "$sel_version" -gt "${#versiones[@]}" ]; then
    echo "Selección de versión inválida."
    exit 1
fi
version_elegida="${versiones[$((sel_version-1))]}"

# Lógica de Puertos
read -p "Define el puerto de escucha (Ej. 80, 8080): " puerto_elegido
while ! validar_puerto "$puerto_elegido"; do
    read -p "Por favor, define un puerto válido y disponible: " puerto_elegido
done

# Despliegue Silencioso
echo -e "\nIniciando aprovisionamiento..."
if [ "$paquete" == "apache2" ]; then
    instalar_apache "$version_elegida" "$puerto_elegido"
elif [ "$paquete" == "nginx" ]; then
    instalar_nginx "$version_elegida" "$puerto_elegido"
elif [ "$paquete" == "tomcat" ]; then
    instalar_tomcat "$version_elegida" "$puerto_elegido"
fi

echo "¡Despliegue completado! Visita: http://$(hostname -I | awk '{print $1}'):$puerto_elegido"