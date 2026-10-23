# DNS Toggle

A tiny Windows GUI (PowerShell + WinForms) that shows your active network adapter's DNS settings and flips them with one button:

- **Automatic (DHCP)** → button: *Turn on manual DNS at 1.1.1.1*
- **Manual** → button: *Manual is on - revert to automatic*

Useful when your home DNS server (Pi-hole, AdGuard Home, etc.) is down and you want to fall back to Cloudflare quickly, then switch back.

## What it shows

- The active adapter (the one carrying the default route) and its IPv4 address
- DNS mode: Automatic (DHCP) or Manual
- Current IPv4 and IPv6 DNS servers

Manual mode sets `1.1.1.1`, `1.0.0.1`, `2606:4700:4700::1111` and `2606:4700:4700::1001`. Edit `$ManualServers` at the top of the script to use something else. Each switch also flushes the DNS cache.

## Requirements

- Windows 10/11 with Windows PowerShell 5.1 (built in)
- Admin rights to change DNS. The script relaunches itself elevated, so expect a UAC prompt.

## Install

1. Put `DnsToggle.ps1` somewhere permanent, e.g. `C:\Tools\dns-toggle\`.
2. Create a Start menu shortcut (run in PowerShell, adjusting the path):

   ```powershell
   $p   = 'C:\Tools\dns-toggle\DnsToggle.ps1'
   $lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DNS Toggle.lnk"
   $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
   $s.TargetPath   = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
   $s.Arguments    = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$p`""
   $s.IconLocation = "$env:WINDIR\System32\netshell.dll,0"
   $s.Save()
   ```

3. Find **DNS Toggle** in the Start menu, right-click it, and pin it to Start or the taskbar.

## Check the state without the GUI

```powershell
.\DnsToggle.ps1 -Probe
```

Prints the adapter, mode and DNS servers, and changes nothing.

## How it decides "Manual"

Windows stores hand-set DNS servers in the adapter's `NameServer` registry value under `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{GUID}`. If that value is non-empty, the mode is Manual; otherwise the servers came from DHCP.

## License

MIT
