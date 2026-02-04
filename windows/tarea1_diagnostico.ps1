Write-Host "Nombre del equipo:"
hostname

Write-Host "nIP actual:"
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {$_.IPAddress -notlike "169.*"} |
    Select-Object -ExpandProperty IPAddress

Write-Host "nEspacio en disco:"
Get-PSDrive -PSProvider FileSystem | 
    Select-Object Name, @{Name="Used(GB)";Expression={[math]::Round($.Used/1GB,2)}}, @{Name="Free(GB)";Expression={[math]::Round($.Free/1GB,2)}}