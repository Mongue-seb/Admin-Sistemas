
$AppCmd = "$env:windir\System32\inetsrv\appcmd.exe"

function Instalar-RolIIS {
    Write-Host "`n[+] Instalando nucleo IIS, FTP y EXTENSIBILIDAD..." -ForegroundColor Yellow
    # FIX: El nombre interno correcto es Web-FTP-Ext
    Install-WindowsFeature Web-FTP-Server, Web-FTP-Service, Web-FTP-Ext, Web-Mgmt-Console -IncludeManagementTools | Out-Null
    Write-Host "[-] Instalacion completa. El motor ya soporta comandos de seguridad." -ForegroundColor Green
}

function Preparar-ServidorFTP {
    Write-Host "`n[+] Purificando y Preparando Servidor FTP..." -ForegroundColor Yellow
    try { Import-Module WebAdministration -Force -ErrorAction SilentlyContinue } catch { }
    
    # 1. Relajar politicas de contrasenas
    $SecPol = "C:\secpol.cfg"
    secedit /export /cfg $SecPol | Out-Null
    (Get-Content $SecPol) -replace 'PasswordComplexity = 1', 'PasswordComplexity = 0' | Set-Content $SecPol
    (Get-Content $SecPol) -replace 'MinimumPasswordLength = \d+', 'MinimumPasswordLength = 0' | Set-Content $SecPol
    secedit /configure /db $env:windir\security\local.sdb /cfg $SecPol /areas SECURITYPOLICY | Out-Null
    Remove-Item $SecPol -Force 2>$null

    # 2. Crear Grupos
    try { New-LocalGroup -Name "reprobados" -ErrorAction SilentlyContinue | Out-Null } catch { }
    try { New-LocalGroup -Name "recursadores" -ErrorAction SilentlyContinue | Out-Null } catch { }

    # 3. Estructura de Directorios Exacta
    $RealRoot = "C:\FTP_Real"
    $IsoRoot = "C:\FTP_Root"
    $AnonRoot = "$IsoRoot\LocalUser\Public"

    foreach ($dir in @($RealRoot, "$RealRoot\general", "$RealRoot\reprobados", "$RealRoot\recursadores", $IsoRoot, "$IsoRoot\LocalUser", $AnonRoot)) {
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory | Out-Null }
    }

    # 4. Permisos NTFS Universales (El S-1-1-0 infalible)
    Write-Host "[+] Aplicando permisos NTFS (*S-1-1-0)..." -ForegroundColor Cyan
    icacls "$IsoRoot" /grant "*S-1-1-0:(RX)" /Q | Out-Null
    icacls "$IsoRoot\LocalUser" /grant "*S-1-1-0:(RX)" /Q | Out-Null
    icacls "$RealRoot\general" /grant "*S-1-1-0:(RX)" /Q | Out-Null
    icacls "$RealRoot\general" /grant "Users:(M)" /Q | Out-Null
    icacls "$RealRoot\reprobados" /grant "reprobados:(OI)(CI)(M)" /Q | Out-Null
    icacls "$RealRoot\recursadores" /grant "recursadores:(OI)(CI)(M)" /Q | Out-Null

    if (-not (Test-Path "$AnonRoot\general")) { cmd /c mklink /J "$AnonRoot\general" "$RealRoot\general" | Out-Null }

    # 5. Destruir y Recrear IIS (La Opcion Nuclear)
    Write-Host "[+] Configurando IIS..." -ForegroundColor Cyan
    & $AppCmd stop site "FTPServer" 2>$null | Out-Null
    & $AppCmd delete site "FTPServer" 2>$null | Out-Null

    New-WebFtpSite -Name "FTPServer" -Port 21 -PhysicalPath $IsoRoot -Force | Out-Null
    
    # 6. Forzar Autenticacion Basic a la fuerza (Directo al apphost)
    & $AppCmd set config "FTPServer" -section:system.ftpServer/security/authentication/basicAuthentication /enabled:"True" /defaultLogonDomain:"" /commit:apphost | Out-Null
    
    # 7. Quitar SSL y Modo Aislamiento 2
    Set-ItemProperty "IIS:\Sites\FTPServer" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\FTPServer" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\FTPServer" -Name ftpServer.userIsolation.mode -Value 2

    # 8. Reglas de Autorizacion Nativas
    & $AppCmd clear config "FTPServer" -section:system.ftpServer/security/authorization /commit:apphost | Out-Null
    & $AppCmd set config "FTPServer" -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='*',permissions='Read, Write']" /commit:apphost | Out-Null
    
    Restart-WebItem "IIS:\Sites\FTPServer"
    Write-Host "[-] Servidor FTP base listo y configurado al 100%." -ForegroundColor Green
}

