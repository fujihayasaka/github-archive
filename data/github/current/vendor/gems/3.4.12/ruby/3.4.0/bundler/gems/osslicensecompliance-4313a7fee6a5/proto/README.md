_Version: 0.3.0_

# API Reference

# Table of Contents


<details><summary>Services (1)</summary>

  - [LicenseCompliance](#licensecompliance)


</details>


<details><summary>Messages (14)</summary>

  - [CheckRepositoryRequest](#checkrepositoryrequest)
  - [CheckRepositoryResponse](#checkrepositoryresponse)
  - [CreateEnterprisePolicyRequest](#createenterprisepolicyrequest)
  - [CreateEnterprisePolicyResponse](#createenterprisepolicyresponse)
  - [CreateOrganizationPolicyRequest](#createorganizationpolicyrequest)
  - [CreateOrganizationPolicyResponse](#createorganizationpolicyresponse)
  - [CreateRepositoryPolicyRequest](#createrepositorypolicyrequest)
  - [CreateRepositoryPolicyResponse](#createrepositorypolicyresponse)
  - [GetEnterprisePolicyRequest](#getenterprisepolicyrequest)
  - [GetEnterprisePolicyResponse](#getenterprisepolicyresponse)
  - [GetOrganizationPolicyRequest](#getorganizationpolicyrequest)
  - [GetOrganizationPolicyResponse](#getorganizationpolicyresponse)
  - [GetRepositoryPolicyRequest](#getrepositorypolicyrequest)
  - [GetRepositoryPolicyResponse](#getrepositorypolicyresponse)


</details>





<details><summary>Messages (9)</summary>

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


<details><summary>Enums (5)</summary>

  - [FailureLevel](#failurelevel)
  - [FailureReason](#failurereason)
  - [PackageAction](#packageaction)
  - [PackageManager](#packagemanager)
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


## CreateEnterprisePolicy

> **rpc** CreateEnterprisePolicy([CreateEnterprisePolicyRequest](#createenterprisepolicyrequest))
    [CreateEnterprisePolicyResponse](#createenterprisepolicyresponse)


## GetEnterprisePolicy

> **rpc** GetEnterprisePolicy([GetEnterprisePolicyRequest](#getenterprisepolicyrequest))
    [GetEnterprisePolicyResponse](#getenterprisepolicyresponse)


## CreateRepositoryPolicy

> **rpc** CreateRepositoryPolicy([CreateRepositoryPolicyRequest](#createrepositorypolicyrequest))
    [CreateRepositoryPolicyResponse](#createrepositorypolicyresponse)


## GetRepositoryPolicy

> **rpc** GetRepositoryPolicy([GetRepositoryPolicyRequest](#getrepositorypolicyrequest))
    [GetRepositoryPolicyResponse](#getrepositorypolicyresponse)


## CheckRepository

> **rpc** CheckRepository([CheckRepositoryRequest](#checkrepositoryrequest))
    [CheckRepositoryResponse](#checkrepositoryresponse)


 <!-- end methods -->
 <!-- end services -->

# Messages


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


## CreateRepositoryPolicyRequest



| Field | Type | Description |
| ----- | ---- | ----------- |
| organization_id | [ uint64](#uint64) | none |
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
 <!-- end messages -->

# Enums
 <!-- end Enums -->


 <!-- end services -->

# Messages


## EnterprisePolicy



| Field | Type | Description |
| ----- | ---- | ----------- |
| enterprise_id | [ uint64](#uint64) | none |
| created_at | [ google.protobuf.Timestamp](#googleprotobuftimestamp) | none |
| licenses | [ PolicyLicenses](#policylicenses) | none |
| packages | [repeated PackagePolicy](#packagepolicy) | none |
| custom_remediation_guidance | [ string](#string) | none |
 <!-- end Fields -->
 <!-- end HasFields -->


## LicenseEntry



| Field | Type | Description |
| ----- | ---- | ----------- |
| spdx_id | [ string](#string) | none |
| contexts | [repeated string](#string) | none |
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
| match_licenses | [repeated string](#string) | none |
| contexts | [repeated string](#string) | none |
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
| organization_id | [ uint64](#uint64) | none |
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

