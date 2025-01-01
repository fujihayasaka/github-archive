[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/gitauth/v1/gitauth_api.proto



## Services

<a name="github.spokes.gitauth.v1.GitauthAPI"></a>

### GitauthAPI

This API is the interface that the gitauth service uses to talk to spokesd
during a Git request.

<a name="github.spokes.gitauth.v1.GitauthAPI-ListRoutes"></a>

#### ListRoutes

ListRoutes provides the list of routes and a quarantine ID. The routes are
sorted based on the action requested.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.gitauth.v1.GitauthAPI/ListRoutes`

<a name="github.spokes.gitauth.v1.ListRoutesRequest"></a>

##### ListRoutesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| action | [ListRoutesRequest.Action](#github.spokes.gitauth.v1.ListRoutesRequest.Action) |  | what action is being is being requested for. We expect the list of routes being returned to map to the action being taken. |
| protocol | [ListRoutesRequest.Protocol](#github.spokes.gitauth.v1.ListRoutesRequest.Protocol) |  | the protocol for the incoming request being made to babeld from the customer. We expected the list of routes being returned to map to the protocol being taken. |



<a name="github.spokes.gitauth.v1.ListRoutesResponse"></a>

##### ListRoutesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| replicas | [github.spokes.repositories.v1.ReplicaItem](../../repositories/v1/replica_item.md#github.spokes.repositories.v1.ReplicaItem) | repeated | the list of routes to replicas based on the action requested. |
| quarantine_id | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | quarantine id to add to sockstat, if this is a push. |



<a name="github.spokes.gitauth.v1.GitauthAPI-SetUpPushState"></a>

#### SetUpPushState

SetUpPushState accepts a list of babeld host statuses and a quarantine ID
and returns a transaction state for use in RequestContext in subsequent
Spokes Access API calls.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.gitauth.v1.GitauthAPI/SetUpPushState`

<a name="github.spokes.gitauth.v1.SetUpPushStateRequest"></a>

##### SetUpPushStateRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| quarantine_id | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | the quarantine ID for this push. |
| hosts | [HostStatus](#github.spokes.gitauth.v1.HostStatus) | repeated | the status of each replica in the push. |



<a name="github.spokes.gitauth.v1.SetUpPushStateResponse"></a>

##### SetUpPushStateResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| push_state | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | push_state is the updated transaction state. This value should be used as the RequestContext.transaction_state in all Spokes Access API calls that happen while the quarantine is still active. |



<a name="github.spokes.gitauth.v1.GitauthAPI-CommitQuarantine"></a>

#### CommitQuarantine

CommitQuarantine moves objects from the quarantine into a repository's object directory

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.gitauth.v1.GitauthAPI/CommitQuarantine`

<a name="github.spokes.gitauth.v1.CommitQuarantineRequest"></a>

##### CommitQuarantineRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request context must include transaction state, which identifies the quarantine to commit. |
| preserve_quarantine | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | Controls whether or not to clear the quarantine directory after committing. By default, quarantine is cleared after committing. |



<a name="github.spokes.gitauth.v1.CommitQuarantineResponse"></a>

##### CommitQuarantineResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| push_state | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | push_state is the updated transaction state. Clients should stop using the prior RequestContext.transaction_state and use this value instead. |



<a name="github.spokes.gitauth.v1.GitauthAPI-RemoveQuarantine"></a>

#### RemoveQuarantine

RemoveQuarantine the quarantine directory

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.gitauth.v1.GitauthAPI/RemoveQuarantine`

<a name="github.spokes.gitauth.v1.RemoveQuarantineRequest"></a>

##### RemoveQuarantineRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request context may include transaction state, which identifies the quarantine to remove. |
| quarantine_id | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | an identifier to uniquely map a quarantine path for the pack in the push. if this is unavailable, we will look at the transaction state in the request context. |



<a name="google.protobuf.Empty"></a>

##### .google.protobuf.Empty


<a name="github.spokes.gitauth.v1.ListRoutesRequest.Action"></a>

### ListRoutesRequest.Action


| Name | Number | Description |
| ---- | ------ | ----------- |
| ACTION_INVALID | 0 |  |
| ACTION_READ | 1 |  |
| ACTION_WRITE | 2 |  |


<a name="github.spokes.gitauth.v1.ListRoutesRequest.Protocol"></a>

### ListRoutesRequest.Protocol


| Name | Number | Description |
| ---- | ------ | ----------- |
| PROTOCOL_INVALID | 0 |  |
| PROTOCOL_SSH | 1 |  |
| PROTOCOL_HTTP | 2 |  |
| PROTOCOL_SVN | 3 |  |
| PROTOCOL_GIT | 4 |  |


