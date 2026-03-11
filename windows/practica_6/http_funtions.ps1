# ==========================================
# LIBRERÍA DE FUNCIONES HTTP - WINDOWS
# ==========================================

function Validar-Puerto {
    param ([string]$Puerto)
    
    if ([string]::IsNullOrWhiteSpace($Puerto) -or $Puerto -notmatch "^\d+$") {
        Write-Host "Error: Puerto invalido." -ForegroundColor Red
        return $false
    }
    
    $PuertoInt = [int]$Puerto
    $Reservados = @(21, 22, 25, 53, 110, 143, 443, 3306, 3389)
    if ($Reservados -contains $PuertoInt) {
        Write-Host "Error: El puerto $Puerto esta reservado por el sistema." -ForegroundColor Red
        return $false
    }

    $Conexion = Get-NetTCPConnection -LocalPort $PuertoInt -ErrorAction SilentlyContinue
    if ($Conexion) {
        Write-Host "Error: El puerto $Puerto ya esta en uso." -ForegroundColor Red
        return $false
    }
    return $true
}

function Obtener-VersionesChoco {
    param ([string]$Paquete)
    Write-Host "Consultando repositorio de Chocolatey para $Paquete..." -ForegroundColor Cyan
    $Resultado = choco search $Paquete --exact --all-versions --limit-output
    $Versiones = $Resultado | ForEach-Object { ($_ -split '\|')[1] } | Select-Object -First 5
    return $Versiones
}

function Configurar-FirewallWindows {
    param ([int]$Puerto)
    Write-Host "Configurando Reglas de Firewall (Abriendo puerto $Puerto)..." -ForegroundColor Cyan
    New-NetFirewallRule -DisplayName "HTTP-Custom-$Puerto" -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    
    if ($Puerto -ne 80) {
        Disable-NetFirewallRule -DisplayName "World Wide Web Services (HTTP Traffic-In)" -ErrorAction SilentlyContinue | Out-Null
    }
}

function Crear-IndexWindows {
    param ([string]$Servicio, [string]$Version, [string]$Puerto, [string]$Ruta)
    $Html = "<h1>Servidor: $Servicio - Version: $Version - Puerto: $Puerto</h1>"
    Set-Content -Path "$Ruta\index.html" -Value $Html -Force
}

function Instalar-IIS {
    param ([string]$Puerto)
    Write-Host "Instalando IIS silenciosamente..." -ForegroundColor Yellow
    Install-WindowsFeature -name Web-Server -IncludeManagementTools -WarningAction SilentlyContinue | Out-Null

    Write-Host "Configurando bindings en el puerto $Puerto..."
    Remove-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port $Puerto -Protocol http | Out-Null

    Write-Host "Aplicando Hardening a IIS..." -ForegroundColor Cyan
    Remove-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpProtocol/customHeaders" -name "." -AtElement @{name='X-Powered-By'} -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Content-Type-Options';value='nosniff'} -ErrorAction SilentlyContinue
    Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering" -name "removeServerHeader" -value "True" -ErrorAction SilentlyContinue

    Crear-IndexWindows "IIS" "Nativa Windows" "$Puerto" "C:\inetpub\wwwroot"
    Configurar-FirewallWindows -Puerto $Puerto
    Restart-WebAppPool -Name "DefaultAppPool"
    Write-Host "IIS instalado y asegurado correctamente." -ForegroundColor Green
}

