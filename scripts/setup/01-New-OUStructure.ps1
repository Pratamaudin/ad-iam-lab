<#
.SYNOPSIS
    Build the OU tree. Idempotent: safe to re-run.

    corp.nusantara.lab
    └── Corp
        ├── Users
        │   ├── IT / FIN / HR / SLS
        ├── Groups
        │   ├── Roles        (RG-*  Global groups = business roles)
        │   └── Resources    (DL-*  Domain Local groups = permissions)
        ├── Admins           (privileged accounts, separate from daily accounts)
        ├── Service Accounts
        ├── Workstations
        └── Disabled Users   (leavers parked here before deletion)
#>
Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
$c = Get-LabConfig
$root = "OU=$($c.RootOU),$($c.DomainDN)"

function Ensure-OU {
    param([string]$Name, [string]$Path, [string]$Description)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -Description $Description -ProtectedFromAccidentalDeletion $true
        Write-AuditLog -Event SETUP -Target $dn -Action 'OU created'
    }
}

Ensure-OU -Name $c.RootOU -Path $c.DomainDN -Description 'Lab company root'
Ensure-OU -Name 'Users'            -Path $root -Description 'Standard user accounts'
Ensure-OU -Name 'Groups'           -Path $root -Description 'Security groups'
Ensure-OU -Name 'Roles'            -Path "OU=Groups,$root" -Description 'RG-* business role groups (Global)'
Ensure-OU -Name 'Resources'        -Path "OU=Groups,$root" -Description 'DL-* resource/permission groups (Domain Local)'
Ensure-OU -Name 'Admins'           -Path $root -Description 'Privileged (adm-*) accounts'
Ensure-OU -Name 'Service Accounts' -Path $root -Description 'Non-human accounts'
Ensure-OU -Name 'Workstations'     -Path $root -Description 'Domain-joined clients'
Ensure-OU -Name 'Disabled Users'   -Path $root -Description 'Leavers awaiting deletion'

foreach ($dept in $c.Departments.Keys) {
    Ensure-OU -Name $dept -Path "OU=Users,$root" -Description $c.Departments[$dept]
}

Write-Host 'OU structure ready.' -ForegroundColor Green
