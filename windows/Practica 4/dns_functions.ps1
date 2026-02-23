function Agregar-Zona {
    param ($ServerIP)
    Write-Host "`n--- AGREGAR NUEVA ZONA DNS ---" -ForegroundColor Yellow
    $NombreDominio = Read-Host "Nombre del Dominio"
    if ($NombreDominio -eq "") { return }

    if (Get-DnsServerZone -Name $NombreDominio -ErrorAction SilentlyContinue) {
        Write-Host "La zona ya existe." -ForegroundColor Red
        $Over = Read-Host "Recrear? (s/n)"
        if ($Over -eq "s") { Remove-DnsServerZone -Name $NombreDominio -Force -Confirm:$false } else { return }
    }

    $TargetIP = ""
    do {
        $InputIP = Read-Host "IP a la que resolvera (Enter para $ServerIP)"
        if ($InputIP -eq "") { $TargetIP = $ServerIP }
        elseif ((Validar-IP $InputIP) -and -not (Rango-Prohibido $InputIP)) { $TargetIP = $InputIP }
        else { Write-Host "Error: IP invalida." -ForegroundColor Red }
    } until ($TargetIP -ne "")

    try {
        Add-DnsServerPrimaryZone -Name $NombreDominio -ZoneFile "$NombreDominio.dns"
        Add-DnsServerResourceRecordA -ZoneName $NombreDominio -Name "." -IPv4Address $TargetIP
        Add-DnsServerResourceRecordA -ZoneName $NombreDominio -Name "www" -IPv4Address $TargetIP
        Write-Host "Zona CREADA." -ForegroundColor Green
    } catch { Write-Host "Error: $_" -ForegroundColor Red }
}

function Eliminar-Zona {
    Write-Host "`n--- ELIMINAR ZONA DNS ---" -ForegroundColor Yellow
    $Zonas = Get-DnsServerZone | Where-Object {$_.IsDsIntegrated -eq $false -and $_.ZoneType -eq "Primary"}
    if ($Zonas.Count -eq 0) { Write-Host "No hay zonas."; return }

    $Zonas | Select-Object ZoneName | Format-Table -AutoSize
    $NombreBorrar = Read-Host "Nombre EXACTO a borrar"
    
    if ($NombreBorrar -ne "") {
        if (Get-DnsServerZone -Name $NombreBorrar -ErrorAction SilentlyContinue) {
            Remove-DnsServerZone -Name $NombreBorrar -Force -Confirm:$false
            Write-Host "Zona ELIMINADA." -ForegroundColor Green
        } else { Write-Host "La zona no existe." -ForegroundColor Red }
    }
}

function Menu-DNS {
    Install-Role -RoleName "DNS"
    $ServerIP = Garantizar-IP-Estatica
    $ServerIP = "$ServerIP".Split(' ')[0].Trim()

    while ($true) {
        Write-Host "`n--- GESTION DE DOMINIOS DNS ---" -ForegroundColor Cyan
        Write-Host "1) Agregar Dominio"
        Write-Host "2) Eliminar Dominio"
        Write-Host "3) Ver Dominios Actuales"
        Write-Host "4) Volver al Menu Principal"
        
        $SubOpc = Read-Host "Opcion"
        switch ($SubOpc) {
            "1" { Agregar-Zona -ServerIP $ServerIP }
            "2" { Eliminar-Zona }
            "3" { Get-DnsServerZone | Where-Object {$_.IsDsIntegrated -eq $false} | Select-Object ZoneName, ZoneType | Format-Table -AutoSize }
            "4" { return }
        }
    }
}