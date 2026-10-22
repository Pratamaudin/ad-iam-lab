<#
.SYNOPSIS
    Least-privilege delegation: RG-IT-Helpdesk can reset passwords and unlock
    accounts for users under Corp\Users ONLY. Not Domain Admins, not Admins OU.
.NOTES
    Verify afterwards: log in as a helpdesk user, try to reset a Sales user's
    password (should work) and an adm-* account's password (should be denied).
#>
Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
$c = Get-LabConfig
$usersOU = "OU=Users,OU=$($c.RootOU),$($c.DomainDN)"
$trustee = "$($c.NetBIOSName)\RG-IT-Helpdesk"

# /I:S = inherit to sub-objects only, scoped to user objects
dsacls $usersOU /I:S /G "${trustee}:CA;Reset Password;user"   | Out-Null   # reset password
dsacls $usersOU /I:S /G "${trustee}:RPWP;pwdLastSet;user"     | Out-Null   # force "change at next logon"
dsacls $usersOU /I:S /G "${trustee}:RPWP;lockoutTime;user"    | Out-Null   # unlock account

Write-AuditLog -Event SETUP -Target $usersOU -Action "Delegated reset/unlock to $trustee"
Write-Host 'Helpdesk delegation applied.' -ForegroundColor Green
