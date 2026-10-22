<#
.SYNOPSIS
    Promote a fresh Windows Server 2022 VM to the first domain controller of corp.nusantara.lab.
.NOTES
    Run once, as local Administrator, AFTER giving the VM a static IP (e.g. 192.168.56.10)
    and renaming it (e.g. DC01). The server reboots at the end.
#>
[CmdletBinding()]
param(
    [string]$DomainName  = 'corp.nusantara.lab',
    [string]$NetBIOSName = 'NUSANTARA'
)

Install-WindowsFeature AD-Domain-Services, DNS, GPMC, RSAT-AD-Tools -IncludeManagementTools

$dsrm = Read-Host -AsSecureString 'DSRM (Directory Services Restore Mode) password'

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBIOSName `
    -ForestMode 'WinThreshold' `
    -DomainMode 'WinThreshold' `
    -InstallDns `
    -SafeModeAdministratorPassword $dsrm `
    -Force
