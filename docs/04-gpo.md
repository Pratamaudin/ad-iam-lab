# 04 – Group Policy

## Scripted (04-New-GPOs.ps1)

| Policy | Linked to | Settings | Control objective |
|---|---|---|---|
| Default Domain Policy | Domain | Min length 12, complexity, history 24, max age 90 d, lockout 5 attempts / 15 min | Password strength, brute-force protection |
| PSO-Admins (fine-grained) | RG-IT-SysAdmin | Min length 16, max age 60 d, lockout 3 attempts / 30 min | Stronger control for privileged role |
| GPO-U-All-ScreenLock | Corp\Users | Screen saver on, password protected, 600 s | Unattended session protection |
| GPO-U-SLS-NoControlPanel | Corp\Users\SLS | `NoControlPanel = 1` | Prevent config changes by non-IT users |
| GPO-C-Workstations-USBBlock | Corp\Workstations | `RemovableStorageDevices\Deny_All = 1` | Data-loss prevention |

HTML reports of each GPO are exported to `C:\IAMLab\reports\gpo\` — copy them into `docs/gpo-reports/`.

## Manual step A — drive mapping by role (Group Policy Preferences)

GPP items cannot be created with the GroupPolicy cmdlets, so this one is done in GPMC:

1. Create `GPO-U-All-DriveMaps`, link to `Corp\Users`.
2. *User Configuration → Preferences → Windows Settings → Drive Maps → New → Mapped Drive*
3. Add one item per department share, each with **Item-level targeting → Security Group**:

| Drive | Path | Targeting (security group) |
|---|---|---|
| P: | `\\DC01\Public` | DL-Share-Public-RO |
| F: | `\\DC01\Finance` | DL-Share-Finance-RO **or** DL-Share-Finance-RW |
| H: | `\\DC01\HR` | DL-Share-HR-RW |
| S: | `\\DC01\Sales` | DL-Share-Sales-RW |
| I: | `\\DC01\IT` | DL-Share-IT-RW |

Result: a mover automatically gets the new drive and loses the old one at next logon — the drive
follows the role, nobody edits a logon script.

## Manual step B — audit policy (feeds a SIEM)

In GPMC edit **Default Domain Controllers Policy** →
*Computer Configuration → Policies → Windows Settings → Security Settings → Advanced Audit Policy Configuration → Account Management*:

- Audit User Account Management: **Success, Failure**
- Audit Security Group Management: **Success, Failure**

Plus *Account Logon → Audit Credential Validation* and *Logon/Logoff → Audit Account Lockout*.

Verify on DC01: `auditpol /get /category:"Account Management"`

Every JML action now leaves a Windows Security event:

| Event ID | Meaning | Produced by |
|---|---|---|
| 4720 | User account created | Joiner |
| 4738 | User account changed | Mover, Leaver |
| 4728 / 4729 | Member added / removed — global group (RG-*) | Joiner, Mover, Leaver |
| 4732 / 4733 | Member added / removed — domain local group (DL-*) | Drift step / Leaver |
| 4725 | User account disabled | Leaver |
| 4724 | Password reset by another account | Leaver, Helpdesk |
| 4726 | User account deleted | Leaver purge |
| 4740 / 4767 | Account locked out / unlocked | Lockout policy, Helpdesk |

**SOC angle:** a 4728/4732 event with no matching ticket in `audit-log.csv` = change made outside
the JML process → exactly what the drift step simulates. This is the next extension: ship these
events to Wazuh or Splunk and alert on them.

## Verifying on CL01

```powershell
gpupdate /force
gpresult /r /scope user
gpresult /h C:\Temp\gpresult.html
```
