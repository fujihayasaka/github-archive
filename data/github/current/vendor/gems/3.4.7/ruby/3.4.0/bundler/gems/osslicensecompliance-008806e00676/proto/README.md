_Version: 0.22.0_

# API Reference

# Table of Contents


<details><summary>Services (1)</summary>

  - [LicenseCompliance](#licensecompliance)


</details>


<details><summary>Messages (40)</summary>

  - [AddLicensesForAlertRequest](#addlicensesforalertrequest)
  - [AddLicensesForAlertResponse](#addlicensesforalertresponse)
  - [AddLicensesToEnterprisePolicyRequest](#addlicensestoenterprisepolicyrequest)
  - [AddLicensesToEnterprisePolicyResponse](#addlicensestoenterprisepolicyresponse)
  - [AddLicensesToOrganizationPolicyRequest](#addlicensestoorganizationpolicyrequest)
  - [AddLicensesToOrganizationPolicyResponse](#addlicensestoorganizationpolicyresponse)
  - [CheckRepositoryRequest](#checkrepositoryrequest)
  - [CheckRepositoryResponse](#checkrepositoryresponse)
  - [CreateEnterprisePolicyRequest](#createenterprisepolicyrequest)
  - [CreateEnterprisePolicyResponse](#createenterprisepolicyresponse)
  - [CreateOrganizationPolicyRequest](#createorganizationpolicyrequest)
  - [CreateOrganizationPolicyResponse](#createorganizationpolicyresponse)
  - [CreatePackageExceptionRequest](#createpackageexceptionrequest)
  - [CreatePackageExceptionResponse](#createpackageexceptionresponse)
  - [CreateRepositoryPolicyRequest](#createrepositorypolicyrequest)
  - [CreateRepositoryPolicyResponse](#createrepositorypolicyresponse)
  - [DeleteLicensesFromEnterprisePolicyRequest](#deletelicensesfromenterprisepolicyrequest)
  - [DeleteLicensesFromEnterprisePolicyResponse](#deletelicensesfromenterprisepolicyresponse)
  - [DeleteLicensesFromRepositoryPolicyRequest](#deletelicensesfromrepositorypolicyrequest)
  - [DeleteLicensesFromRepositoryPolicyResponse](#deletelicensesfromrepositorypolicyresponse)
  - [DeletePackageExceptionsFromEnterprisePolicyRequest](#deletepackageexceptionsfromenterprisepolicyrequest)
  - [DeletePackageExceptionsFromEnterprisePolicyResponse](#deletepackageexceptionsfromenterprisepolicyresponse)
  - [DeletePackageExceptionsFromRepositoryPolicyRequest](#deletepackageexceptionsfromrepositorypolicyrequest)
  - [DeletePackageExceptionsFromRepositoryPolicyResponse](#deletepackageexceptionsfromrepositorypolicyresponse)
  - [DenyAlertDismissalRequest](#denyalertdismissalrequest)
  - [DenyAlertDismissalResponse](#denyalertdismissalresponse)
  - [GetAlertRequest](#getalertrequest)
  - [GetAlertResponse](#getalertresponse)
  - [GetCombinedRepositoryPolicyRequest](#getcombinedrepositorypolicyrequest)
  - [GetCombinedRepositoryPolicyResponse](#getcombinedrepositorypolicyresponse)
  - [GetEnterprisePolicyRequest](#getenterprisepolicyrequest)
  - [GetEnterprisePolicyResponse](#getenterprisepolicyresponse)
  - [GetOrganizationPolicyRequest](#getorganizationpolicyrequest)
  - [GetOrganizationPolicyResponse](#getorganizationpolicyresponse)
  - [GetRepositoryPolicyRequest](#getrepositorypolicyrequest)
  - [GetRepositoryPolicyResponse](#getrepositorypolicyresponse)
  - [GetReviewableAlertsRequest](#getreviewablealertsrequest)
  - [GetReviewableAlertsResponse](#getreviewablealertsresponse)
  - [RequestAlertDismissalRequest](#requestalertdismissalrequest)
  - [RequestAlertDismissalResponse](#requestalertdismissalresponse)


</details>





<details><summary>Messages (15)</summary>

  - [Alert](#alert)
  - [AlertEvent](#alertevent)
  - [CombinedLicense](#combinedlicense)
  - [CombinedPackage](#combinedpackage)
  - [CombinedRepositoryPolicy](#combinedrepositorypolicy)
  - [DistributionPolicy](#distributionpolicy)
  - [EnterprisePolicy](#enterprisepolicy)
  - [LicenseEntry](#licenseentry)
  - [OrganizationPolicy](#organizationpolicy)
  - [Package](#package)
  - [PackageFailure](#packagefailure)
  - [PackagePolicy](#packagepolicy)
  - [PolicyLicenses](#policylicenses)
  - [RepositoryPolicy](#repositorypolicy)
  - [RepositoryResults](#repositoryresults)


</details>


<details><summary>Enums (9)</summary>

  - [AlertEventType](#alerteventtype)
  - [AlertResolution](#alertresolution)
  - [AlertStatus](#alertstatus)
  - [FailureLevel](#failurelevel)
  - [FailureReason](#failurereason)
  - [PackageAction](#packageaction)
  - [PackageManager](#packagemanager)
  - [PolicyLevel](#policylevel)
  - [RepositoryCheckStatus](#repositorycheckstatus)


</details>



<details><summary>Scalar Value Types (15)</summary>

  - [double](#double)
  - [float](#float)
  - [int32](#int32)
  - [int64](#int64)
  - [uint32](#uint32)
  - [uint64](#uint64)
  - [sint32](#sint32)
  - [sint64](#sint64)
  - [fixed32](#fixed32)
  - [fixed64](#fixed64)
  - [sfixed32](#sfixed32)
  - [sfixed64](#sfixed64)
  - [bool](#bool)
  - [string](#string)
  - [bytes](#bytes)


</details>



# LicenseCompliance



## CreateOrganizationPolicy

> **rpc** CreateOrganizationPolicy([CreateOrganizationPolicyRequest](#createorganizationpolicyrequest))
    [CreateOrganizationPolicyResponse](#createorganizationpolicyresponse)


## GetOrganizationPolicy

> **rpc** GetOrganizationPolicy([GetOrganizationPolicyRequest](#getorganizationpolicyrequest))
    [GetOrganizationPolicyResponse](#getorganizationpolicyresponse)


## AddLicensesToOrganizationPolicy

> **rpc** AddLicensesToOrganizationPolicy([AddLicensesToOrganizationPolicyRequest](#addlicensestoorganizationpolicyrequest))
    [AddLicensesToOrganizationPolicyResponse](#addlicensestoorganizationpolicyresponse)


## CreateEnterprisePolicy

> **rpc** CreateEnterprisePolicy([CreateEnterprisePolicyRequest](#createenterprisepolicyrequest))
    [CreateEnterprisePolicyResponse](#createenterprisepolicyresponse)


## GetEnterprisePolicy

> **rpc** GetEnterprisePolicy([GetEnterprisePolicyRequest](#getenterprisepolicyrequest))
    [GetEnterprisePolicyResponse](#getenterprisepolicyresponse)


## DeletePackageExceptionsFromEnterprisePolicy

> **rpc** DeletePackageExceptionsFromEnterprisePolicy([DeletePackageExceptionsFromEnterprisePolicyRequest](#deletepackageexceptionsfromenterprisepolicyrequest))
    [DeletePackageExceptionsFromEnterprisePolicyResponse](#deletepackageexceptionsfromenterprisepolicyresponse)


## AddLicensesToEnterprisePolicy

> **rpc** AddLicensesToEnterprisePolicy([AddLicensesToEnterprisePolicyRequest](#addlicensestoenterprisepolicyrequest))
    [AddLicensesToEnterprisePolicyResponse](#addlicensestoenterprisepolicyresponse)


## DeleteLicensesFromEnterprisePolicy

> **rpc** DeleteLicensesFromEnterprisePolicy([DeleteLicensesFromEnterprisePolicyRequest](#deletelicensesfromenterprisepolicyrequest))
    [DeleteLicensesFromEnterprisePolicyResponse](#deletelicensesfromenterprisepolicyresponse)


## CreateRepositoryPolicy

> **rpc** CreateRepositoryPolicy([CreateRepositoryPolicyRequest](#createrepositorypolicyrequest))
    [CreateRepositoryPolicyResponse](#createrepositorypolicyresponse)


## GetRepositoryPolicy

> **rpc** GetRepositoryPolicy([GetRepositoryPolicyRequest](#getrepositorypolicyrequest))
    [GetRepositoryPolicyResponse](#getrepositorypolicyresponse)


## GetCombinedRepositoryPolicy

> **rpc** GetCombinedRepositoryPolicy([GetCombinedRepositoryPolicyRequest](#getcombinedrepositorypolicyrequest))
    [GetCombinedRepositoryPolicyResponse](#getcombinedrepositorypolicyresponse)


## DeleteLicensesFromRepositoryPolicy

> **rpc** DeleteLicensesFromRepositoryPolicy([DeleteLicensesFromRepositoryPolicyRequest](#deletelicensesfromrepositorypolicyrequest))
    [DeleteLicensesFromRepositoryPolicyResponse](#deletelicensesfromrepositorypolicyresponse)


## DeletePackageExceptionsFromRepositoryPolicy

> **rpc** DeletePackageExceptionsFromRepositoryPolicy([DeletePackageExceptionsFromRepositoryPolicyRequest](#deletepackageexceptionsfromrepositorypolicyrequest))
    [DeletePackageExceptionsFromRepositoryPolicyResponse](#deletepackageexceptionsfromrepositorypolicyresponse)


## CheckRepository

> **rpc** CheckRepository([CheckRepositoryRequest](#checkrepositoryrequest))
    [CheckRepositoryResponse](#checkrepositoryresponse)


## GetAlert

> **rpc** GetAlert([GetAlertRequest](#getalertrequest))
    [GetAlertResponse](#getalertresponse)


## CreatePackageException

> **rpc** CreatePackageException([CreatePackageExceptionRequest](#createpackageexceptionrequest))
    [CreatePackageExceptionResponse](#createpackageexceptionresponse)


## AddLicensesForAlert

> **rpc** AddLicensesForAlert([AddLicensesForAlertRequest](#addlicensesforalertrequest))
    [AddLicensesForAlertResponse](#addlicensesforalertresponse)


## RequestAlertDismissal

> **rpc** RequestAlertDismissal([RequestAlertDismissalRequest](#requestalertdismissalrequest))
    [RequestAlertDismissalResponse](#requestalertdismissalresponse)


## DenyAlertDismissal

> **rpc** DenyAlertDismissal([DenyAlertDismissalRequest](#denyalertdismissalrequest))
    [DenyAlertDismissalResponse](#denyalertdismissalresponse)


## GetReviewableAlerts

> **rpc** GetReviewableAlerts([GetReviewableAlertsRequest](#getreviewablealertsrequest))
    [GetReviewableAlertsResponse](#getreviewablealertsresponse)


 <!-- end methods -->
 <!-- end services -->

# Messages


## AddLicensesForAlertRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| alert_number | [ uint32](#uint32) | none |
| user_id | [ uint64](#uint64) | none |
| policy_level | [ PolicyLevel](#policylevel) | none |
| contexts | [repeated string](#string) | none |
| organization_id | [ uint64](#uint64) | none |
| enterprise_id | [ uint64](#uint64) | none |
| comment | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AddLicensesForAlertResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
| added_licenses | [repeated string](#string) | none |
| policy_level | [ PolicyLevel](#policylevel) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AddLicensesToEnterprisePolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
| spdx_ids | [repeated string](#string) | none |
| context | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AddLicensesToEnterprisePolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ EnterprisePolicy](#enterprisepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AddLicensesToOrganizationPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| organization_id | [ uint64](#uint64) | none |
| spdx_ids | [repeated string](#string) | none |
| context | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AddLicensesToOrganizationPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ OrganizationPolicy](#organizationpolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CheckRepositoryRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
| organization_id | [ uint64](#uint64) | none |
| repository_id | [ uint64](#uint64) | none |
| commit_sha | [ string](#string) | none |
| base_sha | [ string](#string) | none |
| context | [ string](#string) | none |
| pull_request_id | [ uint64](#uint64) | none |
| pull_request_number | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CheckRepositoryResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| status | [ RepositoryCheckStatus](#repositorycheckstatus) | none |
| message | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateEnterprisePolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
| custom_remediation_guidance | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateEnterprisePolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ EnterprisePolicy](#enterprisepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateOrganizationPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| organization_id | [ uint64](#uint64) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
| custom_remediation_guidance | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateOrganizationPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ OrganizationPolicy](#organizationpolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreatePackageExceptionRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| organization_id | [ uint64](#uint64) | none |
| enterprise_id | [ uint64](#uint64) | none |
| user_id | [ uint64](#uint64) | none |
| alert_number | [ uint32](#uint32) | none |
| policy_level | [ PolicyLevel](#policylevel) | none |
| contexts | [repeated string](#string) | none |
| comment | [ string](#string) | none |
| action | [ PackageAction](#packageaction) | none |
| pattern | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreatePackageExceptionResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateRepositoryPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CreateRepositoryPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ RepositoryPolicy](#repositorypolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteLicensesFromEnterprisePolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | The enterprise ID to update policy for. |
| spdx_ids | [repeated string](#string) | The SPDX license IDs to delete from the specified context. |
| context | [ string](#string) | The context from which to remove the licenses. |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteLicensesFromEnterprisePolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ EnterprisePolicy](#enterprisepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteLicensesFromRepositoryPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | The repository ID to update policy for. |
| spdx_ids | [repeated string](#string) | The SPDX license IDs to delete from the specified context. |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeleteLicensesFromRepositoryPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeletePackageExceptionsFromEnterprisePolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeletePackageExceptionsFromEnterprisePolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ EnterprisePolicy](#enterprisepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeletePackageExceptionsFromRepositoryPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DeletePackageExceptionsFromRepositoryPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DenyAlertDismissalRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| number | [ uint32](#uint32) | none |
| user_id | [ uint64](#uint64) | none |
| comment | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DenyAlertDismissalResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetAlertRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| number | [ uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetAlertResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| alert | [ Alert](#alert) | none |
| events | [repeated AlertEvent](#alertevent) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetCombinedRepositoryPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
| organization_id | [ uint64](#uint64) | none |
| repository_id | [ uint64](#uint64) | none |
| distribution_policy_name | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetCombinedRepositoryPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ CombinedRepositoryPolicy](#combinedrepositorypolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetEnterprisePolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetEnterprisePolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ EnterprisePolicy](#enterprisepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetOrganizationPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| organization_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetOrganizationPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ OrganizationPolicy](#organizationpolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetRepositoryPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetRepositoryPolicyResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| policy | [ RepositoryPolicy](#repositorypolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetReviewableAlertsRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| organization_id | [ uint64](#uint64) | none |
| enterprise_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## GetReviewableAlertsResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| alerts | [repeated Alert](#alert) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RequestAlertDismissalRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| number | [ uint32](#uint32) | none |
| user_id | [ uint64](#uint64) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RequestAlertDismissalResponse



| Field | Type | Description |
| ----- | ---- | ----------- |
| success | [ bool](#bool) | none |
 <!-- end Fields -->
 <!-- end HasFields -->
 <!-- end messages -->

# Enums
 <!-- end Enums -->


 <!-- end services -->

# Messages


## Alert



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ uint64](#uint64) | none |
| number | [ uint32](#uint32) | none |
| status | [ AlertStatus](#alertstatus) | none |
| resolution | [ AlertResolution](#alertresolution) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| repository_id | [ uint64](#uint64) | none |
| organization_id | [ uint64](#uint64) | none |
| enterprise_id | [ uint64](#uint64) | none |
| manifest_name | [ string](#string) | none |
| manifest_line_number | [ uint32](#uint32) | none |
| package_ecosystem | [ PackageManager](#packagemanager) | none |
| package_name | [ string](#string) | none |
| package_version | [ string](#string) | none |
| license | [ string](#string) | none |
| pull_request_number | [ uint32](#uint32) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## AlertEvent



| Field | Type | Description |
| ----- | ---- | ----------- |
| id | [ uint64](#uint64) | none |
| alert_id | [ uint64](#uint64) | none |
| event_type | [ AlertEventType](#alerteventtype) | none |
| user_id | [ uint64](#uint64) | none |
| occurred_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| event_body | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CombinedLicense



| Field | Type | Description |
| ----- | ---- | ----------- |
| spdx_id | [ string](#string) | none |
| added_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| level | [ PolicyLevel](#policylevel) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CombinedPackage



| Field | Type | Description |
| ----- | ---- | ----------- |
| package_manager | [ PackageManager](#packagemanager) | none |
| name | [ string](#string) | none |
| action | [ PackageAction](#packageaction) | none |
| reason | [ string](#string) | none |
| extra_allowed_spdx_ids | [repeated string](#string) | none |
| added_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| level | [ PolicyLevel](#policylevel) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## CombinedRepositoryPolicy



| Field | Type | Description |
| ----- | ---- | ----------- |
| licenses | [repeated CombinedLicense](#combinedlicense) | none |
| packages | [repeated CombinedPackage](#combinedpackage) | none |
| custom_remediation_guidance | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## DistributionPolicy



| Field | Type | Description |
| ----- | ---- | ----------- |
| name | [ string](#string) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## EnterprisePolicy



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
| custom_remediation_guidance | [ string](#string) | none |
| distribution_policies | [repeated DistributionPolicy](#distributionpolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## LicenseEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| spdx_id | [ string](#string) | none |
| contexts | [repeated string](#string) | none |
| added_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## OrganizationPolicy



| Field | Type | Description |
| ----- | ---- | ----------- |
| organization_id | [ uint64](#uint64) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
| custom_remediation_guidance | [ string](#string) | none |
| distribution_policies | [repeated DistributionPolicy](#distributionpolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## Package



| Field | Type | Description |
| ----- | ---- | ----------- |
| package_manager | [ PackageManager](#packagemanager) | none |
| name | [ string](#string) | none |
| version | [ string](#string) | none |
| license | [ string](#string) | none |
| dev_dependency | [ bool](#bool) | none |
| manifests | [repeated string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PackageFailure



| Field | Type | Description |
| ----- | ---- | ----------- |
| package | [ Package](#package) | none |
| reason | [ FailureReason](#failurereason) | none |
| level | [ FailureLevel](#failurelevel) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PackagePolicy



| Field | Type | Description |
| ----- | ---- | ----------- |
| package_manager | [ PackageManager](#packagemanager) | none |
| name | [ string](#string) | none |
| action | [ PackageAction](#packageaction) | none |
| reason | [ string](#string) | none |
| extra_allowed_spdx_ids | [repeated string](#string) | none |
| contexts | [repeated string](#string) | none |
| added_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## PolicyLicenses



| Field | Type | Description |
| ----- | ---- | ----------- |
| allowed | [repeated LicenseEntry](#licenseentry) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepositoryPolicy



| Field | Type | Description |
| ----- | ---- | ----------- |
| repository_id | [ uint64](#uint64) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## RepositoryResults



| Field | Type | Description |
| ----- | ---- | ----------- |
| success_count | [ int64](#int64) | none |
| failure_count | [ int64](#int64) | none |
| error_count | [ int64](#int64) | none |
| last_error | [ string](#string) | none |
| failures | [repeated PackageFailure](#packagefailure) | none |
 <!-- end Fields -->
 <!-- end HasFields -->
 <!-- end messages -->

# Enums


## AlertEventType


| Name | Number | Description |
| ---- | ------ | ----------- |
| ALERT_EVENT_TYPE_UNKNOWN | 0 | none |
| ALERT_EVENT_TYPE_REVIEW_REQUESTED | 1 | none |
| ALERT_EVENT_TYPE_REVIEW_DENIED | 2 | none |
| ALERT_EVENT_TYPE_EXCEPTION_ADDED | 3 | none |
| ALERT_EVENT_TYPE_LICENSES_ADDED | 4 | none |
| ALERT_EVENT_TYPE_CLOSED | 5 | none |
| ALERT_EVENT_TYPE_REVIEW_APPROVED | 6 | none |




## AlertResolution


| Name | Number | Description |
| ---- | ------ | ----------- |
| ALERT_RESOLUTION_UNKNOWN | 0 | none |
| ALERT_RESOLUTION_EXCEPTION_ADDED | 1 | none |
| ALERT_RESOLUTION_POLICY_CHANGED | 2 | none |




## AlertStatus


| Name | Number | Description |
| ---- | ------ | ----------- |
| ALERT_STATUS_UNKNOWN | 0 | none |
| ALERT_STATUS_OPEN | 1 | none |
| ALERT_STATUS_REVIEW_REQUESTED | 2 | none |
| ALERT_STATUS_CLOSED | 3 | none |




## FailureLevel


| Name | Number | Description |
| ---- | ------ | ----------- |
| FAILURE_LEVEL_UNKNOWN | 0 | none |
| FAILURE_LEVEL_NONE | 1 | none |
| FAILURE_LEVEL_REPOSITORY | 2 | none |
| FAILURE_LEVEL_ORGANIZATION | 3 | none |
| FAILURE_LEVEL_ENTERPRISE | 4 | none |




## FailureReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| FAILURE_REASON_UNKNOWN | 0 | none |
| FAILURE_REASON_LICENSE_NOT_ALLOWED | 1 | none |
| FAILURE_REASON_PACKAGE_BLOCKED | 2 | none |
| FAILURE_REASON_EXPIRED | 3 | none |




## PackageAction


| Name | Number | Description |
| ---- | ------ | ----------- |
| PACKAGE_ACTION_UNKNOWN | 0 | none |
| PACKAGE_ACTION_ALLOWED | 1 | none |
| PACKAGE_ACTION_BLOCKED | 2 | none |
| PACKAGE_ACTION_PRIVATE | 3 | none |




## PackageManager
Keep in sync with dependency-graph-api:
https://github.com/github/dependency-graph-api/blob/master/proto/twirp/v1/dependency_graph_api.proto#L108

| Name | Number | Description |
| ---- | ------ | ----------- |
| PACKAGE_MANAGER_UNKNOWN | 0 | none |
| PACKAGE_MANAGER_RUBYGEMS | 1 | none |
| PACKAGE_MANAGER_NPM | 2 | none |
| PACKAGE_MANAGER_PIP | 3 | none |
| PACKAGE_MANAGER_MAVEN | 4 | none |
| PACKAGE_MANAGER_NUGET | 5 | none |
| PACKAGE_MANAGER_COMPOSER | 6 | none |
| PACKAGE_MANAGER_GOMOD | 7 | none |
| PACKAGE_MANAGER_RUST | 8 | none |
| PACKAGE_MANAGER_ACTIONS | 9 | none |
| PACKAGE_MANAGER_PUB | 10 | none |
| PACKAGE_MANAGER_SWIFT | 11 | none |




## PolicyLevel


| Name | Number | Description |
| ---- | ------ | ----------- |
| POLICY_LEVEL_UNKNOWN | 0 | none |
| POLICY_LEVEL_REPOSITORY | 1 | none |
| POLICY_LEVEL_ORGANIZATION | 2 | none |
| POLICY_LEVEL_ENTERPRISE | 3 | none |




## RepositoryCheckStatus


| Name | Number | Description |
| ---- | ------ | ----------- |
| REPOSITORY_CHECK_STATUS_UNKNOWN | 0 | none |
| REPOSITORY_CHECK_STATUS_FAIL | 1 | none |
| REPOSITORY_CHECK_STATUS_PASS | 2 | none |
| REPOSITORY_CHECK_STATUS_PENDING | 3 | none |


 <!-- end Enums -->
 <!-- end Files -->

# Scalar Value Types

| .proto Type | Notes | Go Type | Ruby Type |
| ----------- | ----- | -------- | --------- |
| <div><h4 id="double" /></div><a name="double" /> double |  | float64 | Float |
| <div><h4 id="float" /></div><a name="float" /> float |  | float32 | Float |
| <div><h4 id="int32" /></div><a name="int32" /> int32 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint32 instead. | int32 | Bignum or Fixnum (as required) |
| <div><h4 id="int64" /></div><a name="int64" /> int64 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint64 instead. | int64 | Bignum |
| <div><h4 id="uint32" /></div><a name="uint32" /> uint32 | Uses variable-length encoding. | uint32 | Bignum or Fixnum (as required) |
| <div><h4 id="uint64" /></div><a name="uint64" /> uint64 | Uses variable-length encoding. | uint64 | Bignum or Fixnum (as required) |
| <div><h4 id="sint32" /></div><a name="sint32" /> sint32 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int32s. | int32 | Bignum or Fixnum (as required) |
| <div><h4 id="sint64" /></div><a name="sint64" /> sint64 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int64s. | int64 | Bignum |
| <div><h4 id="fixed32" /></div><a name="fixed32" /> fixed32 | Always four bytes. More efficient than uint32 if values are often greater than 2^28. | uint32 | Bignum or Fixnum (as required) |
| <div><h4 id="fixed64" /></div><a name="fixed64" /> fixed64 | Always eight bytes. More efficient than uint64 if values are often greater than 2^56. | uint64 | Bignum |
| <div><h4 id="sfixed32" /></div><a name="sfixed32" /> sfixed32 | Always four bytes. | int32 | Bignum or Fixnum (as required) |
| <div><h4 id="sfixed64" /></div><a name="sfixed64" /> sfixed64 | Always eight bytes. | int64 | Bignum |
| <div><h4 id="bool" /></div><a name="bool" /> bool |  | bool | TrueClass/FalseClass |
| <div><h4 id="string" /></div><a name="string" /> string | A string must always contain UTF-8 encoded or 7-bit ASCII text. | string | String (UTF-8) |
| <div><h4 id="bytes" /></div><a name="bytes" /> bytes | May contain any arbitrary sequence of bytes. | []byte | String (ASCII-8BIT) |

