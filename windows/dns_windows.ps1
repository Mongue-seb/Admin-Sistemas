# ==============================================================================
# GESTOR INFRAESTRUCTURA: DHCP + DNS MULTI-ZONA (WINDOWS SERVER)
# ==============================================================================

$INTERFACE_ALIAS = "Ethernet 2" 

# =========================
# FUNCIONES AUXILIARES
# =========================

function Validar-IP {
    param ([string]$IP)
    $IPRegex = "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    return ($IP -match $IPRegex)
}

function Rango-Prohibido {
    param ([string]$IP)
    if ($IP -eq "0.0.0.0" -or $IP -eq "127.0.0.0" -or $IP -eq "255.255.255.255") { return $true }
    if ($IP.StartsWith("127.")) { return $true }
    return $false
}

function Obtener-IP-Actual {
    # El "| Select-Object -First 1" evita problemas si hay multiples IPs
    $IPConfig = Get-NetIPAddress -InterfaceAlias $INTERFACE_ALIAS -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($IPConfig) { 
        return $IPConfig.IPAddress.ToString() 
    }
    return $null
}

# =========================
# FUNCIONES DE GESTIÓN
# =========================

function Verificar-Roles {
    Write-Host "--- ESTADO DE ROLES ---" -ForegroundColor Cyan
    $DHCP = Get-WindowsFeature -Name "DHCP"
    $DNS  = Get-WindowsFeature -Name "DNS"
    
    if ($DHCP.Installed) { Write-Host "[OK] DHCP Server instalado." -ForegroundColor Green }
    else { Write-Host "[X]  DHCP Server NO instalado." -ForegroundColor Red }

    if ($DNS.Installed) { Write-Host "[OK] DNS Server instalado." -ForegroundColor Green }
    else { Write-Host "[X]  DNS Server NO instalado." -ForegroundColor Red }
}

function Instalar-Roles {
    Write-Host "Verificando e instalando roles necesarios..." -ForegroundColor Yellow
    
    $InstallDHCP = -not (Get-WindowsFeature -Name "DHCP").Installed
    $InstallDNS  = -not (Get-WindowsFeature -Name "DNS").Installed

    if ($InstallDHCP) {
        Write-Host "Instalando DHCP..." -ForegroundColor Cyan
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
    }
    if ($InstallDNS) {
        Write-Host "Instalando DNS..." -ForegroundColor Cyan
        Install-WindowsFeature -Name DNS -IncludeManagementTools
    }

    if (-not $InstallDHCP -and -not $InstallDNS) {
        Write-Host "Todos los roles ya estan instalados." -ForegroundColor Green
    } else {
        Write-Host "Instalacion finalizada." -ForegroundColor Green
    }
}

# =========================
# LÓGICA DE IP ESTÁTICA
# =========================

function Garantizar-IP-Estatica {
    # Verificamos estado actual
    $NetAdapter = Get-NetIPInterface -InterfaceAlias $INTERFACE_ALIAS -AddressFamily IPv4
    
    # Si esta por DHCP o tiene la IP APIPA (169.254...), hay que arreglarlo
    $IPActual = Obtener-IP-Actual
    $EsAPIPA = $false
    if ($IPActual -and $IPActual.StartsWith("169.254")) { $EsAPIPA = $true }

    if ($NetAdapter.Dhcp -eq "Enabled" -or $EsAPIPA) {
        Write-Host "ALERTA: El servidor no tiene una IP Estatica valida." -ForegroundColor Red
        if ($EsAPIPA) { Write-Host "Detectada IP APIPA (169.254.x.x) - Error de red." -ForegroundColor Yellow }
        
        $Resp = Read-Host "¿Desea configurar una IP ESTATICA ahora? (s/n)"
        if ($Resp -eq "s") {
            $NuevaIP = Read-Host "Ingrese IP Estatica para este Servidor (ej. 192.168.10.1)"
            
            if (Validar-IP $NuevaIP) {
                Write-Host "Configurando IP $NuevaIP en $INTERFACE_ALIAS..." -ForegroundColor Cyan
                
                # 1. Quitamos cualquier IP anterior para evitar errores
                Remove-NetIPAddress -InterfaceAlias $INTERFACE_ALIAS -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
                
                # 2. Ponemos la nueva IP 
                # CRITICO: Agregado '| Out-Null' para evitar que devuelva la IP duplicada al flujo
                New-NetIPAddress -InterfaceAlias $INTERFACE_ALIAS -IPAddress $NuevaIP -PrefixLength 24 -Confirm:$false | Out-Null
                
                # 3. Ajustamos el DNS para que se mire a sí mismo
                Set-DnsClientServerAddress -InterfaceAlias $INTERFACE_ALIAS -ServerAddresses "127.0.0.1" -Confirm:$false
                
                Write-Host "IP Estatica configurada EXITOSAMENTE: $NuevaIP" -ForegroundColor Green
                return $NuevaIP
            } else {
                Write-Host "IP Invalida." -ForegroundColor Red
            }
        }
    } else {
        Write-Host "El servidor ya tiene IP Estatica: $IPActual" -ForegroundColor Green
        return $IPActual
    }
    return (Obtener-IP-Actual)
}

