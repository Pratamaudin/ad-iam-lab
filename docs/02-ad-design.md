# 02 – AD design & naming standard

## OU structure

```
corp.nusantara.lab
└── Corp                         ← all company objects; GPOs are never linked to the built-in Users/Computers containers
    ├── Users
    │   ├── IT                   ← per-department OU = GPO targeting + delegation boundary
    │   ├── FIN
    │   ├── HR
    │   └── SLS
    ├── Groups
    │   ├── Roles                ← RG-*  Global security groups  (who you are)
    │   └── Resources            ← DL-*  Domain Local groups     (what you can touch)
    ├── Admins                   ← privileged accounts, outside helpdesk delegation scope
    ├── Service Accounts
    ├── Workstations             ← computer GPOs (USB block)
    └── Disabled Users           ← leavers parked here; purged after 30 days
```

**Design decisions**

- **OU = administration & policy boundary, groups = access.** OUs decide which GPO applies and who may
  manage the object; they never grant access to data.
- **Admins are outside `Corp\Users`**, so the helpdesk delegation on `Corp\Users` cannot reach them.
- **Disabled Users** is a separate OU so leavers stop receiving user GPOs and are easy to review and purge.
- All OUs are `ProtectedFromAccidentalDeletion`.

## Naming standard

| Object | Pattern | Example |
|---|---|---|
| User logon (sAMAccountName) | first initial + last name, lowercase, number suffix on collision | `srahma`, `srahma2` |
| UPN | `<sam>@corp.nusantara.lab` | `srahma@corp.nusantara.lab` |
| Admin account (planned) | `adm-<sam>` | `adm-asaputra` |
| Role group | `RG-<DEPT>-<Role>` | `RG-FIN-Staff` |
| Resource group | `DL-<Type>-<Resource>-<Right>` | `DL-Share-Finance-RO` |
| User GPO | `GPO-U-<Scope>-<Purpose>` | `GPO-U-SLS-NoControlPanel` |
| Computer GPO | `GPO-C-<Scope>-<Purpose>` | `GPO-C-Workstations-USBBlock` |

## Why AGDLP

**A**ccounts → **G**lobal groups → **D**omain **L**ocal groups → **P**ermissions.

- Global groups describe *people* by business role (HR thinks in roles).
- Domain Local groups describe *a permission on a resource* (data owners think in resources).
- Only DL groups appear on ACLs. Changing what a role can do = change one nesting, not 50 ACLs.
- An access review can answer both "what can Siti do?" (expand her roles) and
  "who can write to Finance?" (expand one DL group).

Anti-patterns this design avoids: users directly on NTFS ACLs, one group per person,
"Finance-All" groups that mix roles and permissions.
