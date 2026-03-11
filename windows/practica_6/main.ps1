# ==========================================
# MAIN SCRIPT - PROVISIONAMIENTO HTTP WINDOWS
# ==========================================

# Importar funciones
. .\http_functions.ps1

# Validar Admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Por favor, ejecuta PowerShell como Administrador."
    exit
}

Clear-Host
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " SISTEMA DE APROVISIONAMIENTO HTTP " -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "1) Instalar IIS (Nativo Windows)"
Write-Host "2) Instalar Apache Win64 (Via Chocolatey)"
Write-Host "3) Instalar Nginx Windows (Via Chocolatey)"
Write-Host "4) Salir"
$Opcion = Read-Host "Elige un servicio HTTP"

if ($Opcion -eq "4") { exit }

# Inicializar variables
$PaqueteChoco = ""
$VersionElegida = "Nativa"

if ($Opcion -eq "2" -or $Opcion -eq "3") {
    if ($Opcion -eq "2") { $PaqueteChoco = "apache-httpd" }
    if ($Opcion -eq "3") { $PaqueteChoco = "nginx" }
    
    $Versiones = Obtener-VersionesChoco -Paquete $PaqueteChoco
    
    if ($Versiones.Count -eq 0) {
        Write-Host "No se encontraron versiones. Verifica tu instalacion de Chocolatey." -ForegroundColor Red
        exit
    }

    Write-Host "`nVersiones Disponibles para $PaqueteChoco:"
    for ($i=0; $i -lt $Versiones.Count; $i++) {
        Write-Host "$($i+1)) $($Versiones[$i])"
    }

    [int]$Sel = Read-Host "Selecciona el numero de version"
    if ($Sel -lt 1 -or $Sel -gt $Versiones.Count) {
        Write-Host "Seleccion invalida." -ForegroundColor Red
        exit
    }
    $VersionElegida = $Versiones[$Sel-1]
} elseif ($Opcion -ne "1") {
    Write-Host "Opcion invalida." -ForegroundColor Red
    exit
}

# Logica de Puertos
$PuertoElegido = Read-Host "Define el puerto de escucha (Ej. 80, 8080)"
while (-not (Validar-Puerto -Puerto $PuertoElegido)) {
    $PuertoElegido = Read-Host "Por favor, define un puerto valido y disponible"
}

# Despliegue Silencioso
Write-Host "`nIniciando aprovisionamiento silencioso..." -ForegroundColor Cyan

if ($Opcion -eq "1") {
    Instalar-IIS -Puerto $PuertoElegido
} elseif ($Opcion -eq "2") {
    Instalar-ApacheChoco -Version $VersionElegida -Puerto $PuertoElegido
} elseif ($Opcion -eq "3") {
    Instalar-NginxChoco -Version $VersionElegida -Puerto $PuertoElegido
}

Write-Host "`n¡Despliegue completado!" -ForegroundColor Green