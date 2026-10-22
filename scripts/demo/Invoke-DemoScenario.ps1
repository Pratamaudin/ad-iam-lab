<#
.SYNOPSIS
    Reproduce the whole lab story end-to-end, so every screenshot in the README
    can be regenerated on a fresh domain.

    Step 1  Seed 9 employees (4 managers, 5 staff)
    Step 2  JOINER  - bulk onboarding from new-hires.csv (one row is deliberately invalid)
    Step 3  MOVER   - Sari Putri: Sales -> Finance
    Step 4  LEAVER  - Budi Wijaya resigns
    Step 5  DRIFT   - simulate the misconfigurations real admins make "just this once"
    Step 6  REVIEW  - access review catches them
#>
$ErrorActionPreference = 'Stop'
$jml = Join-Path $PSScriptRoot '..\jml'
$gov = Join-Path $PSScriptRoot '..\governance'
$data = Join-Path $PSScriptRoot '..\..\data'
Import-Module (Join-Path $PSScriptRoot '..\common\LabCommon.psm1') -Force

Write-Host "`n=== Step 1: seed users ===" -ForegroundColor Cyan
& "$jml\Invoke-Joiner.ps1" -CsvPath "$data\initial-users.csv" | Format-Table SamAccountName, Role

Write-Host "`n=== Step 2: JOINER (bulk) ===" -ForegroundColor Cyan
# Expect: Siti + Rizky created, Joko REJECTED (HR person requested a Finance role)
# TempPassword is printed so you can test first logon on CL01 (lab only)
& "$jml\Invoke-Joiner.ps1" -CsvPath "$data\new-hires.csv" | Format-Table SamAccountName, Role, TempPassword

Write-Host "`n=== Step 3: MOVER ===" -ForegroundColor Cyan
& "$jml\Invoke-Mover.ps1" -SamAccountName sputri -NewDepartment FIN -NewRole RG-FIN-Staff `
    -NewTitle 'Finance Analyst' -NewManager dpratama -TicketId HR-1007

Write-Host "`n=== Step 4: LEAVER ===" -ForegroundColor Cyan
& "$jml\Invoke-Leaver.ps1" -SamAccountName bwijaya -TicketId HR-1012 -Confirm:$false

Write-Host "`n=== Step 5: DRIFT (simulated bad changes outside the JML process) ===" -ForegroundColor Yellow
# a) Payroll officer given direct write to Finance share "to help month-end close"  -> F2 + F5 (SoD)
Add-ADGroupMember -Identity 'DL-Share-Finance-RW' -Members fhidayat
# b) Sales exec added to HR role "temporarily" and never removed                  -> F3 + F4
Add-ADGroupMember -Identity 'RG-HR-Staff' -Members asetiawan
# c) Helpdesk tech asked for a non-expiring password                              -> F8
Set-ADUser rkusuma -PasswordNeverExpires $true
# d) SysAdmin daily account put straight into Domain Admins                       -> F7
Add-ADGroupMember -Identity 'Domain Admins' -Members asaputra

Write-Host "`n=== Step 6: ACCESS REVIEW ===" -ForegroundColor Cyan
& "$gov\Get-AccessReview.ps1"
