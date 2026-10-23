# DNS Toggle - shows the active adapter's DNS mode and flips between
# automatic (DHCP -> UDM -> AdGuard) and manual Cloudflare.
# Run with -Probe to print the detected state without opening the GUI.
param([switch]$Probe)

$ManualServers = @('1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001')

function Get-ActiveAdapter {
    # The adapter carrying the default route with the lowest combined metric.
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { (Get-NetAdapter -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue).Status -eq 'Up' } |
        Sort-Object { $_.RouteMetric + (Get-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4).InterfaceMetric } |
        Select-Object -First 1
    if (-not $route) { return $null }
    Get-NetAdapter -InterfaceIndex $route.ifIndex
}

function Get-DnsState {
    $a = Get-ActiveAdapter
    if (-not $a) { return [pscustomobject]@{ Adapter = $null } }
    # A non-empty static NameServer value in the registry means DNS was set by hand.
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)"
    $static = (Get-ItemProperty -Path $key -Name NameServer -ErrorAction SilentlyContinue).NameServer
    $v4 = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses
    $v6 = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv6).ServerAddresses |
        Where-Object { $_ -notlike 'fec0:*' }
    [pscustomobject]@{
        Adapter = $a
        Mode    = if ([string]::IsNullOrWhiteSpace($static)) { 'Automatic (DHCP)' } else { 'Manual' }
        IPv4    = @($v4)
        IPv6    = @($v6)
        Ip      = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                   Select-Object -First 1).IPAddress
    }
}

if ($Probe) {
    $s = Get-DnsState
    if (-not $s.Adapter) { 'No active adapter'; return }
    "Adapter: $($s.Adapter.Name) ($($s.Ip))"
    "Mode:    $($s.Mode)"
    "IPv4:    $($s.IPv4 -join ', ')"
    "IPv6:    $($s.IPv6 -join ', ')"
    return
}

# Changing DNS needs admin; relaunch elevated if we aren't.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    return
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form -Property @{
    Text = 'DNS Toggle'; Size = New-Object System.Drawing.Size(440, 280)
    StartPosition = 'CenterScreen'; FormBorderStyle = 'FixedDialog'; MaximizeBox = $false
    Font = New-Object System.Drawing.Font('Segoe UI', 10)
}

$info = New-Object System.Windows.Forms.Label -Property @{
    Location = New-Object System.Drawing.Point(16, 14); Size = New-Object System.Drawing.Size(400, 130)
}
$mode = New-Object System.Windows.Forms.Label -Property @{
    Location = New-Object System.Drawing.Point(16, 146); Size = New-Object System.Drawing.Size(400, 26)
    Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
}
$toggle = New-Object System.Windows.Forms.Button -Property @{
    Location = New-Object System.Drawing.Point(16, 180); Size = New-Object System.Drawing.Size(300, 40)
}
$refresh = New-Object System.Windows.Forms.Button -Property @{
    Text = 'Refresh'; Location = New-Object System.Drawing.Point(326, 180); Size = New-Object System.Drawing.Size(80, 40)
}
$form.Controls.AddRange(@($info, $mode, $toggle, $refresh))

function Update-View {
    $form.Cursor = 'WaitCursor'
    $script:state = Get-DnsState
    $s = $script:state
    if (-not $s.Adapter) {
        $info.Text = 'No active network adapter found.'; $mode.Text = ''; $toggle.Enabled = $false
    } else {
        $info.Text = "Adapter:  $($s.Adapter.Name)  ($($s.Adapter.InterfaceDescription))`n" +
                     "Address:  $($s.Ip)`n`n" +
                     "DNS (IPv4):  $(if ($s.IPv4) { $s.IPv4 -join ', ' } else { 'none' })`n" +
                     "DNS (IPv6):  $(if ($s.IPv6) { $s.IPv6 -join ', ' } else { 'none' })"
        $toggle.Enabled = $true
        if ($s.Mode -eq 'Manual') {
            $mode.Text = 'Mode: MANUAL'; $mode.ForeColor = [System.Drawing.Color]::DarkOrange
            $toggle.Text = 'Manual is on - revert to automatic'
        } else {
            $mode.Text = 'Mode: Automatic (DHCP)'; $mode.ForeColor = [System.Drawing.Color]::SeaGreen
            $toggle.Text = 'Turn on manual DNS at 1.1.1.1'
        }
    }
    $form.Cursor = 'Default'
}

$toggle.Add_Click({
    $s = $script:state
    try {
        if ($s.Mode -eq 'Manual') {
            Set-DnsClientServerAddress -InterfaceIndex $s.Adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $s.Adapter.ifIndex -ServerAddresses $ManualServers -ErrorAction Stop
        }
        Clear-DnsClientCache
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Couldn't change DNS:`n$($_.Exception.Message)", 'DNS Toggle', 'OK', 'Error') | Out-Null
    }
    Start-Sleep -Milliseconds 800   # let DHCP-provided servers repopulate after a reset
    Update-View
})
$refresh.Add_Click({ Update-View })
$form.Add_Shown({ Update-View })

[void]$form.ShowDialog()
