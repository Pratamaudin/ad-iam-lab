# Active Directory IAM Lab — RBAC, GPO & Joiner-Mover-Leaver

A small, reproducible Identity & Access Management lab on Windows Server 2022 Active Directory.
It models a fictional 4-department company (**Nusantara Corp**, `corp.nusantara.lab`) and automates
the full identity lifecycle with PowerShell, then audits the result with an access review.

> **Goal:** show IAM *concepts* working end-to-end — role-based access, least privilege,
> identity lifecycle, and access governance — not just "I know AD exists".

---

## What this lab demonstrates

| IAM concept | How it is implemented here |
|---|---|
| **RBAC** | 8 business roles (`RG-*`, Global groups) nested into 8 permission groups (`DL-*`, Domain Local) — the **AGDLP** model. Users only ever get a role; never direct permissions. |
| **Least privilege** | Helpdesk can reset/unlock passwords **only** in `Corp\Users` via OU delegation — no Domain Admin. Admins get a stricter fine-grained password policy. |
| **Identity lifecycle (JML)** | `Invoke-Joiner` / `Invoke-Mover` / `Invoke-Leaver` scripts with validation, naming standard, privilege-creep prevention, disable-then-delete, and access snapshots. |
| **Access governance** | `Get-AccessReview` produces an entitlement report + 8 automated findings (SoD conflicts, mover leftovers, RBAC bypass, stale & privileged accounts) and a sign-off page. |
| **Segregation of Duties** | Conflicting group pairs declared in config, checked on every joiner/mover and in every review. |
| **Policy enforcement (GPO)** | Password & lockout policy, screen lock, Control Panel restriction for Sales, USB storage block on workstations. |
| **Auditability** | Every change written to one CSV audit log with ticket ID; AD audit policy produces Windows Security events (4720, 4728, 4725…) for a SIEM. |

## Architecture

```
 VirtualBox host-only network 192.168.56.0/24
 ┌───────────────────────────┐        ┌──────────────────────────┐
 │ DC01  Windows Server 2022 │◄──────►│ CL01  Windows 11 Ent     │
 │ AD DS, DNS, GPMC, shares  │  LDAP  │ domain-joined client     │
 │ 192.168.56.10             │  SMB   │ (tests GPO + share access)│
 └───────────────────────────┘        └──────────────────────────┘

 corp.nusantara.lab
 └── Corp
     ├── Users ── IT │ FIN │ HR │ SLS
     ├── Groups ── Roles (RG-*) │ Resources (DL-*)
     ├── Admins │ Service Accounts │ Workstations
     └── Disabled Users
```

```
 User ──► RG-FIN-Staff ──► DL-Share-Finance-RO ──► NTFS Read on \\DC01\Finance
          (business role)   (permission)            (resource)
```

## Repository layout

```
scripts/
  config/LabConfig.psd1          # single source of truth: departments, roles, resources, SoD rules
  common/LabCommon.psm1          # naming standard, audit log, SoD check
  setup/00-Install-ADDS.ps1      # promote DC
  setup/01-New-OUStructure.ps1   # OU tree
  setup/02-New-RBACGroups.ps1    # RG/DL groups, AGDLP nesting, shares + NTFS
  setup/03-Set-HelpdeskDelegation.ps1
  setup/04-New-GPOs.ps1
  jml/Invoke-Joiner.ps1          # single or bulk (CSV) onboarding
  jml/Invoke-Mover.ps1           # remove old role -> move -> add new role
  jml/Invoke-Leaver.ps1          # snapshot -> disable -> strip -> park -> purge
  governance/Get-AccessReview.ps1
  demo/Invoke-DemoScenario.ps1   # runs the whole story end-to-end
data/                            # seed employees + HR new-hire feed
docs/                            # design, RBAC matrix, GPO, runbooks, findings
```

## Quick start

1. Build the two VMs — [docs/01-lab-setup.md](docs/01-lab-setup.md)
2. On DC01 (elevated PowerShell):
   ```powershell
   .\scripts\setup\00-Install-ADDS.ps1        # reboots
   .\scripts\setup\01-New-OUStructure.ps1
   .\scripts\setup\02-New-RBACGroups.ps1
   .\scripts\setup\03-Set-HelpdeskDelegation.ps1
   .\scripts\setup\04-New-GPOs.ps1
   .\scripts\demo\Invoke-DemoScenario.ps1
   ```
3. Join CL01 to the domain, move it to `Corp\Workstations`, log in as the demo users and verify.

## The story the demo tells

| Step | Event | Ticket | What happens | Control shown |
|---|---|---|---|---|
| 1 | Seed | — | 9 employees across 4 departments | Naming standard, one role per user |
| 2 | **Joiner** | HR-1001/2/3 | Siti & Rizky onboarded; **Joko rejected** (HR recruiter requested a Finance role) | Request validation |
| 3 | **Mover** | HR-1007 | Sari moves Sales → Finance; Sales role **removed** before Finance role added | Privilege-creep prevention |
| 4 | **Leaver** | HR-1012 | Budi disabled, password scrambled, groups snapshotted & stripped, parked | Disable-then-delete, recoverability |
| 5 | Drift | — | 4 "just this once" changes made outside the process | — |
| 6 | **Access review** | — | All 4 drifts caught as findings | Governance / detective control |

Expected review findings:

| User | Finding | Severity |
|---|---|---|
| fhidayat | F5 SoD: payroll entry + Finance write | Critical |
| fhidayat | F2 Direct member of DL-Share-Finance-RW | Medium |
| asetiawan | F3 HR role while in Sales OU | High |
| asetiawan | F4 Two business roles | Medium |
| asaputra | F7 Daily account in Domain Admins | High |
| rkusuma | F8 PasswordNeverExpires | Medium |

## Screenshots

See [docs/screenshots](docs/screenshots/) — OU tree, AGDLP nesting, GPO results on the client,
helpdesk delegation allowed/denied, JML console output, audit log, access-review page.

## Documentation

- [01 – Lab setup](docs/01-lab-setup.md)
- [02 – AD design & naming standard](docs/02-ad-design.md)
- [03 – RBAC matrix](docs/03-rbac-matrix.md)
- [04 – Group Policy](docs/04-gpo.md)
- [05 – JML runbook](docs/05-jml-runbook.md)
- [06 – Access review & findings](docs/06-access-review.md)

## What I learned / next steps

- Why groups, not users, should be on ACLs — and why AGDLP keeps the model readable at scale.
- Mover is the hardest lifecycle event: adding access is easy, *removing* it is what gets forgotten.
- Disable-then-delete plus a membership snapshot makes offboarding reversible and auditable.
- Next: forward AD security events to Wazuh/Splunk and alert on group changes made outside a ticket;
  tiered admin accounts (`adm-*`); LAPS for local admin passwords; Entra ID Connect sync to the cloud.

---
*Lab environment only. All names and data are fictional.*
