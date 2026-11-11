# LicenseComplianceAlertStatusChanged Event Call Chains

## Overview

This document maps the call chains for `LicenseComplianceAlertStatusChanged` Hydro event publishing in OLC.

## Call Chains

### remediation: c.publisher.PublishAlertStatusChanged

```
c.publisher.PublishAlertStatusChanged
│
├─ Called by: remediation.closeSideEffectAlert
│  │
│  ├─ Called by: remediation.CheckAndCloseAffectedAlertsForLicenses
│  │  │
│  │  ├─ Called by: remediation.AddLicensesToPolicyForAlert (async goroutine)
│  │  │  └─ Called by: twirp.Server.AddLicensesForAlert (Twirp endpoint)
│  │  │
│  │  ├─ Called by: twirp.Server.AddLicensesToOrganizationPolicy (async goroutine)
│  │  │
│  │  └─ Called by: twirp.Server.AddLicensesToEnterprisePolicy (async goroutine)
│  │
│  └─ Called by: remediation.CheckAndCloseAffectedAlertsForPackages
│     │
│     └─ Called by: remediation.AddPackagePolicyForAlert (async goroutine)
│        └─ Called by: twirp.Server.CreatePackageException (Twirp endpoint)
│
└─ Called by: remediation.closeRemediatedAlert
   │
   ├─ Called by: remediation.AddLicensesToPolicyForAlert
   │  └─ Called by: twirp.Server.AddLicensesForAlert (Twirp endpoint)
   │
   └─ Called by: remediation.AddPackagePolicyForAlert
      └─ Called by: twirp.Server.CreatePackageException (Twirp endpoint)
```

### repocheck: c.publisher.PublishAlertStatusChanged

```
c.publisher.PublishAlertStatusChanged
│
└─ Called by: repocheck.Checker.closeOutdatedAlerts
   │
   └─ Called by: repocheck.Checker.UpdateAlerts
      │
      ├─ Called by: repocheck.Checker.checkWithPolicy
      │  └─ Called by: repocheck.Checker.ExecuteJob
      │
      └─ Called by: repocheck.Checker.Check
```