@{
    # ---------------------------------------------------------------
    # Lab-wide settings. Edit here, not inside the scripts.
    # ---------------------------------------------------------------
    DomainName    = 'corp.nusantara.lab'
    NetBIOSName   = 'NUSANTARA'
    DomainDN      = 'DC=corp,DC=nusantara,DC=lab'
    RootOU        = 'Corp'
    AuditLogPath  = 'C:\IAMLab\logs\audit-log.csv'
    SnapshotPath  = 'C:\IAMLab\logs\leaver-snapshots'
    ReportPath    = 'C:\IAMLab\reports'
    ShareRoot     = 'C:\Shares'
    StaleDays     = 90

    # Department code -> department name (code is used in OU and group names)
    Departments = @{
        IT  = 'Information Technology'
        FIN = 'Finance'
        HR  = 'Human Resources'
        SLS = 'Sales'
    }

    # ---------------------------------------------------------------
    # RBAC: business role (Global group, RG-) -> permissions (Domain Local, DL-)
    # Model: AGDLP  (Account -> Global role group -> Domain Local resource group -> Permission)
    # ---------------------------------------------------------------
    Roles = @{
        'RG-IT-Helpdesk'  = @{ Department = 'IT';  Description = 'Helpdesk: password reset/unlock, read-only shares'; Resources = @('DL-Share-Public-RO', 'DL-Share-IT-RW') }
        'RG-IT-SysAdmin'  = @{ Department = 'IT';  Description = 'System administrators';                      Resources = @('DL-Share-Public-RO', 'DL-Share-IT-RW') }
        'RG-FIN-Staff'    = @{ Department = 'FIN'; Description = 'Finance staff';                              Resources = @('DL-Share-Public-RO', 'DL-Share-Finance-RO') }
        'RG-FIN-Manager'  = @{ Department = 'FIN'; Description = 'Finance manager (approver)';                  Resources = @('DL-Share-Public-RO', 'DL-Share-Finance-RW') }
        'RG-HR-Staff'     = @{ Department = 'HR';  Description = 'HR staff, payroll entry';                    Resources = @('DL-Share-Public-RO', 'DL-Share-HR-RW', 'DL-App-Payroll-User') }
        'RG-HR-Manager'   = @{ Department = 'HR';  Description = 'HR manager';                                 Resources = @('DL-Share-Public-RO', 'DL-Share-HR-RW', 'DL-App-Payroll-User') }
        'RG-SLS-Staff'    = @{ Department = 'SLS'; Description = 'Sales staff';                                Resources = @('DL-Share-Public-RO', 'DL-Share-Sales-RW', 'DL-App-CRM-User') }
        'RG-SLS-Manager'  = @{ Department = 'SLS'; Description = 'Sales manager';                              Resources = @('DL-Share-Public-RO', 'DL-Share-Sales-RW', 'DL-App-CRM-User') }
    }

    # Resource groups (Domain Local). Shares get NTFS permissions from these.
    Resources = @{
        'DL-Share-Public-RO'   = @{ Share = 'Public';  Right = 'ReadAndExecute'; Description = 'Read company-wide public share' }
        'DL-Share-IT-RW'       = @{ Share = 'IT';      Right = 'Modify';         Description = 'Modify IT share' }
        'DL-Share-Finance-RO'  = @{ Share = 'Finance'; Right = 'ReadAndExecute'; Description = 'Read Finance share' }
        'DL-Share-Finance-RW'  = @{ Share = 'Finance'; Right = 'Modify';         Description = 'Modify Finance share' }
        'DL-Share-HR-RW'       = @{ Share = 'HR';      Right = 'Modify';         Description = 'Modify HR share' }
        'DL-Share-Sales-RW'    = @{ Share = 'Sales';   Right = 'Modify';         Description = 'Modify Sales share' }
        'DL-App-Payroll-User'  = @{ Share = $null;     Right = $null;            Description = 'Payroll application user (simulated app)' }
        'DL-App-CRM-User'      = @{ Share = $null;     Right = $null;            Description = 'CRM application user (simulated app)' }
    }

    # ---------------------------------------------------------------
    # Segregation of Duties: nobody should hold both groups of a pair
    # (e.g. someone who enters payroll should not also approve Finance)
    # ---------------------------------------------------------------
    SoDConflicts = @(
        @('DL-App-Payroll-User', 'DL-Share-Finance-RW'),
        @('RG-IT-SysAdmin',      'RG-FIN-Manager')
    )
}
