# Cargar dependencias (Encapsulamiento modular)
. .\utils_functions.ps1
. .\ssh_functions.ps1
. .\dhcp_functions.ps1
. .\dns_functions.ps1

Check-Admin
Configurar-Firewall-Ping

while ($true) {
    Write-Host "`n======== SERVIDOR WINDOWS MODULAR (DHCP + DNS) ========" -ForegroundColor Yellow
    Write-Host "0) [HITO CRITICO] Instalar SSH para Acceso Remoto"
    Write-Host "1) Verificar Instalacion de Roles"
    Write-Host "2) Instalar Roles Manualmente (DHCP y DNS)"
    Write-Host "3) Configurar IP Estatica"
    Write-Host "4) Configurar DHCP (Scope, Lease)"
    Write-Host "5) Gestionar Dominios DNS (ABC)"
    Write-Host "6) Pruebas de Resolucion (Nslookup/Ping)"
    Write-Host "7) Salir"
    
    $OPCION = Read-Host "Seleccione opcion"

    switch ($OPCION) {
        "0" { Instalar-SSH }
        "1" { Verificar-Roles-Instalados }
        "2" { Install-Role -RoleName "DHCP"; Install-Role -RoleName "DNS" }
        "3" { Garantizar-IP-Estatica | Out-Null }
        "4" { Configurar-DHCP }
        "5" { Menu-DNS }
        "6" { Ejecutar-Pruebas }
        "7" { exit }
        Default { Write-Host "Opcion invalida" -ForegroundColor Red }
    }
}