#!/bin/bash

# ==========================================
# LIBRERÍA DE FUNCIONES HTTP - LINUX
# ==========================================

# 1. Validación estricta de puerto
validar_puerto() {
    local puerto=$1
    # Validar que sea numérico
    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        echo "Error: El puerto debe ser un número."
        return 1
    fi
    # Restringir puertos reservados
    local reservados=(21 22 25 53 110 143 443 3306)
    for p in "${reservados[@]}"; do
        if [[ "$puerto" -eq "$p" ]]; then
            echo "Error: El puerto $puerto está reservado para otro servicio."
            return 1
        fi
    done
    # Verificar si está ocupado
    if ss -tuln | grep -q ":$puerto "; then
        echo "Error: El puerto $puerto ya está en uso por otro servicio."
        return 1
    fi
    return 0
}

# 2. Obtener versiones dinámicamente
obtener_versiones() {
    local paquete=$1
    echo "Consultando repositorio para $paquete..." >&2
    if [ "$paquete" == "tomcat" ]; then
        # Hacemos Web Scraping directo al archivo de Apache para extraer versiones de Tomcat 9
        curl -s https://archive.apache.org/dist/tomcat/tomcat-9/ | grep -o 'v9\.[0-9]*\.[0-9]*' | sort -V | uniq | tac | head -n 5
    else
        apt-get update -qq >/dev/null 2>&1
        apt-cache madison "$paquete" | awk '{print $3}' | head -n 5
    fi
}

# 3. Configuración del Firewall (UFW)
configurar_firewall() {
    local puerto=$1
    echo "Configurando UFW para el puerto $puerto..."
    ufw allow "$puerto"/tcp >/dev/null 2>&1
    # Cerrar puerto 80 si no es el elegido
    if [[ "$puerto" -ne 80 ]]; then
        ufw deny 80/tcp >/dev/null 2>&1
    fi
    ufw reload >/dev/null 2>&1
}

# 4. Crear index.html dinámico
crear_index() {
    local servicio=$1
    local version=$2
    local puerto=$3
    local ruta=$4
    
    echo "<h1>Servidor: $servicio - Versión: $version - Puerto: $puerto</h1>" > "$ruta/index.html"
}

# 5. Instalación y Hardening de Apache2
instalar_apache() {
    local version=$1
    local puerto=$2
    echo "Instalando silenciosamente Apache2 versión $version..."
    
    apt-get install -y -q apache2="$version" >/dev/null 2>&1
    
    # Cambio de puerto
    sed -i "s/Listen 80/Listen $puerto/g" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$puerto>/g" /etc/apache2/sites-available/000-default.conf
    
    # Hardening (Ocultar versión y cabeceras de seguridad)
    sed -i "s/ServerTokens OS/ServerTokens Prod/g" /etc/apache2/conf-available/security.conf
    sed -i "s/ServerSignature On/ServerSignature Off/g" /etc/apache2/conf-available/security.conf
    sed -i "s/TraceEnable On/TraceEnable Off/g" /etc/apache2/conf-available/security.conf
    
    a2enmod headers >/dev/null 2>&1
    echo 'Header always set X-Frame-Options "SAMEORIGIN"' >> /etc/apache2/apache2.conf
    echo 'Header always set X-Content-Type-Options "nosniff"' >> /etc/apache2/apache2.conf
    
    # Permisos
    crear_index "Apache2" "$version" "$puerto" "/var/www/html"
    chown -R www-data:www-data /var/www/html
    chmod -R 750 /var/www/html

    systemctl restart apache2
    configurar_firewall "$puerto"
    echo "Apache2 aprovisionado exitosamente en el puerto $puerto."
}

