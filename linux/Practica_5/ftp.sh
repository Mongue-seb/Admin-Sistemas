#!/bin/bash

instalar_vsftpd() {
    echo -e "\n--- INSTALANDO Y CONFIGURANDO VSFTPD ---"
    apt-get update > /dev/null 2>&1
    apt-get install -y vsftpd > /dev/null 2>&1

    # Crear grupos
    groupadd -f reprobados
    groupadd -f recursadores

    # Crear estructura base oculta (la real)
    mkdir -p /srv/ftp_real/{general,reprobados,recursadores}
    
    # Permisos de la estructura base
    chmod 777 /srv/ftp_real/general
    chgrp reprobados /srv/ftp_real/reprobados
    chmod 770 /srv/ftp_real/reprobados
    chgrp recursadores /srv/ftp_real/recursadores
    chmod 770 /srv/ftp_real/recursadores

    # Configurar el acceso anónimo
    mkdir -p /srv/ftp_anon/general
    # Montamos la carpeta general real en la vista del anónimo
    if ! mountpoint -q /srv/ftp_anon/general; then
        mount --bind /srv/ftp_real/general /srv/ftp_anon/general
    fi
    chown root:root /srv/ftp_anon
    chmod 755 /srv/ftp_anon

    # Configurar vsftpd.conf
    cp /etc/vsftpd.conf /etc/vsftpd.conf.bak
    cat > /etc/vsftpd.conf <<EOF
listen=NO
listen_ipv6=YES
anonymous_enable=YES
anon_root=/srv/ftp_anon
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
pasv_min_port=40000
pasv_max_port=50000
EOF

    systemctl restart vsftpd
    echo "Servicio vsftpd configurado e iniciado."
}

gestionar_usuarios() {
    read -p "¿Cuántos usuarios deseas crear/gestionar? " num_users
    for (( i=1; i<=num_users; i++ )); do
        echo -e "\n--- Usuario $i ---"
        read -p "Nombre de usuario: " usr
        read -p "Contraseña: " pass
        read -p "Grupo (reprobados/recursadores): " grp

        # Validar grupo
        if [[ "$grp" != "reprobados" && "$grp" != "recursadores" ]]; then
            echo "Grupo inválido. Omitiendo usuario."
            continue
        fi

        # Crear usuario si no existe
        if ! id "$usr" &>/dev/null; then
            useradd -m -s /usr/sbin/nologin -G "$grp" "$usr"
            echo "$usr:$pass" | chpasswd
            
            # Estructura de la jaula del usuario
            mkdir -p /home/$usr/ftp_root/{general,$grp,$usr}
            chown root:root /home/$usr/ftp_root # Requisito de seguridad de vsftpd
            chown $usr:$usr /home/$usr/ftp_root/$usr
            chmod 700 /home/$usr/ftp_root/$usr

            # Montar las carpetas compartidas dentro de su jaula
            mount --bind /srv/ftp_real/general /home/$usr/ftp_root/general
            mount --bind /srv/ftp_real/$grp /home/$usr/ftp_root/$grp
            
            # Hacer que vsftpd aterrice aquí
            usermod -d /home/$usr/ftp_root "$usr"
            
            echo "Usuario $usr creado en el grupo $grp con estructura vinculada."
        else
            echo "El usuario ya existe. Modificando grupo..."
            viejo_grp=$(id -ng $usr)
            usermod -g "$grp" "$usr"
            
            # Ajustar la jaula al nuevo grupo
            umount /home/$usr/ftp_root/$viejo_grp 2>/dev/null
            rmdir /home/$usr/ftp_root/$viejo_grp 2>/dev/null
            mkdir -p /home/$usr/ftp_root/$grp
            mount --bind /srv/ftp_real/$grp /home/$usr/ftp_root/$grp
            echo "Usuario $usr movido al grupo $grp."
        fi
    done
}

# --- MENU PRINCIPAL ---
while true; do
    echo -e "\n============================="
    echo " MENU FTP "
    echo "============================="
    echo "1) Instalar y Preparar Entorno"
    echo "2) Gestionar Usuarios (Crear/Cambiar Grupo)"
    echo "3) Salir"
    read -p "Opción: " opc

    case $opc in
        1) instalar_vsftpd ;;
        2) gestionar_usuarios ;;
        3) break ;;
        *) echo "Opción inválida." ;;
    esac
done