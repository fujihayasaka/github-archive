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