function Gestionar-UsuariosFTP {
    Write-Host "`n=======================================" -ForegroundColor Yellow
    $NumUsers = Read-Host "Cuantos usuarios deseas crear/gestionar?"
    if (-not [int]::TryParse($NumUsers, [ref]$null)) { return }
    
    for ($i = 1; $i -le [int]$NumUsers; $i++) {
        $Usr = Read-Host "Nombre de usuario"
        $Pass = Read-Host "Contrasena (Ej. hola1234)"
        $Grp = Read-Host "Grupo (reprobados o recursadores)"

        # Solucion SAM: Evitar caducidad
        net user $Usr $Pass /add /y 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { net user $Usr $Pass 2>$null | Out-Null }
        net user $Usr /active:yes | Out-Null
        wmic useraccount where "name='$Usr'" set PasswordExpires=FALSE | Out-Null

        # Asignar grupo
        net localgroup reprobados $Usr /delete 2>$null | Out-Null
        net localgroup recursadores $Usr /delete 2>$null | Out-Null
        net localgroup $Grp $Usr /add 2>$null | Out-Null

        # Crear Jaula en LocalUser
        $UserRoot = "C:\FTP_Root\LocalUser\$Usr"
        $PersonalPath = "$UserRoot\$Usr"
        if (-not (Test-Path $UserRoot)) { New-Item -Path $UserRoot -ItemType Directory | Out-Null }
        if (-not (Test-Path $PersonalPath)) { New-Item -Path $PersonalPath -ItemType Directory | Out-Null }
        
        # Permisos exactos de la jaula
        icacls "$UserRoot" /grant "${Usr}:(RX)" /Q | Out-Null
        icacls "$PersonalPath" /grant "${Usr}:(OI)(CI)(F)" /Q | Out-Null

        # Enlaces (Junctions)
        if (Test-Path "$UserRoot\reprobados") { cmd /c rmdir "$UserRoot\reprobados" 2>$null }
        if (Test-Path "$UserRoot\recursadores") { cmd /c rmdir "$UserRoot\recursadores" 2>$null }

        if (-not (Test-Path "$UserRoot\general")) { cmd /c mklink /J "$UserRoot\general" "C:\FTP_Real\general" | Out-Null }
        cmd /c mklink /J "$UserRoot\$Grp" "C:\FTP_Real\$Grp" | Out-Null

        Write-Host "[-] Jaula de $Usr creada exitosamente." -ForegroundColor Green
    }
    
    # Reiniciar todo el motor para refrescar cache
    Write-Host "[+] Refrescando cache de seguridad..." -ForegroundColor Cyan
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
}

while ($true) {
    Write-Host "`n=============================" -ForegroundColor DarkCyan
    Write-Host "  MENU FTP V5 INFALIBLE" -ForegroundColor DarkCyan
    Write-Host "=============================" -ForegroundColor DarkCyan
    Write-Host "1) Instalar Rol IIS (Fix Extensibilidad)"
    Write-Host "2) Preparar/Resetear Servidor FTP"
    Write-Host "3) Gestionar Usuarios y Jaulas"
    Write-Host "4) Salir"
    
    $Opc = Read-Host "Elige una opcion"
    switch ($Opc) {
        "1" { Instalar-RolIIS }
        "2" { Preparar-ServidorFTP }
        "3" { Gestionar-UsuariosFTP }
        "4" { exit }
        default { Write-Host "Opcion Invalida." -ForegroundColor Red }
    }
}