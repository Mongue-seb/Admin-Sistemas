function Configurar-DHCP {
    Install-Role -RoleName "DHCP"
    
    $ServerIP = Garantizar-IP-Estatica
    $ServerIP = "$ServerIP".Split(' ')[0].Trim()

    Write-Host "`n--- CONFIGURACION DEL AMBITO DHCP ---" -ForegroundColor Yellow
    $ScopeName = Read-Host "Nombre del ambito DHCP"
    
    do { 
        $IP_INI = Read-Host "IP inicial del rango"
        $Valido = (Validar-IP $IP_INI) -and -not (Rango-Prohibido $IP_INI)
        if (-not $Valido) { Write-Host "Error IP invalida." -ForegroundColor Red }
    } until ($Valido)

    do { 
        $IP_FIN = Read-Host "IP final del rango"
        $Valido = (Validar-IP $IP_FIN) -and -not (Rango-Prohibido $IP_FIN)
        if (-not $Valido) { Write-Host "Error IP invalida." -ForegroundColor Red }
    } until ($Valido)

    $GATEWAY = ""
    $InputGW = Read-Host "Gateway (Enter para vacio)"
    if ($InputGW -ne "" -and (Validar-IP $InputGW) -and -not (Rango-Prohibido $InputGW)) { $GATEWAY = $InputGW }

    $DNS_Value = [string[]]@($ServerIP)

    $LEASE_SEC = 0
    do {
        $InputLease = Read-Host "Tiempo concesion (segundos) [Enter=28800]"
        if ($InputLease -eq "") { $LEASE_SEC = 28800 }
        elseif ($InputLease -match "^\d+$" -and [int]$InputLease -gt 0) { $LEASE_SEC = [int]$InputLease }
        else { Write-Host "Debe ser numero entero positivo." -ForegroundColor Red }
    } until ($LEASE_SEC -gt 0)
   
    $Octets = $IP_INI.Split('.')
    $NetworkID = "$($Octets[0]).$($Octets[1]).$($Octets[2]).0"

    try {
        Write-Host "Preparando servicio DHCP..." -ForegroundColor Cyan
        Restart-Service dhcpserver -Force; Start-Sleep -Seconds 5

        if (Get-DhcpServerv4Scope -ScopeId $NetworkID -ErrorAction SilentlyContinue) {
            Remove-DhcpServerv4Scope -ScopeId $NetworkID -Force
        }

        Add-DhcpServerv4Scope -Name $ScopeName -StartRange $IP_INI -EndRange $IP_FIN -SubnetMask 255.255.255.0 -State Active -LeaseDuration (New-TimeSpan -Seconds $LEASE_SEC)
        
        if ($GATEWAY -ne "") { Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 3 -Value $GATEWAY }
        Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 6 -Value $DNS_Value

        Write-Host "Configuracion DHCP EXITOSA." -ForegroundColor Green
    } catch { Write-Host "ERROR DHCP: $_" -ForegroundColor Red }
}