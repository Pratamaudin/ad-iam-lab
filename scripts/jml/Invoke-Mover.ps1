<#
.SYNOPSIS
    MOVER: an employee changes department or role.

.DESCRIPTION
    The classic IAM failure here is PRIVILEGE CREEP: the new access is added but the
    old access is never removed. This script does remove-then-add:
      1. Record current role groups (before snapshot)
      2. Remove ALL RG-* role memberships
      3. Move account to the new department OU, update attributes
      4. Add the new role, run SoD check, record after snapshot

    Direct DL-*/ad-hoc memberships are NOT silently kept: they are listed as
    a warning so the new manager must re-request them.

.EXAMPLE
    .\Invoke-Mover.ps1 -SamAccountName sputri -NewDepartment FIN -NewRole RG-FIN-Staff `
        -NewTitle 'Finance Analyst' -NewManager dpratama -TicketId HR-1007
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$SamAccountName,
    [Parameter(Mandatory)][string]$NewDepartment,
    [Parameter(Mandatory)][string]$NewRole,
    [string]$NewTitle,
    [string]$NewManager,
    [Parameter(Mandatory)][string]$TicketId
)

Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
$c = Get-LabConfig

# ---------- validation ----------
$user = Get-ADUser $SamAccountName -Properties MemberOf, Department, Title, Manager, Enabled
if (-not $user.Enabled)                                  { throw "$SamAccountName is disabled (leaver?). Use rehire process." }
if (-not $c.Departments.ContainsKey($NewDepartment))     { throw "Unknown department '$NewDepartment'" }
if (-not $c.Roles.ContainsKey($NewRole))                 { throw "Unknown role '$NewRole'" }
if ($c.Roles[$NewRole].Department -ne $NewDepartment)    { throw "Role $NewRole is not part of $NewDepartment" }

$currentGroups = $user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
$oldRoles      = $currentGroups | Where-Object { $_ -like 'RG-*' }
$adHoc         = $currentGroups | Where-Object { $_ -notlike 'RG-*' -and $_ -ne 'Domain Users' }

Write-AuditLog -Event MOVER -TicketId $TicketId -Target $SamAccountName -Action 'Before snapshot' `
    -Detail "Dept=$($user.Department); Roles=$($oldRoles -join ',' ); AdHoc=$($adHoc -join ',')"

if ($PSCmdlet.ShouldProcess($SamAccountName, "Move to $NewDepartment / $NewRole")) {

    # 1. Remove old roles (stops privilege creep)
    foreach ($r in $oldRoles) {
        Remove-ADGroupMember -Identity $r -Members $SamAccountName -Confirm:$false
        Write-AuditLog -Event MOVER -TicketId $TicketId -Target $SamAccountName -Action "Removed role $r"
    }

    # 2. Move OU + attributes
    Move-ADObject -Identity $user.DistinguishedName -TargetPath (Get-DeptOUPath $NewDepartment)
    $set = @{ Department = $c.Departments[$NewDepartment] }
    if ($NewTitle)   { $set.Title   = $NewTitle }
    if ($NewManager) { $set.Manager = $NewManager }
    Set-ADUser $SamAccountName @set

    # 3. New role
    Add-ADGroupMember -Identity $NewRole -Members $SamAccountName
    Write-AuditLog -Event MOVER -TicketId $TicketId -Target $SamAccountName -Action "Added role $NewRole" `
        -Detail "Moved to OU=$NewDepartment"

    if ($adHoc) {
        Write-Warning "Ad-hoc memberships kept for review (new manager must confirm or remove): $($adHoc -join ', ')"
    }

    $sod = Test-LabSoD -SamAccountName $SamAccountName
    if ($sod) {
        Write-Warning "SoD conflict after move: $($sod.ConflictA) + $($sod.ConflictB)"
        Write-AuditLog -Event MOVER -TicketId $TicketId -Target $SamAccountName -Action 'SoD WARNING' -Detail ($sod | Out-String).Trim()
    }

    $after = (Get-ADUser $SamAccountName -Properties MemberOf).MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
    Write-AuditLog -Event MOVER -TicketId $TicketId -Target $SamAccountName -Action 'After snapshot' -Detail ($after -join ',')
}
