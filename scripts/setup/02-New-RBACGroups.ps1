<#
.SYNOPSIS
    Create role groups (RG-*, Global) and resource groups (DL-*, Domain Local),
    nest roles into resources (AGDLP), create file shares and apply NTFS permissions.
    Idempotent.
#>
Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
$c = Get-LabConfig
$root      = "OU=$($c.RootOU),$($c.DomainDN)"
$rolesOU   = "OU=Roles,OU=Groups,$root"
$resOU     = "OU=Resources,OU=Groups,$root"

# 1. Resource groups (Domain Local)
foreach ($name in $c.Resources.Keys) {
    if (-not (Get-ADGroup -Filter "Name -eq '$name'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $name -GroupScope DomainLocal -GroupCategory Security `
            -Path $resOU -Description $c.Resources[$name].Description
        Write-AuditLog -Event SETUP -Target $name -Action 'Resource group created'
    }
}

# 2. Role groups (Global) + nesting into resource groups
foreach ($role in $c.Roles.Keys) {
    $def = $c.Roles[$role]
    if (-not (Get-ADGroup -Filter "Name -eq '$role'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $role -GroupScope Global -GroupCategory Security `
            -Path $rolesOU -Description $def.Description
        Write-AuditLog -Event SETUP -Target $role -Action 'Role group created'
    }
    foreach ($res in $def.Resources) {
        $already = Get-ADGroupMember $res | Where-Object Name -eq $role
        if (-not $already) {
            Add-ADGroupMember -Identity $res -Members $role
            Write-AuditLog -Event SETUP -Target $res -Action "Nested role $role"
        }
    }
}

# 3. File shares + NTFS permissions driven by DL groups only (never by user)
$shares = $c.Resources.Values | Where-Object Share | Select-Object -ExpandProperty Share -Unique
foreach ($share in $shares) {
    $path = Join-Path $c.ShareRoot $share
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }

    # Remove inherited "Users" access, keep SYSTEM + Administrators
    $acl = Get-Acl $path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($id in 'NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators') {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $id, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    foreach ($kv in $c.Resources.GetEnumerator() | Where-Object { $_.Value.Share -eq $share }) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$($c.NetBIOSName)\$($kv.Key)", $kv.Value.Right, 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    Set-Acl -Path $path -AclObject $acl

    if (-not (Get-SmbShare -Name $share -ErrorAction SilentlyContinue)) {
        # Share permission = Authenticated Users Change; real control is NTFS
        New-SmbShare -Name $share -Path $path -ChangeAccess 'Authenticated Users' | Out-Null
    }
    Write-AuditLog -Event SETUP -Target "\\$env:COMPUTERNAME\$share" -Action 'Share + NTFS ACL applied'
}

Write-Host 'RBAC groups and shares ready.' -ForegroundColor Green
