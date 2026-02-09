# =========================
# FUNCION VALIDAR IPv4
# =========================
function Validar-IP {
    param ($ip)
    return $ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
}

# =========================
# ENTRADA DE DATOS
# =========================

do {
    $scopeName = Read-Host "Nombre del Ambito DHCP"
} while ([string]::IsNullOrWhiteSpace($scopeName))

do {
    $scopeStart = Read-Host "IP inicial del rango"
} until (Validar-IP $scopeStart)

do {
    $scopeEnd = Read-Host "IP final del rango"
} until (Validar-IP $scopeEnd)

do {
    $gateway = Read-Host "Gateway"
} until (Validar-IP $gateway)

do {
    $dnsServer = Read-Host "Servidor DNS"
} until (Validar-IP $dnsServer)

do {
    $leaseHours = Read-Host "Tiempo de concesion (horas)"
} until ($leaseHours -match '^\d+$')

$scopeMask = "255.255.255.0"
$scopeSubnet = ($scopeStart -replace '\d+$','0')

# =========================
# INSTALACION DHCP (IDEMPOTENTE)
# =========================

$dhcp = Get-WindowsFeature DHCP

if (-not $dhcp.Installed) {
    Write-Host "Instalando rol DHCP..."
    Install-WindowsFeature DHCP -IncludeManagementTools
} else {
    Write-Host "Rol DHCP ya instalado"
}

# =========================
# CREAR SCOPE
# =========================

$scopeExistente = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
    Where-Object { $_.ScopeId -eq $scopeSubnet }

if (-not $scopeExistente) {
    Write-Host "Creando el ambito DHCP..."
    Add-DhcpServerv4Scope `
        -Name $scopeName `
        -StartRange $scopeStart `
        -EndRange $scopeEnd `
        -SubnetMask $scopeMask `
        -LeaseDuration (New-TimeSpan -Hours $leaseHours)
} else {
    Write-Host "El ambito ya existe"
}

# =========================
# OPCIONES DHCP
# =========================

Set-DhcpServerv4OptionValue `
    -ScopeId $scopeSubnet `
    -Router $gateway `
    -DnsServer $dnsServer

# =========================
# ACTIVAR SERVICIO
# =========================

Start-Service DHCPServer
Set-Service DHCPServer -StartupType Automatic
Set-DhcpServerv4Scope -ScopeId $scopeSubnet -State Active

# =========================
# MONITOREO
# =========================

Write-Host "`nEstado del servicio:"
Get-Service DHCPServer

Write-Host "`nLeases activos:"
Get-DhcpServerv4Lease -ScopeId $scopeSubnet