# =========================
# CONFIGURACIÓN DHCP
# =========================

function Configurar-DHCP {
    if (-not (Get-WindowsFeature -Name "DHCP").Installed) {
        Write-Host "Error: El rol DHCP no esta instalado." -ForegroundColor Red; return
    }
    
    $ServerIP = Garantizar-IP-Estatica
    
    $ServerIP = "$ServerIP".Split(' ')[0]
    $ServerIP = $ServerIP.Trim()

    Write-Host "`n--- CONFIGURACION DEL AMBITO DHCP ---" -ForegroundColor Yellow
    $ScopeName = Read-Host "Nombre del ambito DHCP"
    
    $IP_INI = ""
    do {
        $InputIP = Read-Host "IP inicial del rango (ej. 192.168.10.100)"
        if (Validar-IP $InputIP -and -not (Rango-Prohibido $InputIP)) { $IP_INI = $InputIP }
    } until ($IP_INI -ne "")

    $IP_FIN = ""
    do {
        $InputIP = Read-Host "IP final del rango (ej. 192.168.10.200)"
        if (Validar-IP $InputIP -and -not (Rango-Prohibido $InputIP)) { $IP_FIN = $InputIP }
    } until ($IP_FIN -ne "")

    $GATEWAY = Read-Host "Gateway (Enter para vacio)"
    if ($GATEWAY -ne "" -and -not (Validar-IP $GATEWAY)) { $GATEWAY = "" }

    $DNS_Value = [string[]]@($ServerIP)

    $LEASE_SEC = 28800
    $InputLease = Read-Host "Tiempo concesion (segundos) [Enter=28800]"
    if ($InputLease -match "^\d+$") { $LEASE_SEC = [int]$InputLease }
   
    $Octets = $IP_INI.Split('.')
    $NetworkID = "$($Octets[0]).$($Octets[1]).$($Octets[2]).0"

    try {
        Write-Host "Preparando servicio DHCP..." -ForegroundColor Cyan
        Restart-Service dhcpserver -Force
        
        Write-Host "Esperando 5 segundos a que el servicio se estabilice..." -ForegroundColor Gray
        Start-Sleep -Seconds 5

        if (Get-DhcpServerv4Scope -ScopeId $NetworkID -ErrorAction SilentlyContinue) {
            Write-Host "Eliminando ambito previo $NetworkID..." -ForegroundColor Gray
            Remove-DhcpServerv4Scope -ScopeId $NetworkID -Force
        }

        Write-Host "Creando ambito $ScopeName..."
        $TimeSpan = New-TimeSpan -Seconds $LEASE_SEC
        Add-DhcpServerv4Scope -Name $ScopeName -StartRange $IP_INI -EndRange $IP_FIN -SubnetMask 255.255.255.0 -State Active -LeaseDuration $TimeSpan

        if ($GATEWAY -ne "") { 
            Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 3 -Value $GATEWAY 
        }
        
        Write-Host "Asignando servidor DNS ($DNS_Value) a los clientes..."
        Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 6 -Value $DNS_Value

        Write-Host "Configuracion DHCP EXITOSA." -ForegroundColor Green
    } catch { 
        Write-Host "ERROR FATAL DHCP: $_" -ForegroundColor Red 
        Write-Host "Verifica la IP: '$ServerIP'" -ForegroundColor Yellow
    }
}

# =========================
# GESTIÓN DNS AVANZADA
# =========================

function Agregar-Zona {
    param ($ServerIP)
    Write-Host "`n--- AGREGAR NUEVA ZONA DNS ---" -ForegroundColor Yellow
    
    $NombreDominio = Read-Host "Nombre del Dominio (ej. reprobados.com)"
    if ($NombreDominio -eq "") { return }

    # Verificar si ya existe
    if (Get-DnsServerZone -Name $NombreDominio -ErrorAction SilentlyContinue) {
        Write-Host "La zona '$NombreDominio' ya existe." -ForegroundColor Red
        $Over = Read-Host "¿Desea eliminarla y recrearla? (s/n)"
        if ($Over -eq "s") {
            Remove-DnsServerZone -Name $NombreDominio -Force -Confirm:$false
        } else {
            return
        }
    }

    $TargetIP = Read-Host "IP a la que resolvera (Enter para usar $ServerIP)"
    if ($TargetIP -eq "" -or -not (Validar-IP $TargetIP)) { $TargetIP = $ServerIP }

    try {
        Add-DnsServerPrimaryZone -Name $NombreDominio -ZoneFile "$NombreDominio.dns"
        
        Add-DnsServerResourceRecordA -ZoneName $NombreDominio -Name "." -IPv4Address $TargetIP
        Add-DnsServerResourceRecordA -ZoneName $NombreDominio -Name "www" -IPv4Address $TargetIP
        
        Write-Host "Zona '$NombreDominio' CREADA exitosamente." -ForegroundColor Green
        Write-Host "Apuntando a -> $TargetIP" -ForegroundColor Gray
    } catch {
        Write-Host "Error al crear zona: $_" -ForegroundColor Red
    }
}