function Instalar-ApacheChoco {
    param ([string]$Version, [string]$Puerto)
    Write-Host "Instalando Apache v$Version via Chocolatey (Mostrando logs...)" -ForegroundColor Yellow
    choco install apache-httpd -y --version $Version --force
    
    $BaseDir = "C:\tools\Apache24"
    if (-Not (Test-Path "$BaseDir\conf\httpd.conf")) { $BaseDir = "C:\Apache24" }
    if (-Not (Test-Path "$BaseDir\conf\httpd.conf")) { $BaseDir = "$env:APPDATA\Apache24" }
    
    if (-Not (Test-Path "$BaseDir\conf\httpd.conf")) {
        Write-Host "ERROR CRITICO: La instalacion fallo." -ForegroundColor Red
        return
    }

    Write-Host "¡Apache encontrado en $BaseDir! Aplicando configuraciones dinamicas..." -ForegroundColor Cyan
    $ConfPath = "$BaseDir\conf\httpd.conf"
    $BaseDirUnix = $BaseDir -replace '\\', '/'
    
    (Get-Content $ConfPath) -replace '^Listen\s+\d+', "Listen $Puerto" | Set-Content $ConfPath
    (Get-Content $ConfPath) -replace '^ServerRoot\s+.*', "ServerRoot `"$BaseDirUnix`"" | Set-Content $ConfPath
    (Get-Content $ConfPath) -replace '^DocumentRoot\s+.*', "DocumentRoot `"$BaseDirUnix/htdocs`"" | Set-Content $ConfPath
    (Get-Content $ConfPath) -replace '^<Directory\s+.*htdocs.*', "<Directory `"$BaseDirUnix/htdocs`">" | Set-Content $ConfPath
    
    Crear-IndexWindows "Apache Win64" "$Version" "$Puerto" "$BaseDir\htdocs"
    Configurar-FirewallWindows -Puerto $Puerto
    
    Write-Host "Iniciando/Reiniciando el demonio de Apache..." -ForegroundColor Yellow
    if (Get-Service -Name "Apache" -ErrorAction SilentlyContinue) { Restart-Service "Apache" -Force } 
    elseif (Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue) { Restart-Service "Apache2.4" -Force }
    
    Write-Host "Apache Win64 aprovisionado exitosamente." -ForegroundColor Green
}

function Instalar-NginxChoco {
    param ([string]$Version, [string]$Puerto)
    Write-Host "Instalando Nginx v$Version via Chocolatey (Mostrando logs...)" -ForegroundColor Yellow
    choco install nginx -y --version $Version --force
    
    # Nginx suele extraerse en C:\tools\nginx-1.22.1 (con la version en el nombre)
    $BaseDir = ""
    if (Test-Path "C:\tools") {
        $Carpetas = Get-ChildItem -Path "C:\tools" -Filter "nginx*" -Directory
        if ($Carpetas) { $BaseDir = $Carpetas[0].FullName }
    }
    if (-Not (Test-Path "$BaseDir\conf\nginx.conf")) { $BaseDir = "C:\nginx" }
    if (-Not (Test-Path "$BaseDir\conf\nginx.conf")) { $BaseDir = "$env:APPDATA\nginx" }

    if (-Not (Test-Path "$BaseDir\conf\nginx.conf")) {
        Write-Host "ERROR CRITICO: No se encontro la carpeta de Nginx." -ForegroundColor Red
        return
    }

    Write-Host "¡Nginx encontrado en $BaseDir! Aplicando Hardening..." -ForegroundColor Cyan
    $ConfPath = "$BaseDir\conf\nginx.conf"
    
    # Modificar puerto
    (Get-Content $ConfPath) -replace 'listen\s+\d+;', "listen $Puerto;" | Set-Content $ConfPath
    
    # Inyectar Hardening justo despues de la apertura de 'http {'
    $ConfigContent = Get-Content $ConfPath -Raw
    if ($ConfigContent -notmatch "server_tokens off;") {
        $Hardening = "http {`n    server_tokens off;`n    add_header X-Frame-Options SAMEORIGIN;`n    add_header X-Content-Type-Options nosniff;"
        $ConfigContent = $ConfigContent -replace "http\s*\{", $Hardening
        Set-Content -Path $ConfPath -Value $ConfigContent
    }

    Crear-IndexWindows "Nginx Windows" "$Version" "$Puerto" "$BaseDir\html"
    Configurar-FirewallWindows -Puerto $Puerto

    Write-Host "Reiniciando proceso Nginx..." -ForegroundColor Yellow
    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process -FilePath "$BaseDir\nginx.exe" -WorkingDirectory $BaseDir

    Write-Host "Nginx Windows aprovisionado exitosamente." -ForegroundColor Green
}