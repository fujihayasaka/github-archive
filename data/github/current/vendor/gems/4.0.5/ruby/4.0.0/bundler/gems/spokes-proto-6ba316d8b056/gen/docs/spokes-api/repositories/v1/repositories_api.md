[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/repositories/v1/repositories_api.proto



## Services

<a name="github.spokes.repositories.v1.RepositoriesAPI"></a>

### RepositoriesAPI

RepositoriesAPI contains APIs for repository related operations.

<a name="github.spokes.repositories.v1.RepositoriesAPI-ListAvailableReplicas"></a>

#### ListAvailableReplicas

ListAvailableReplicas returns a list of all the available replicas for a
repository.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.repositories.v1.RepositoriesAPI/ListAvailableReplicas`

<a name="github.spokes.repositories.v1.ListAvailableReplicasRequest"></a>

##### ListAvailableReplicasRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository used to retrieve replicas. |



<a name="github.spokes.repositories.v1.ListAvailableReplicasResponse"></a>

##### ListAvailableReplicasResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| replicas | [ReplicaItem](replica_item.md#github.spokes.repositories.v1.ReplicaItem) | repeated | replicas are the available replicas for the repository, sorted by most to least recommended. |



<a name="github.spokes.repositories.v1.RepositoriesAPI-UpdateInfoNWO"></a>

#### UpdateInfoNWO

UpdateInfoNWO creates or updates the info/nwo file that lives in a repository.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.repositories.v1.RepositoriesAPI/UpdateInfoNWO`

<a name="github.spokes.repositories.v1.UpdateInfoNWORequest"></a>

##### UpdateInfoNWORequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository used to update the info/nwo file. |
| nwo | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | nwo is the repository "name with owner" to write to the info/nwo file.

required |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| priority | [github.spokes.types.v1.UpdateReferencesPriority](../../types/v1/update_references_priority.md#github.spokes.types.v1.UpdateReferencesPriority) |  | priority is the priority for this update.

required |
| sockstat | [github.spokes.types.v1.Sockstat](../../types/v1/sockstat.md#github.spokes.types.v1.Sockstat) |  | sockstat is the sockstat data to be used for this update. |



<a name="github.spokes.repositories.v1.UpdateInfoNWOResponse"></a>

##### UpdateInfoNWOResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| error_reason | [UpdateInfoNWOResponse.ErrorReason](#github.spokes.repositories.v1.UpdateInfoNWOResponse.ErrorReason) |  | error_reason is a machine-readable 3PC error code. |
| error_message | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | error_message is a human-readable error message. |
| checksum | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | checksum provides the Spokes checksum after the operation completed |
| committed_at | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | committed_at provides a time value, formatted as a unixtime stamp, for when the 3pc transaction that updates the info/nwo file has been committed. |



<a name="github.spokes.repositories.v1.RepositoriesAPI-RecomputeChecksums"></a>

#### RecomputeChecksums

RecomputeChecksums does a 3pc transaction to recompute the checksums, but does not change hard state.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.repositories.v1.RepositoriesAPI/RecomputeChecksums`

<a name="github.spokes.repositories.v1.RecomputeChecksumsRequest"></a>

##### RecomputeChecksumsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository for which the checksum will be recomputed. (required) |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request_context determines the quality of service we ask for from gitmon |
| priority | [github.spokes.types.v1.UpdateReferencesPriority](../../types/v1/update_references_priority.md#github.spokes.types.v1.UpdateReferencesPriority) |  | priority is the priority for the checksum recomputation. (required) |
| sockstat | [github.spokes.types.v1.Sockstat](../../types/v1/sockstat.md#github.spokes.types.v1.Sockstat) |  | sockstat is the sockstat data to be used for this checksum recomputation. |
| checksum_strategy | [RecomputeChecksumsRequest.ChecksumStrategy](#github.spokes.repositories.v1.RecomputeChecksumsRequest.ChecksumStrategy) |  | checksum_strategy chooses whether we recompute the checksums from scratch. (required) |



<a name="github.spokes.repositories.v1.RecomputeChecksumsResponse"></a>

##### RecomputeChecksumsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| error_reason | [RecomputeChecksumsResponse.ErrorReason](#github.spokes.repositories.v1.RecomputeChecksumsResponse.ErrorReason) |  | error_reason is a machine-readable 3PC error code. |
| error_message | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | error_message is a human-readable error message. |
| checksum | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | checksum provides the Spokes checksum after the operation completed |
| committed_at | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | committed_at provides a time value, formatted as a unixtime stamp, for when the recomputation happened. |



<a name="github.spokes.repositories.v1.RepositoriesAPI-CreateFork"></a>

#### CreateFork

CreateFork creates a fork repository on-disk and in the Spokes DB, including
cloning the appropriate contents of the parent into the fork.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.repositories.v1.RepositoriesAPI/CreateFork`

<a name="github.spokes.repositories.v1.CreateForkRequest"></a>

##### CreateForkRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| parent | [ParentRepository](#github.spokes.repositories.v1.ParentRepository) |  | parent is the parent repository from which the fork should be created. |
| fork | [CreateForkRequest.Fork](#github.spokes.repositories.v1.CreateForkRequest.Fork) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| branch_mode | [CreateForkRequest.BranchMode](#github.spokes.repositories.v1.CreateForkRequest.BranchMode) |  |  |
| token | [github.spokes.types.v1.Token](../../types/v1/token.md#github.spokes.types.v1.Token) |  | token is an opaque token to poll for the status of an in progress fork operation. |
| wait_milliseconds | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | wait_milliseconds is the amount of time gitrpcd should wait before telling the caller the operation is still running. |



<a name="github.spokes.repositories.v1.CreateForkResponse"></a>

##### CreateForkResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| status | [CreateForkResponse.Status](#github.spokes.repositories.v1.CreateForkResponse.Status) |  | status is the machine-readable status of the fork operation. |
| message | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | message includes details, if available, related to the status of the operation. |
| token | [github.spokes.types.v1.Token](../../types/v1/token.md#github.spokes.types.v1.Token) |  | token is an opaque token to poll for the status of an in progress fork operation. |



<a name="github.spokes.repositories.v1.RepositoriesAPI-GetRepositoryMetadata"></a>

#### GetRepositoryMetadata

GetRepositoryMetadata provides a list of repository metadata, including
the hash algorithm and ref format.
Note: For repository and network metadata, use v2.GetRepositoryMetadata

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.repositories.v1.RepositoriesAPI/GetRepositoryMetadata`

<a name="github.spokes.repositories.v1.GetRepositoryMetadataRequest"></a>

##### GetRepositoryMetadataRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository used to update the info/nwo file. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.repositories.v1.GetRepositoryMetadataResponse"></a>

##### GetRepositoryMetadataResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| hash_algorithm | [github.spokes.types.v1.HashAlgorithm](../../types/v1/hash_algorithm.md#github.spokes.types.v1.HashAlgorithm) |  | hash_algorithm is the main hash algorithm in use for this repository. |
| ref_format | [github.spokes.types.v1.RefFormat](../../types/v1/ref_format.md#github.spokes.types.v1.RefFormat) |  | ref_format is the ref format in use for this repository. |



<a name="github.spokes.repositories.v1.RepositoriesAPI-CreateRepository"></a>

#### CreateRepository

CreateRepository creates a repository on-disk and in the Spokes DB.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.repositories.v1.RepositoriesAPI/CreateRepository`

<a name="github.spokes.repositories.v1.CreateRepositoryRequest"></a>

##### CreateRepositoryRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to be created. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| nwo | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | nwo is the name with owner of the repository. |
| initial_commit | [CreateRepositoryRequest.InitialCommit](#github.spokes.repositories.v1.CreateRepositoryRequest.InitialCommit) |  | initial_commit contains data for optionally creating an initial commit in the repository. |
| default_branch | [github.spokes.types.v1.Reference](../../types/v1/reference.md#github.spokes.types.v1.Reference) |  | default_branch is the reference to use for the default branch. |
| hash_algorithm | [github.spokes.types.v1.HashAlgorithm](../../types/v1/hash_algorithm.md#github.spokes.types.v1.HashAlgorithm) |  | hash_algorithm is the main hash algorithm in use for this repository. |
| ref_format | [github.spokes.types.v1.RefFormat](../../types/v1/ref_format.md#github.spokes.types.v1.RefFormat) |  | ref_format is the ref format in use for this repository. |



<a name="github.spokes.repositories.v1.CreateRepositoryResponse"></a>

##### CreateRepositoryResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| head_oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | head_oid is the object ID of the commit at the head of the default branch. |



<a name="github.spokes.repositories.v1.CreateForkRequest.BranchMode"></a>

### CreateForkRequest.BranchMode


| Name | Number | Description |
| ---- | ------ | ----------- |
| BRANCH_MODE_INVALID | 0 |  |
| BRANCH_MODE_ALL_BRANCHES | 1 | create the fork with all branches of the parent. |
| BRANCH_MODE_DEFAULT_BRANCH | 2 | create the fork with only the default branch of the parent. |


<a name="github.spokes.repositories.v1.CreateForkResponse.Status"></a>

### CreateForkResponse.Status


| Name | Number | Description |
| ---- | ------ | ----------- |
| STATUS_INVALID | 0 |  |
| STATUS_COMPLETE | 1 |  |
| STATUS_FAILED | 2 |  |
| STATUS_INPROGRESS | 3 |  |


<a name="github.spokes.repositories.v1.RecomputeChecksumsRequest.ChecksumStrategy"></a>

### RecomputeChecksumsRequest.ChecksumStrategy


| Name | Number | Description |
| ---- | ------ | ----------- |
| CHECKSUM_STRATEGY_INVALID | 0 |  |
| CHECKSUM_STRATEGY_REUSE_CHECKSUMS | 1 |  |
| CHECKSUM_STRATEGY_FORGET_CHECKSUMS | 2 |  |


<a name="github.spokes.repositories.v1.RecomputeChecksumsResponse.ErrorReason"></a>

### RecomputeChecksumsResponse.ErrorReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| ERROR_REASON_INVALID | 0 |  |
| ERROR_REASON_FAILED_TO_LOCK | 1 |  |
| ERROR_REASON_THREEPC | 2 |  |
| ERROR_REASON_TOO_BUSY | 3 |  |
| ERROR_REASON_TIMEOUT | 4 |  |
| ERROR_REASON_DATABASE | 5 |  |


<a name="github.spokes.repositories.v1.UpdateInfoNWOResponse.ErrorReason"></a>

### UpdateInfoNWOResponse.ErrorReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| ERROR_REASON_INVALID | 0 |  |
| ERROR_REASON_FAILED_TO_LOCK | 1 |  |
| ERROR_REASON_THREEPC | 2 |  |
| ERROR_REASON_TOO_BUSY | 3 |  |
| ERROR_REASON_TIMEOUT | 4 |  |
| ERROR_REASON_DATABASE | 5 |  |


