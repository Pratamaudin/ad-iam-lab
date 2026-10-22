# 01 – Lab setup

## Hardware / software

| Item | Value |
|---|---|
| Host | Any PC with 16 GB RAM (8 GB works with smaller VMs) |
| Hypervisor | VirtualBox 7 (or VMware Workstation / Hyper-V) |
| DC01 | Windows Server 2022 **Evaluation** (180 days, free) — 2 vCPU, 4 GB RAM, 50 GB disk |
| CL01 | Windows 11 Enterprise **Evaluation** (90 days, free) — 2 vCPU, 4 GB RAM, 60 GB disk |
| Network | Adapter 1: NAT (internet for updates) · Adapter 2: Host-only `192.168.56.0/24` |

Both ISOs come from the Microsoft Evaluation Center.

## DC01

1. Install Windows Server 2022 Standard (**Desktop Experience**).
2. Rename and set static IP on the host-only adapter:
   ```powershell
   Rename-Computer -NewName DC01 -Restart
   New-NetIPAddress -InterfaceAlias 'Ethernet 2' -IPAddress 192.168.56.10 -PrefixLength 24
   Set-DnsClientServerAddress -InterfaceAlias 'Ethernet 2' -ServerAddresses 127.0.0.1
   ```
3. Copy this repo to `C:\IAMLab` and allow local scripts:
   ```powershell
   Set-ExecutionPolicy -Scope Process RemoteSigned
   ```
4. Run `scripts\setup\00-Install-ADDS.ps1` → server reboots as a domain controller.
5. Log in as `NUSANTARA\Administrator` and run setup scripts 01 → 04, then the demo.

## CL01

1. Install Windows 11 Enterprise.
2. Host-only adapter: IP `192.168.56.20/24`, **DNS = 192.168.56.10** (the DC — joining fails without this).
3. Join the domain:
   ```powershell
   Add-Computer -DomainName corp.nusantara.lab -Credential NUSANTARA\Administrator -Restart
   ```
4. On DC01, move the computer into the Workstations OU so the USB GPO applies:
   ```powershell
   Get-ADComputer CL01 | Move-ADObject -TargetPath 'OU=Workstations,OU=Corp,DC=corp,DC=nusantara,DC=lab'
   ```
5. On CL01: `gpupdate /force`, reboot.
6. For the helpdesk delegation test, install ADUC on CL01 (helpdesk users must not log on to the DC):
   ```powershell
   Add-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
   ```

## Verifying it works

| Test | How | Expected |
|---|---|---|
| Joiner login | Log in on CL01 as `srahma` with the temp password | Forced to change password |
| Share access (allow) | `srahma` opens `\\DC01\Finance` | Can read, cannot write |
| Share access (deny) | `srahma` opens `\\DC01\HR` | Access denied |
| GPO screen lock | Idle 10 min | Locked, password needed |
| GPO Sales | `asetiawan` opens Settings / Control Panel | Blocked by policy message |
| GPO USB | Plug a USB stick into CL01 | Access denied |
| Delegation allow | As `rkusuma` (helpdesk): ADUC → reset `asetiawan` password | Works |
| Delegation deny | As `rkusuma`: reset `Administrator` password | Access denied |
| Leaver | Try logging in as `bwijaya` | "Your account has been disabled" |
| Effective policy | `gpresult /r` and `gpresult /h report.html` on CL01 | GPOs listed as applied |

Take a screenshot of each — see [screenshots/README.md](screenshots/README.md).