function Eliminar-Zona {
    Write-Host "`n--- ELIMINAR ZONA DNS ---" -ForegroundColor Yellow
    
    $Zonas = Get-DnsServerZone | Where-Object {$_.IsDsIntegrated -eq $false -and $_.ZoneType -eq "Primary"}
    if ($Zonas.Count -eq 0) {
        Write-Host "No hay zonas primarias configuradas para eliminar." -ForegroundColor Yellow
        return
    }

    $Zonas | Select-Object ZoneName, ZoneType | Format-Table -AutoSize
    
    $NombreBorrar = Read-Host "Escriba el nombre EXACTO de la zona a borrar (o Enter para cancelar)"
    
    if ($NombreBorrar -ne "") {
        if (Get-DnsServerZone -Name $NombreBorrar -ErrorAction SilentlyContinue) {
            Remove-DnsServerZone -Name $NombreBorrar -Force -Confirm:$false
            Write-Host "Zona '$NombreBorrar' ELIMINADA correctamente." -ForegroundColor Green
        } else {
            Write-Host "La zona no existe." -ForegroundColor Red
        }
    }
}

function Menu-DNS {
    if (-not (Get-WindowsFeature -Name "DNS").Installed) {
        Write-Host "Error: El rol DNS no esta instalado." -ForegroundColor Red; return
    }
    
    $ServerIP = Garantizar-IP-Estatica
    $ServerIP = "$ServerIP".Split(' ')[0].Trim()

    while ($true) {
        Write-Host "`n--- GESTION DE DOMINIOS DNS ---" -ForegroundColor Cyan
        Write-Host "1) Agregar Dominio (Zona + www)"
        Write-Host "2) Eliminar Dominio"
        Write-Host "3) Ver Dominios Actuales"
        Write-Host "4) Volver al Menu Principal"
        
        $SubOpc = Read-Host "Seleccione opcion"
        
        switch ($SubOpc) {
            "1" { Agregar-Zona -ServerIP $ServerIP }
            "2" { Eliminar-Zona }
            "3" { Get-DnsServerZone | Select-Object ZoneName, ZoneType | Format-Table -AutoSize }
            "4" { return }
            Default { Write-Host "Opcion invalida" }
        }
    }
}

# =========================
# MONITOREO Y PRUEBAS
# =========================

function Ejecutar-Pruebas {
    Write-Host "===== PRUEBAS DE RESOLUCION =====" -ForegroundColor Cyan
    $DomTest = Read-Host "Dominio a probar (ej. reprobados.com)"
    if ($DomTest -eq "") { return }

    Write-Host "Probando NSLOOKUP..."
    try {
        $Res = Resolve-DnsName -Name $DomTest -Type A -ErrorAction Stop
        Write-Host "Resolucion OK: $($Res.IPAddress)" -ForegroundColor Green
    } catch { Write-Host "Fallo resolucion DNS." -ForegroundColor Red }

    Write-Host "Probando PING..."
    try {
        Test-Connection -ComputerName $DomTest -Count 1 -ErrorAction Stop | Out-Null
        Write-Host "Ping OK." -ForegroundColor Green
    } catch { Write-Host "Ping fallo." -ForegroundColor Yellow }
}

# =========================
# MENU PRINCIPAL
# =========================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ADVERTENCIA: Ejecuta como Administrador." -ForegroundColor Red
}

while ($true) {
    Write-Host "`n======== SERVIDOR TODO-EN-UNO (DHCP + DNS) ========" -ForegroundColor Yellow
    Write-Host "1) Verificar Instalacion"
    Write-Host "2) Instalar Roles (DHCP y DNS)"
    Write-Host "3) Configurar DHCP (Scope)"
    Write-Host "4) Gestionar Dominios DNS (Agregar/Quitar)"
    Write-Host "5) Pruebas de Resolucion"
    Write-Host "6) Salir"
    
    $OPCION = Read-Host "Seleccione opcion"

    switch ($OPCION) {
        "1" { Verificar-Roles }
        "2" { Instalar-Roles }
        "3" { Configurar-DHCP }
        "4" { Menu-DNS }
        "5" { Ejecutar-Pruebas }
        "6" { exit }
        Default { Write-Host "Opcion invalida" -ForegroundColor Red }
    }

}
