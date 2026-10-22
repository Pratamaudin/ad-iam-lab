# 06 – Access review & findings

`scripts/governance/Get-AccessReview.ps1` is the **detective control** that catches what the
preventive controls (JML scripts) can't: changes made by hand, outside the process.

Output (`C:\IAMLab\reports\access-review-<date>\`):

| File | Audience | Content |
|---|---|---|
| `entitlements.csv` | Auditor | Every user: roles, direct groups, effective DL permissions, last logon |
| `findings.csv` | IAM team | One row per issue with severity and suggested action |
| `summary.html` | Manager | Findings + entitlements + sign-off line |

## Finding catalogue

| ID | Check | Severity | Typical root cause |
|---|---|---|---|
| F1 | Disabled account still in groups | High | Leaver done by hand, half-finished |
| F2 | Direct member of a DL-* group | Medium | "Just add him to the folder" request bypassing roles |
| F3 | Role doesn't match department OU | High | Mover where old role wasn't removed |
| F4 | More than one business role | Medium | Temporary access never revoked |
| F5 | SoD conflict | Critical | Any of the above creating toxic combination |
| F6 | No logon > 90 days, or never logged on | Medium/Low | Orphan account, no-show hire |
| F7 | Member of privileged built-in group | High | Daily account used for admin work |
| F8 | PasswordNeverExpires | Medium | Convenience request |

## Demo result

After `Invoke-DemoScenario.ps1`, step 5 makes four out-of-process changes. The review flags all of them:

| User | Finding | Severity | Remediation |
|---|---|---|---|
| fhidayat | F5 Payroll + Finance RW | Critical | `Remove-ADGroupMember DL-Share-Finance-RW fhidayat` |
| fhidayat | F2 Direct DL membership | Medium | (same fix) |
| asetiawan | F3 RG-HR-Staff while in SLS | High | `Remove-ADGroupMember RG-HR-Staff asetiawan` |
| asetiawan | F4 Two roles | Medium | (same fix) |
| asaputra | F7 Domain Admins | High | Create `adm-asaputra` for admin work, remove daily account from Domain Admins |
| rkusuma | F8 Password never expires | Medium | `Set-ADUser rkusuma -PasswordNeverExpires $false` |

Re-run the review after remediation → findings should drop to 0 (or only F6 in a fresh lab, since
demo users never logged on). Screenshot both the before and after.

*(Replace this table with your actual `findings.csv` output.)*
