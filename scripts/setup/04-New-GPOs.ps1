#Requires -Modules GroupPolicy
<#
.SYNOPSIS
    Password/lockout policy, a stricter fine-grained policy for admins, and three
    GPOs linked to the right OUs. Idempotent.

    | GPO                              | Linked to         | Setting                                   |
    |----------------------------------|-------------------|-------------------------------------------|
    | Default Domain Policy            | domain            | 12+ chars, complexity, lockout 5/15 min   |
    | PSO-Admins (fine-grained)        | RG-IT-SysAdmin    | 16+ chars, lockout 3                      |
    | GPO-U-All-ScreenLock             | Corp\Users        | lock screen after 10 min, password needed |
    | GPO-U-SLS-NoControlPanel         | Corp\Users\SLS    | Control Panel / Settings blocked          |
    | GPO-C-Workstations-USBBlock      | Corp\Workstations | removable storage denied                  |
#>
Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
Import-Module GroupPolicy
$c = Get-LabConfig
$root = "OU=$($c.RootOU),$($c.DomainDN)"

# ---- 1. Domain password + lockout policy ----
Set-ADDefaultDomainPasswordPolicy -Identity $c.DomainName `
    -MinPasswordLength 12 -ComplexityEnabled $true -PasswordHistoryCount 24 `
    -MaxPasswordAge '90.00:00:00' -MinPasswordAge '1.00:00:00' `
    -LockoutThreshold 5 -LockoutDuration '00:15:00' -LockoutObservationWindow '00:15:00'
Write-AuditLog -Event SETUP -Target $c.DomainName -Action 'Default password/lockout policy set'

# ---- 2. Fine-grained password policy for privileged role ----
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'PSO-Admins'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy -Name 'PSO-Admins' -Precedence 10 `
        -MinPasswordLength 16 -ComplexityEnabled $true -PasswordHistoryCount 24 `
        -MaxPasswordAge '60.00:00:00' -MinPasswordAge '1.00:00:00' `
        -LockoutThreshold 3 -LockoutDuration '00:30:00' -LockoutObservationWindow '00:30:00' `
        -ReversibleEncryptionEnabled $false
    Add-ADFineGrainedPasswordPolicySubject -Identity 'PSO-Admins' -Subjects 'RG-IT-SysAdmin'
    Write-AuditLog -Event SETUP -Target 'PSO-Admins' -Action 'FGPP created, applied to RG-IT-SysAdmin'
}

# ---- helper ----
function Ensure-GPO {
    param([string]$Name, [string]$LinkTo, [string]$Comment)
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $Name -Comment $Comment }
    $linked = (Get-GPInheritance -Target $LinkTo).GpoLinks | Where-Object DisplayName -eq $Name
    if (-not $linked) { New-GPLink -Name $Name -Target $LinkTo -LinkEnabled Yes | Out-Null }
    Write-AuditLog -Event SETUP -Target $Name -Action "GPO ensured, linked to $LinkTo"
    $gpo
}

# ---- 3. Screen lock for every user ----
$g = Ensure-GPO -Name 'GPO-U-All-ScreenLock' -LinkTo "OU=Users,$root" -Comment 'Lock after 10 min idle'
$k = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
Set-GPRegistryValue -Name $g.DisplayName -Key $k -ValueName 'ScreenSaveActive'    -Type String -Value '1'   | Out-Null
Set-GPRegistryValue -Name $g.DisplayName -Key $k -ValueName 'ScreenSaverIsSecure' -Type String -Value '1'   | Out-Null
Set-GPRegistryValue -Name $g.DisplayName -Key $k -ValueName 'ScreenSaveTimeOut'   -Type String -Value '600' | Out-Null

# ---- 4. Sales: no Control Panel / Settings ----
$g = Ensure-GPO -Name 'GPO-U-SLS-NoControlPanel' -LinkTo "OU=SLS,OU=Users,$root" -Comment 'Sales users cannot change system settings'
Set-GPRegistryValue -Name $g.DisplayName -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
    -ValueName 'NoControlPanel' -Type DWord -Value 1 | Out-Null

# ---- 5. Workstations: block removable storage (data-leak control) ----
$g = Ensure-GPO -Name 'GPO-C-Workstations-USBBlock' -LinkTo "OU=Workstations,$root" -Comment 'Deny all removable storage'
Set-GPRegistryValue -Name $g.DisplayName -Key 'HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices' `
    -ValueName 'Deny_All' -Type DWord -Value 1 | Out-Null

# Back up all GPOs + HTML reports into the repo-friendly folder
$out = Join-Path $c.ReportPath 'gpo'
New-Item -ItemType Directory -Path $out -Force | Out-Null
foreach ($name in 'GPO-U-All-ScreenLock', 'GPO-U-SLS-NoControlPanel', 'GPO-C-Workstations-USBBlock') {
    Get-GPOReport -Name $name -ReportType Html -Path (Join-Path $out "$name.html")
}

Write-Host "GPOs ready. HTML reports in $out" -ForegroundColor Green
Write-Host 'Manual steps left: drive-mapping GPP + audit policy (see docs/04-gpo.md).' -ForegroundColor Yellow
