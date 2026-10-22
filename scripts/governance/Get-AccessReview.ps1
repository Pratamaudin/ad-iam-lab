<#
.SYNOPSIS
    ACCESS REVIEW / ATTESTATION: who has what, and what looks wrong.

.DESCRIPTION
    Produces three files in $ReportPath\access-review-<date>\ :
      - entitlements.csv   one row per user: roles, ad-hoc groups, effective resources
      - findings.csv       one row per issue, with severity and suggested action
      - summary.html       the page a manager would sign off

    Checks:
      F1  Disabled account still holds group memberships      (leaver not finished)
      F2  Direct membership in a DL-* group                    (RBAC bypass)
      F3  Role group does not match the user's department OU   (mover leftover / privilege creep)
      F4  More than one business role                           (role explosion)
      F5  Segregation-of-Duties conflict
      F6  Enabled but no logon in N days / never logged on      (orphan / stale account)
      F7  Member of a built-in privileged group                (needs explicit justification)
      F8  PasswordNeverExpires set on a human account
#>
Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force
$c = Get-LabConfig

$outDir = Join-Path $c.ReportPath ("access-review-{0:yyyy-MM-dd}" -f (Get-Date))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$searchBase = "OU=$($c.RootOU),$($c.DomainDN)"
$users = Get-ADUser -SearchBase $searchBase -Filter * -Properties `
    MemberOf, Department, Title, Enabled, LastLogonDate, whenCreated, PasswordNeverExpires, Manager

$privileged = 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators', 'Account Operators', 'Backup Operators'
$entitlements = [System.Collections.Generic.List[object]]::new()
$findings     = [System.Collections.Generic.List[object]]::new()

function Add-Finding($user, $id, $sev, $issue, $action) {
    $findings.Add([pscustomobject]@{
        User = $user.SamAccountName; Finding = $id; Severity = $sev
        Issue = $issue; SuggestedAction = $action
    })
}

foreach ($u in $users) {
    $direct = @($u.MemberOf | ForEach-Object { (Get-ADGroup $_).Name })
    $effective = @(Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=$($u.DistinguishedName))" |
        Select-Object -ExpandProperty Name)
    $roles  = @($direct | Where-Object { $_ -like 'RG-*' })
    $dlDirect = @($direct | Where-Object { $_ -like 'DL-*' })
    $ouDept = if ($u.DistinguishedName -match 'OU=([^,]+),OU=Users,') { $Matches[1] } else { $null }

    $entitlements.Add([pscustomobject]@{
        User          = $u.SamAccountName
        Name          = $u.Name
        Enabled       = $u.Enabled
        OUDepartment  = $ouDept
        Title         = $u.Title
        Roles         = $roles -join '; '
        DirectGroups  = ($direct | Where-Object { $_ -notlike 'RG-*' }) -join '; '
        EffectiveDL   = ($effective | Where-Object { $_ -like 'DL-*' }) -join '; '
        LastLogon     = $u.LastLogonDate
    })

    # F1
    if (-not $u.Enabled -and $direct.Count -gt 0) {
        Add-Finding $u 'F1' 'High' "Disabled but still in: $($direct -join ', ')" 'Complete leaver: remove memberships'
    }
    # F2
    foreach ($dl in $dlDirect) {
        Add-Finding $u 'F2' 'Medium' "Direct member of $dl (bypasses role model)" 'Remove, or grant via a role group'
    }
    # F3
    foreach ($r in $roles) {
        $roleDept = $c.Roles[$r].Department
        if ($ouDept -and $roleDept -and $roleDept -ne $ouDept) {
            Add-Finding $u 'F3' 'High' "Role $r belongs to $roleDept but user sits in $ouDept" 'Mover leftover: remove old role'
        }
    }
    # F4
    if ($roles.Count -gt 1) {
        Add-Finding $u 'F4' 'Medium' "Holds $($roles.Count) roles: $($roles -join ', ')" 'Confirm with manager; one role per user'
    }
    # F5
    foreach ($s in (Test-LabSoD -SamAccountName $u.SamAccountName)) {
        Add-Finding $u 'F5' 'Critical' "SoD conflict: $($s.ConflictA) + $($s.ConflictB)" 'Remove one side; document exception if approved'
    }
    # F6
    if ($u.Enabled) {
        $staleCut = (Get-Date).AddDays(-$c.StaleDays)
        if ($u.LastLogonDate -and $u.LastLogonDate -lt $staleCut) {
            Add-Finding $u 'F6' 'Medium' "No logon since $($u.LastLogonDate.ToString('yyyy-MM-dd'))" 'Confirm with manager, else disable'
        }
        elseif (-not $u.LastLogonDate -and $u.whenCreated -lt (Get-Date).AddDays(-14)) {
            Add-Finding $u 'F6' 'Low' 'Never logged on, created >14 days ago' 'Confirm the hire actually started'
        }
    }
    # F7
    foreach ($p in ($effective | Where-Object { $privileged -contains $_ })) {
        Add-Finding $u 'F7' 'High' "Member of privileged group $p" 'Use separate adm-* account; justify or remove'
    }
    # F8
    if ($u.PasswordNeverExpires) {
        Add-Finding $u 'F8' 'Medium' 'PasswordNeverExpires on a human account' 'Clear the flag'
    }
}

$entitlements | Export-Csv (Join-Path $outDir 'entitlements.csv') -NoTypeInformation -Encoding UTF8
$findings     | Sort-Object Severity, User | Export-Csv (Join-Path $outDir 'findings.csv') -NoTypeInformation -Encoding UTF8

# ---------- HTML summary for sign-off ----------
$sevOrder = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
$style = @'
<style>
 body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222}
 table{border-collapse:collapse;margin:12px 0;font-size:13px}
 th,td{border:1px solid #ccc;padding:4px 8px;text-align:left}
 th{background:#1f3a5f;color:#fff}
 h1{margin-bottom:0} .meta{color:#666}
</style>
'@
$counts = $findings | Group-Object Severity | Sort-Object { $sevOrder[$_.Name] } |
    Select-Object @{n = 'Severity'; e = { $_.Name } }, Count
$body = @"
<h1>Quarterly Access Review</h1>
<p class='meta'>Domain: $($c.DomainName) &middot; Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') &middot; Users reviewed: $($users.Count) &middot; Findings: $($findings.Count)</p>
<h2>Findings by severity</h2>
$($counts | ConvertTo-Html -Fragment)
<h2>Findings</h2>
$($findings | Sort-Object { $sevOrder[$_.Severity] }, User | ConvertTo-Html -Fragment)
<h2>Entitlements</h2>
$($entitlements | Select-Object User, Name, Enabled, OUDepartment, Roles, DirectGroups | ConvertTo-Html -Fragment)
<h2>Sign-off</h2>
<p>Reviewer: ____________________ &nbsp; Date: ____________ &nbsp; Decision: Approve / Revoke listed findings</p>
"@
ConvertTo-Html -Head $style -Body $body -Title 'Access Review' | Set-Content (Join-Path $outDir 'summary.html') -Encoding UTF8

Write-AuditLog -Event ACCESS_REVIEW -Target $c.DomainName -Action 'Review generated' -Detail "Findings=$($findings.Count); Path=$outDir"
Write-Host "Access review written to $outDir" -ForegroundColor Green
$counts | Format-Table
