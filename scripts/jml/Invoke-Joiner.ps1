<#
.SYNOPSIS
    JOINER: onboard a new employee from an HR request.

.DESCRIPTION
    1. Validate the request (department exists, role belongs to department, manager exists)
    2. Generate username by naming standard, create account in the department OU
    3. Assign exactly ONE business role group (RG-*) -> access flows via AGDLP
    4. Force password change at first logon
    5. Check Segregation of Duties, write audit log

.EXAMPLE
    .\Invoke-Joiner.ps1 -FirstName Siti -LastName Rahma -Department FIN -Role RG-FIN-Staff `
        -Title 'Accounts Payable Officer' -Manager dpratama -TicketId HR-1001

.EXAMPLE
    # Bulk onboarding from an HR export
    .\Invoke-Joiner.ps1 -CsvPath ..\..\data\new-hires.csv
#>
[CmdletBinding(DefaultParameterSetName = 'Single', SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'Single', Mandatory)][string]$FirstName,
    [Parameter(ParameterSetName = 'Single', Mandatory)][string]$LastName,
    [Parameter(ParameterSetName = 'Single', Mandatory)][string]$Department,
    [Parameter(ParameterSetName = 'Single', Mandatory)][string]$Role,
    [Parameter(ParameterSetName = 'Single')][string]$Title = '',
    [Parameter(ParameterSetName = 'Single')][string]$Manager = '',
    [Parameter(ParameterSetName = 'Single')][string]$EmployeeId = '',
    [Parameter(ParameterSetName = 'Single', Mandatory)][string]$TicketId,
    [Parameter(ParameterSetName = 'Csv', Mandatory)][string]$CsvPath
)

Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
$c = Get-LabConfig

function New-Joiner {
    param($r)

    # ---------- validation ----------
    if (-not $c.Departments.ContainsKey($r.Department)) { throw "Unknown department '$($r.Department)'" }
    if (-not $c.Roles.ContainsKey($r.Role))             { throw "Unknown role '$($r.Role)'" }
    if ($c.Roles[$r.Role].Department -ne $r.Department) {
        throw "Role $($r.Role) does not belong to department $($r.Department) (request rejected)"
    }
    if ($r.Manager -and -not (Get-ADUser -Filter "SamAccountName -eq '$($r.Manager)'")) {
        throw "Manager '$($r.Manager)' not found"
    }
    if ($r.EmployeeId -and (Get-ADUser -Filter "EmployeeID -eq '$($r.EmployeeId)'")) {
        throw "EmployeeID $($r.EmployeeId) already has an account (possible rehire: use Mover/re-enable)"
    }

    # ---------- create ----------
    $sam  = New-LabSamAccountName -FirstName $r.FirstName -LastName $r.LastName
    $upn  = "$sam@$($c.DomainName)"
    $temp = New-LabTempPassword

    $params = @{
        Name                  = "$($r.FirstName) $($r.LastName)"
        GivenName             = $r.FirstName
        Surname               = $r.LastName
        DisplayName           = "$($r.FirstName) $($r.LastName)"
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        Path                  = Get-DeptOUPath $r.Department
        Department            = $c.Departments[$r.Department]
        Title                 = $r.Title
        Company               = 'Nusantara Corp (lab)'
        AccountPassword       = (ConvertTo-SecureString $temp -AsPlainText -Force)
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }
    if ($r.EmployeeId) { $params.EmployeeID = $r.EmployeeId }
    if ($r.Manager)    { $params.Manager    = $r.Manager }

    if ($PSCmdlet.ShouldProcess($sam, 'Create user')) {
        New-ADUser @params
        Add-ADGroupMember -Identity $r.Role -Members $sam

        Write-AuditLog -Event JOINER -TicketId $r.TicketId -Target $sam -Action 'Account created' `
            -Detail "OU=$($r.Department); Role=$($r.Role); Manager=$($r.Manager)"

        $sod = Test-LabSoD -SamAccountName $sam
        if ($sod) {
            Write-Warning "SoD conflict for ${sam}: $($sod.ConflictA) + $($sod.ConflictB)"
            Write-AuditLog -Event JOINER -TicketId $r.TicketId -Target $sam -Action 'SoD WARNING' -Detail ($sod | Out-String).Trim()
        }

        [pscustomobject]@{
            SamAccountName = $sam
            UPN            = $upn
            Role           = $r.Role
            TempPassword   = $temp   # LAB ONLY - shown once, never logged
        }
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Csv') {
    foreach ($row in Import-Csv $CsvPath) {
        try   { New-Joiner $row }
        catch { Write-Warning "Row $($row.FirstName) $($row.LastName) skipped: $($_.Exception.Message)" }
    }
}
else {
    New-Joiner ([pscustomobject]@{
        FirstName = $FirstName; LastName = $LastName; Department = $Department; Role = $Role
        Title = $Title; Manager = $Manager; EmployeeId = $EmployeeId; TicketId = $TicketId
    })
}
