function Instalar-SSH {
    Write-Host "`n--- INSTALACION DE OPENSSH SERVER ---" -ForegroundColor Cyan
    Write-Host "Instalando binarios de OpenSSH..." -ForegroundColor Yellow
    
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "Configurando el servicio para arranque automatico..."
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType 'Automatic'
    
    Write-Host "Abriendo el puerto 22 en el Firewall de Windows..."
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "Instalacion completada." -ForegroundColor Green
    Write-Host "HITO CRITICO: Usa SSH para conectarte de forma remota." -ForegroundColor Magenta
}