# 6. Instalación y Hardening de Nginx
instalar_nginx() {
    local version=$1
    local puerto=$2
    echo "Instalando silenciosamente Nginx versión $version..."
    
    apt-get install -y -q nginx="$version" >/dev/null 2>&1
    
    # Cambio de puerto
    sed -i "s/listen 80 default_server;/listen $puerto default_server;/g" /etc/nginx/sites-available/default
    sed -i "s/listen \[::\]:80 default_server;/listen \[::\]:$puerto default_server;/g" /etc/nginx/sites-available/default
    
    # Hardening
    sed -i "s/# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
    sed -i "/server_tokens off;/a \ \ \ \ add_header X-Frame-Options SAMEORIGIN;\n\ \ \ \ add_header X-Content-Type-Options nosniff;" /etc/nginx/nginx.conf
    
    # Permisos
    crear_index "Nginx" "$version" "$puerto" "/var/www/html"
    chown -R www-data:www-data /var/www/html
    chmod -R 750 /var/www/html

    systemctl restart nginx
    configurar_firewall "$puerto"
    echo "Nginx aprovisionado exitosamente en el puerto $puerto."
}

# 7. Instalación y Hardening de Tomcat (Binarios y Variables de Entorno)
instalar_tomcat() {
    local version=$1 # Ej. v9.0.87
    local num_version=${version#v} # Quita la 'v' para el nombre del archivo
    local puerto=$2
    echo "Instalando Java y descargando binarios de Tomcat $version..."

    # Dependencia necesaria para Tomcat
    apt-get install -y -q default-jdk >/dev/null 2>&1

    # Crear usuario dedicado y limitarlo a /var/www/tomcat
    useradd -r -m -U -d /var/www/tomcat -s /bin/false tomcat >/dev/null 2>&1
    mkdir -p /var/www/tomcat
    
    # Descarga y extracción silenciosa (.tar.gz)
    local url="https://archive.apache.org/dist/tomcat/tomcat-9/${version}/bin/apache-tomcat-${num_version}.tar.gz"
    curl -s -O "$url"
    tar -xzf "apache-tomcat-${num_version}.tar.gz" -C /var/www/tomcat --strip-components=1
    rm "apache-tomcat-${num_version}.tar.gz"

    # Manipulación del puerto en server.xml
    sed -i "s/port=\"8080\"/port=\"$puerto\"/g" /var/www/tomcat/conf/server.xml
    
    # HARDENING TOMCAT: Ocultar la versión en las cabeceras inyectando un nombre falso
    sed -i "s/port=\"$puerto\"/port=\"$puerto\" server=\"Web-Server\"/g" /var/www/tomcat/conf/server.xml

    # Inyección de Cabeceras de Seguridad modificando el web.xml global
    sed -i '/<\/web-app>/d' /var/www/tomcat/conf/web.xml
    cat <<EOT >> /var/www/tomcat/conf/web.xml
    <filter>
        <filter-name>httpHeaderSecurity</filter-name>
        <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>
        <init-param>
            <param-name>antiClickJackingOption</param-name>
            <param-value>SAMEORIGIN</param-value>
        </init-param>
    </filter>
    <filter-mapping>
        <filter-name>httpHeaderSecurity</filter-name>
        <url-pattern>/*</url-pattern>
    </filter-mapping>
</web-app>
EOT

    # Crear HTML y Permisos Restrictivos
    rm -rf /var/www/tomcat/webapps/ROOT/*
    crear_index "Tomcat" "$version" "$puerto" "/var/www/tomcat/webapps/ROOT"
    
    chown -R tomcat:tomcat /var/www/tomcat
    chmod -R 750 /var/www/tomcat

    # Manejo de Variables de Entorno y creación del servicio desatendido
    cat <<EOT > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/default-java"
Environment="CATALINA_PID=/var/www/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/var/www/tomcat"
Environment="CATALINA_BASE=/var/www/tomcat"
ExecStart=/var/www/tomcat/bin/startup.sh
ExecStop=/var/www/tomcat/bin/shutdown.sh

[Install]
WantedBy=multi-user.target
EOT

    systemctl daemon-reload
    systemctl enable tomcat >/dev/null 2>&1
    systemctl restart tomcat
    
    configurar_firewall "$puerto"
    echo "Tomcat aprovisionado exitosamente en el puerto $puerto."
}