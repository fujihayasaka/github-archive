# LicenseComplianceAlertStatusChanged Event Call Chains

## Overview

This document maps the call chains for `LicenseComplianceAlertStatusChanged` Hydro event publishing in OLC.

## Call Chains

### remediation: PublishAlertStatusChanged

```
PublishAlertStatusChanged
│
├─ Called by: remediation.closeSideEffectAlert
│  │
│  ├─ Called by: remediation.checkAndCloseAffectedAlertsForPolicyChange
│  │  │
│  │  ├─ Called by: remediation.CheckAndCloseAffectedAlertsForLicenses
│  │  │  │
│  │  │  ├─ Called by: remediation.updateAlertForPolicyChange (async goroutine)
│  │  │  │  └─ Called by: remediation.AddLicensesToPolicyForAlert
│  │  │  │     └─ Called by: twirp.Server.AddLicensesForAlert (Twirp endpoint)
│  │  │  │
│  │  │  ├─ Called by: remediation.AddLicensesToOrganizationPolicy (async goroutine)
│  │  │  │  └─ Called by: twirp.Server.AddLicensesToOrganizationPolicy (Twirp endpoint)
│  │  │  │
│  │  │  └─ Called by: remediation.AddLicensesToEnterprisePolicy (async goroutine)
│  │  │     └─ Called by: twirp.Server.AddLicensesToEnterprisePolicy (Twirp endpoint)
│  │  │
│  │  └─ Called by: remediation.CheckAndCloseAffectedAlertsForPackages
│  │     │
│  │     └─ Called by: remediation.updateAlertForPolicyChange (async goroutine)
│  │        └─ Called by: remediation.AddPackagePolicyForAlert
│  │           └─ Called by: twirp.Server.CreatePackageException (Twirp endpoint)
│  │
│  └─ (Side-effect closures for alerts affected by policy changes)
│
└─ Called by: remediation.updateAlertForPolicyChange (direct alert closure)
   │
   ├─ Called by: remediation.AddLicensesToPolicyForAlert
   │  └─ Called by: twirp.Server.AddLicensesForAlert (Twirp endpoint)
   │
   └─ Called by: remediation.AddPackagePolicyForAlert
      └─ Called by: twirp.Server.CreatePackageException (Twirp endpoint)
```

### repocheck: PublishAlertStatusChanged

```
PublishAlertStatusChanged
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

### remediation/requests: PublishAlertStatusChanged

```
PublishAlertStatusChanged
│
├─ Called by: remediation.RequestAlertClosure
│  └─ Called by: twirp.Server.RequestAlertClosure (Twirp endpoint)
│
├─ Called by: remediation.DenyClosureRequest
│  └─ Called by: twirp.Server.DenyClosureRequest (Twirp endpoint)
│
└─ Called by: remediation.ExpireClosureRequest
   └─ Called by: twirp.Server.ExpireClosureRequest (Twirp endpoint)
```

### remediation/outdated: PublishAlertStatusChanged

```
PublishAlertStatusChanged
│
└─ Called by: remediation.CloseOutdatedAlerts
   └─ Called by: repocheck (when alerts are no longer in manifests)
```