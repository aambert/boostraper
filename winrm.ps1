rite-Host "Delete any existing WinRM listeners"
winrm delete winrm/config/listener?Address=*+Transport=HTTP  2>$Null
winrm delete winrm/config/listener?Address=*+Transport=HTTPS 2>$Null

Write-Host "Create a new WinRM listener and configure"
winrm create winrm/config/listener?Address=*+Transport=HTTPS
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="0"}'
winrm set winrm/config '@{MaxTimeoutms="7200000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="12000"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

Write-Host "Configure UAC to allow privilege elevation in remote shells"
$Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$Setting = 'LocalAccountTokenFilterPolicy'
Set-ItemProperty -Path $Key -Name $Setting -Value 1 -Force

Write-Host "turn off PowerShell execution policy restrictions"
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine
New-Item                                                                       `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" `
    -Force

Set-NetConnectionProfile                                                       `
    -InterfaceIndex (Get-NetConnectionProfile).InterfaceIndex                  `
    -NetworkCategory Private

Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value True
Set-Item WSMan:\localhost\Service\Auth\Basic       -Value True
Write-Host "Configure and restart the WinRM Service; Enable the required firewall exception"
Stop-Service -Name WinRM
Set-Service -Name WinRM -StartupType Automatic
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new action=allow localip=any remoteip=any
Start-Service -Name WinRM

$profiles = Get-NetConnectionProfile
Foreach ($i in $profiles) {
    Write-Host ("Updating Interface ID {0} to be Private.." -f $profiles.InterfaceIndex)
    Set-NetConnectionProfile -InterfaceIndex $profiles.InterfaceIndex -NetworkCategory Private
}

Write-Host "Obtaining the Thumbprint of the Certificate from KeyVault"
$Thumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -match "$ComputerName"}).Thumbprint

Write-Host "Enable HTTPS in WinRM.."
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$ComputerName`"; CertificateThumbprint=`"$Thumbprint`"}"

Write-Host "Enabling Basic Authentication.."
winrm set winrm/config/service/Auth "@{Basic=`"true`"}"

Write-Host "Re-starting the WinRM Service"
net stop winrm
net start winrm

Write-Host "Open Firewall Ports"
netsh advfirewall firewall add rule name="Windows Remote Management (HTTPS-In)" dir=in action=allow protocol=TCP localport=5986
