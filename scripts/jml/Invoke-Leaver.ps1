<#
.SYNOPSIS
    LEAVER: offboard an employee on their last day.

.DESCRIPTION
    Disable first, delete later. Steps:
      1. Snapshot every group membership to JSON (so access can be restored if HR made a mistake,
         and so auditors can see what was removed)
      2. Disable the account and scramble the password
      3. Remove all group memberships except Domain Users
      4. Move to Corp\Disabled Users, stamp description with date + ticket
      5. (separate mode) -PurgeOlderThanDays deletes accounts that have sat disabled long enough

.EXAMPLE
    .\Invoke-Leaver.ps1 -SamAccountName bwijaya -TicketId HR-1012

.EXAMPLE
    .\Invoke-Leaver.ps1 -PurgeOlderThanDays 30 -WhatIf
#>
[CmdletBinding(DefaultParameterSetName = 'Offboard', SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(ParameterSetName = 'Offboard', Mandatory)][string]$SamAccountName,
    [Parameter(ParameterSetName = 'Offboard', Mandatory)][string]$TicketId,
    [Parameter(ParameterSetName = 'Purge', Mandatory)][int]$PurgeOlderThanDays
)

Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
$c = Get-LabConfig

if ($PSCmdlet.ParameterSetName -eq 'Purge') {
    $cutoff = (Get-Date).AddDays(-$PurgeOlderThanDays)
    Get-ADUser -SearchBase (Get-DisabledOUPath) -Filter 'Enabled -eq $false' -Properties whenChanged |
        Where-Object whenChanged -lt $cutoff |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.SamAccountName, 'Delete disabled account')) {
                Remove-ADUser $_ -Confirm:$false
                Write-AuditLog -Event LEAVER -Target $_.SamAccountName -Action "Deleted (disabled > $PurgeOlderThanDays days)"
            }
        }
    return
}

$user = Get-ADUser $SamAccountName -Properties MemberOf, Department, Title, Manager, Description

# 1. Snapshot
if (-not (Test-Path $c.SnapshotPath)) { New-Item -ItemType Directory -Path $c.SnapshotPath -Force | Out-Null }
$groups = $user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
$snapFile = Join-Path $c.SnapshotPath ("{0}_{1:yyyyMMdd-HHmmss}.json" -f $SamAccountName, (Get-Date))
[pscustomobject]@{
    SamAccountName = $SamAccountName
    TicketId       = $TicketId
    Department     = $user.Department
    Title          = $user.Title
    Manager        = $user.Manager
    OriginalOU     = ($user.DistinguishedName -split ',', 2)[1]
    Groups         = $groups
    TakenAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json | Set-Content -Path $snapFile -Encoding UTF8
Write-AuditLog -Event LEAVER -TicketId $TicketId -Target $SamAccountName -Action 'Access snapshot saved' -Detail $snapFile

if ($PSCmdlet.ShouldProcess($SamAccountName, 'Disable and strip access')) {

    # 2. Disable + scramble password (kills any password the user may have shared)
    Disable-ADAccount $SamAccountName
    Set-ADAccountPassword $SamAccountName -Reset -NewPassword (ConvertTo-SecureString (New-LabTempPassword) -AsPlainText -Force)
    Write-AuditLog -Event LEAVER -TicketId $TicketId -Target $SamAccountName -Action 'Disabled + password scrambled'

    # 3. Strip memberships
    foreach ($g in $groups) {
        Remove-ADGroupMember -Identity $g -Members $SamAccountName -Confirm:$false
        Write-AuditLog -Event LEAVER -TicketId $TicketId -Target $SamAccountName -Action "Removed from $g"
    }

    # 4. Park in Disabled Users
    $stamp = "LEAVER {0:yyyy-MM-dd} {1} | was: {2}" -f (Get-Date), $TicketId, $user.Title
    Set-ADUser $SamAccountName -Description $stamp -Clear manager
    Move-ADObject -Identity $user.DistinguishedName -TargetPath (Get-DisabledOUPath)
    Write-AuditLog -Event LEAVER -TicketId $TicketId -Target $SamAccountName -Action 'Moved to Disabled Users'
}
