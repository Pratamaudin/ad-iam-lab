# 03 – RBAC matrix

Source of truth: [`scripts/config/LabConfig.psd1`](../scripts/config/LabConfig.psd1).
Changing a role's access = edit the config and re-run `02-New-RBACGroups.ps1`.

## Role → permission

| Role (RG-*) | Public RO | IT RW | Finance RO | Finance RW | HR RW | Sales RW | Payroll app | CRM app | AD rights |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---|
| RG-IT-Helpdesk | ✔ | ✔ | | | | | | | Reset password, unlock (Corp\Users only) |
| RG-IT-SysAdmin | ✔ | ✔ | | | | | | | Stricter password policy (PSO-Admins) |
| RG-FIN-Staff | ✔ | | ✔ | | | | | | |
| RG-FIN-Manager | ✔ | | | ✔ | | | | | |
| RG-HR-Staff | ✔ | | | | ✔ | | ✔ | | |
| RG-HR-Manager | ✔ | | | | ✔ | | ✔ | | |
| RG-SLS-Staff | ✔ | | | | | ✔ | | ✔ | |
| RG-SLS-Manager | ✔ | | | | | ✔ | | ✔ | |

## Resource groups → actual permission

| DL group | Resource | NTFS right |
|---|---|---|
| DL-Share-Public-RO | `\\DC01\Public` | Read & Execute |
| DL-Share-IT-RW | `\\DC01\IT` | Modify |
| DL-Share-Finance-RO | `\\DC01\Finance` | Read & Execute |
| DL-Share-Finance-RW | `\\DC01\Finance` | Modify |
| DL-Share-HR-RW | `\\DC01\HR` | Modify |
| DL-Share-Sales-RW | `\\DC01\Sales` | Modify |
| DL-App-Payroll-User | Payroll app (simulated) | app login |
| DL-App-CRM-User | CRM app (simulated) | app login |

Share-level permission is `Authenticated Users: Change` everywhere; **NTFS is the real control**.
Inheritance from the parent folder is removed so the built-in `Users` group gets nothing.

## Segregation of Duties rules

| Rule | Conflict | Why |
|---|---|---|
| SoD-1 | DL-App-Payroll-User + DL-Share-Finance-RW | The person who enters payroll must not also approve/post finance records |
| SoD-2 | RG-IT-SysAdmin + RG-FIN-Manager | An admin who can change any ACL must not also own financial approval |

Checked by `Test-LabSoD` (resolves nested groups via `LDAP_MATCHING_RULE_IN_CHAIN`)
on every joiner and mover, and on every access review.
