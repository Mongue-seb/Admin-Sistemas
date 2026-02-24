$global:INTERFACE_ALIAS = "Ethernet 2" 

function Check-Admin {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "ADVERTENCIA: Ejecuta como Administrador." -ForegroundColor Red
        exit
    }
}

function Install-Role {
    param ([string]$RoleName)
    if (-not (Get-WindowsFeature -Name $RoleName).Installed) {
        Write-Host "Instalando rol $RoleName..." -ForegroundColor Yellow
        Install-WindowsFeature -Name $RoleName -IncludeManagementTools | Out-Null
        Write-Host "Rol $RoleName instalado correctamente." -ForegroundColor Green
    }
}

function Validar-IP { 
    param ([string]$IP) 
    return ($IP -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") 
}

function Rango-Prohibido {
    param ([string]$IP)
    if ($IP -eq "0.0.0.0" -or $IP -eq "255.255.255.255" -or $IP.StartsWith("127.") -or [int]$IP.Split('.')[0] -ge 224) { return $true }
    return $false
}

function Obtener-IP-Actual {
    $IPConfig = Get-NetIPAddress -InterfaceAlias $global:INTERFACE_ALIAS -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($IPConfig) { return $IPConfig.IPAddress.ToString() }
    return $null
}

function Configurar-Firewall-Ping {
    New-NetFirewallRule -DisplayName "Permitir Ping (ICMPv4-In)" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
}

function Garantizar-IP-Estatica {
    $IPActual = Obtener-IP-Actual
    $NetAdapter = Get-NetIPInterface -InterfaceAlias $global:INTERFACE_ALIAS -AddressFamily IPv4
    $EsAPIPA = if ($IPActual -and $IPActual.StartsWith("169.254")) { $true } else { $false }

    if ($NetAdapter.Dhcp -eq "Enabled" -or $EsAPIPA) {
        Write-Host "ALERTA: Se requiere configurar IP Estatica." -ForegroundColor Red
        $Resp = Read-Host "Configurar ahora? (s/n)"
        if ($Resp -eq "s") {
            do {
                $NuevaIP = Read-Host "Ingrese IP Estatica"
                $Valida = (Validar-IP $NuevaIP) -and -not (Rango-Prohibido $NuevaIP)
                if (-not $Valida) { Write-Host "Error: IP invalida o prohibida." -ForegroundColor Red }
            } until ($Valida)

            Write-Host "Aplicando IP..." -ForegroundColor Cyan
            Remove-NetIPAddress -InterfaceAlias $global:INTERFACE_ALIAS -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceAlias $global:INTERFACE_ALIAS -IPAddress $NuevaIP -PrefixLength 24 -Confirm:$false | Out-Null
            Set-DnsClientServerAddress -InterfaceAlias $global:INTERFACE_ALIAS -ServerAddresses "127.0.0.1" -Confirm:$false
            Configurar-Firewall-Ping
            return $NuevaIP
        }
    } else {
        Write-Host "El servidor ya tiene IP Estatica: $IPActual" -ForegroundColor Green
    }
    return $IPActual
}

function Verificar-Roles-Instalados {
    Write-Host "--- ESTADO DE ROLES ---" -ForegroundColor Cyan
    if ((Get-WindowsFeature -Name "DHCP").Installed) { Write-Host "[OK] DHCP Server" -ForegroundColor Green } else { Write-Host "[X] DHCP NO instalado" -ForegroundColor Red }
    if ((Get-WindowsFeature -Name "DNS").Installed) { Write-Host "[OK] DNS Server" -ForegroundColor Green } else { Write-Host "[X] DNS NO instalado" -ForegroundColor Red }
}

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
