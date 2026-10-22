#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Shared helpers for the AD IAM lab: config loading, audit logging, naming rules.
#>

$script:ConfigPath = Join-Path $PSScriptRoot '..\config\LabConfig.psd1'

function Get-LabConfig {
    Import-PowerShellDataFile -Path $script:ConfigPath
}

function Get-DeptOUPath {
    param([Parameter(Mandatory)][string]$DeptCode)
    $c = Get-LabConfig
    "OU=$DeptCode,OU=Users,OU=$($c.RootOU),$($c.DomainDN)"
}

function Get-DisabledOUPath {
    $c = Get-LabConfig
    "OU=Disabled Users,OU=$($c.RootOU),$($c.DomainDN)"
}

function New-LabSamAccountName {
    <#
        Naming standard: first initial + last name, lowercase, max 20 chars.
        Collisions get a numeric suffix: jsantoso, jsantoso2, jsantoso3 ...
    #>
    param(
        [Parameter(Mandatory)][string]$FirstName,
        [Parameter(Mandatory)][string]$LastName
    )
    $base = ($FirstName.Substring(0, 1) + $LastName) -replace '[^a-zA-Z0-9]', ''
    $base = $base.ToLower()
    if ($base.Length -gt 18) { $base = $base.Substring(0, 18) }

    $candidate = $base
    $i = 2
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $candidate = "$base$i"
        $i++
    }
    $candidate
}

function New-LabTempPassword {
    # Random 16-char password (plain string, LAB ONLY); user must change at first logon.
    # In production this goes to the manager via a secure channel, never into logs.
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%*?'
    $pw = -join (1..12 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    'Aa1!' + $pw   # guarantee all complexity classes
}

function Write-AuditLog {
    <#
        Every identity change is appended to one CSV: this is the evidence trail
        an auditor (or a SOC analyst) would ask for.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('JOINER', 'MOVER', 'LEAVER', 'ACCESS_REVIEW', 'SETUP')][string]$Event,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Action,
        [string]$TicketId = '-',
        [string]$Detail = ''
    )
    $c = Get-LabConfig
    $dir = Split-Path $c.AuditLogPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    [pscustomobject]@{
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Event        = $Event
        TicketId     = $TicketId
        Target       = $Target
        Action       = $Action
        Detail       = $Detail
        PerformedBy  = "$env:USERDOMAIN\$env:USERNAME"
    } | Export-Csv -Path $c.AuditLogPath -Append -NoTypeInformation -Encoding UTF8

    Write-Host ("[{0}] {1} {2}: {3}" -f $Event, $TicketId, $Target, $Action)
}

function Test-LabSoD {
    <#
        Returns SoD violations for one user (or nothing).
        Checks nested membership, so RG -> DL chains are evaluated.
    #>
    param([Parameter(Mandatory)][string]$SamAccountName)
    $c = Get-LabConfig
    $user = Get-ADUser $SamAccountName
    # LDAP_MATCHING_RULE_IN_CHAIN: all groups incl. nested
    $groups = Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=$($user.DistinguishedName))" |
        Select-Object -ExpandProperty Name

    foreach ($pair in $c.SoDConflicts) {
        if ($groups -contains $pair[0] -and $groups -contains $pair[1]) {
            [pscustomobject]@{ User = $SamAccountName; ConflictA = $pair[0]; ConflictB = $pair[1] }
        }
    }
}

Export-ModuleMember -Function *
