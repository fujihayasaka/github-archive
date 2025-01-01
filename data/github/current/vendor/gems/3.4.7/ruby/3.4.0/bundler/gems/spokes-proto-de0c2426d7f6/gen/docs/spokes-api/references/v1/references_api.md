[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/references/v1/references_api.proto



## Services

<a name="github.spokes.references.v1.ReferencesAPI"></a>

### ReferencesAPI

ReferencesAPI contains APIs for reference-related Git operations.

<a name="github.spokes.references.v1.ReferencesAPI-ResolveReferences"></a>

#### ResolveReferences

ResolveReferences resolves each of the given fully-qualified reference
names to their corresponding referenced object ID. Limited to a maximum
of 1000 references per request.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.references.v1.ReferencesAPI/ResolveReferences`

<a name="github.spokes.references.v1.ResolveReferencesRequest"></a>

##### ResolveReferencesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the reference lookup to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| references | [github.spokes.types.v1.Reference](../../types/v1/reference.md#github.spokes.types.v1.Reference) | repeated | references are the refs to resolve to their respective OIDs.

Reference names passed here must be valid fully-qualified reference names and follow the rules in https://git-scm.com/docs/git-check-ref-format#_description. For example, "refs/heads/main", "refs/tags/v1.0", and "HEAD" are valid qualified ref names, but "main", "REBASE_HEAD", and "tags/v1.0" are not. Note that this differs from the validation of the ObjectSelector type, which allows for looser reference specifications.

A maximum of 10000 references are allowed per request. |



<a name="github.spokes.references.v1.ResolveReferencesResponse"></a>

##### ResolveReferencesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [ResolveReferencesResponse.ResolvedReference](#github.spokes.references.v1.ResolveReferencesResponse.ResolvedReference) | repeated | items is the list resolved references. |



<a name="github.spokes.references.v1.ReferencesAPI-ListReferences"></a>

#### ListReferences

ListReferences returns a list of references. Note that this endpoint will
include references in the internal namespaces such as refs/__gh__ and
refs/pull. These will need to be filtered out, either with a selector or
explicitly before returning data to customers.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.references.v1.ReferencesAPI/ListReferences`

<a name="github.spokes.references.v1.ListReferencesRequest"></a>

##### ListReferencesRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the object lookup to. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) universal_selector | [github.spokes.types.selectors.v1.UniversalSelector](../../types/selectors/v1/universal_selector.md#github.spokes.types.selectors.v1.UniversalSelector) |  | universal_selector selects all references in the repository. |
| (oneof selector) prefix_selector | [github.spokes.types.selectors.v1.PrefixSelector](../../types/selectors/v1/prefix_selector.md#github.spokes.types.selectors.v1.PrefixSelector) |  | prefix_selector selects references based on matching prefixes. |



<a name="github.spokes.references.v1.ListReferencesResponse"></a>

##### ListReferencesResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reference_items | [ReferenceItem](reference_item.md#github.spokes.references.v1.ReferenceItem) | repeated | references is the list of references. |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.references.v1.ReferencesAPI-GetDefaultBranch"></a>

#### GetDefaultBranch

GetDefaultBranch returns the name of the default branch for a repository.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.references.v1.ReferencesAPI/GetDefaultBranch`

<a name="github.spokes.references.v1.GetDefaultBranchRequest"></a>

##### GetDefaultBranchRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the object lookup to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.references.v1.GetDefaultBranchResponse"></a>

##### GetDefaultBranchResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| reference | [github.spokes.types.v1.Reference](../../types/v1/reference.md#github.spokes.types.v1.Reference) |  | reference is the default branch reference for the repository. |



<a name="github.spokes.references.v1.ReferencesAPI-ListReferencesWithDetails"></a>

#### ListReferencesWithDetails

ListReferencesWithDetails returns a list of references which match a
given glob pattern. The list of references includes the creation time for
each reference: tagger date for tags, committer date for commits. If a
tag does not have tagger information, the committer date is returned
instead.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.references.v1.ReferencesAPI/ListReferencesWithDetails`

<a name="github.spokes.references.v1.ListReferencesWithDetailsRequest"></a>

##### ListReferencesWithDetailsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository for which tags are retrieved |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) universal_selector | [github.spokes.types.selectors.v1.UniversalSelector](../../types/selectors/v1/universal_selector.md#github.spokes.types.selectors.v1.UniversalSelector) |  | universal_selector selects all references in the repository, including our hidden bookkeeping references. |
| (oneof selector) ref_glob_selector | [github.spokes.types.selectors.v1.RefGlobSelector](../../types/selectors/v1/ref_glob_selector.md#github.spokes.types.selectors.v1.RefGlobSelector) |  | ref glob selector selects all references matching a given glob pattern, including our hidden bookkeeping references. |



<a name="github.spokes.references.v1.ListReferencesWithDetailsResponse"></a>

##### ListReferencesWithDetailsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| refs | [RefWithCommitTime](ref_with_commit_time.md#github.spokes.references.v1.RefWithCommitTime) | repeated | tag refs returned with creation time information |



<a name="github.spokes.references.v1.ReferencesAPI-Update"></a>

#### Update

Update updates references for a repository

This is a low-level interface that interacts directly with a repository.
It does not respect application-level restrictions such as branch
protections or run hooks.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.references.v1.ReferencesAPI/Update`

<a name="github.spokes.references.v1.UpdateRequest"></a>

##### UpdateRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository for which refs are updated. |
| nwo | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | nwo is the NWO for the repository for which refs are updated. |
| priority | [github.spokes.types.v1.UpdateReferencesPriority](../../types/v1/update_references_priority.md#github.spokes.types.v1.UpdateReferencesPriority) |  | priority is the priority for the ref update. |
| txn | [Transaction](transaction.md#github.spokes.references.v1.Transaction) |  | txn is the transaction to perform for the ref update. |
| sockstat | [github.spokes.types.v1.Sockstat](../../types/v1/sockstat.md#github.spokes.types.v1.Sockstat) |  | sockstat is the sockstat data to be used for this ref update. |
| fileservers | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) | repeated | fileservers, if not empty, is the list of file servers to use. This is used only during gist creation. |



<a name="github.spokes.references.v1.UpdateResponse"></a>

##### UpdateResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| error_reason | [UpdateResponse.ErrorReason](#github.spokes.references.v1.UpdateResponse.ErrorReason) |  | error_reason is a machine-readable 3PC error code. |
| error_message | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | error_message is a human-readable error message. |
| checksum | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | checksum provides the Spokes checksum after the operation completed |
| committed_at | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | committed_at provides a time value, formatted as a unixtime stamp, for when the commit was applied. |
| refs_status | [RefStatus](ref_status.md#github.spokes.references.v1.RefStatus) | repeated | refs_status represents the failures for each ref update operation |



<a name="github.spokes.references.v1.ReferencesAPI-UpdateDefaultBranch"></a>

#### UpdateDefaultBranch

UpdateDefaultBranch updates the HEAD reference for a repository

This is a low-level interface that interacts directly with a repository.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.references.v1.ReferencesAPI/UpdateDefaultBranch`

<a name="github.spokes.references.v1.UpdateDefaultBranchRequest"></a>

##### UpdateDefaultBranchRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository for which refs are updated. (required) |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| nwo | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | nwo is the NWO for the repository for which refs are updated. |
| priority | [github.spokes.types.v1.UpdateReferencesPriority](../../types/v1/update_references_priority.md#github.spokes.types.v1.UpdateReferencesPriority) |  | priority is the priority for the ref update. (required) |
| new_value | [github.spokes.types.v1.Reference](../../types/v1/reference.md#github.spokes.types.v1.Reference) |  | new_value is the value to set the symbolic reference to. (required) |
| sockstat | [github.spokes.types.v1.Sockstat](../../types/v1/sockstat.md#github.spokes.types.v1.Sockstat) |  | sockstat is the sockstat data to be used for this ref update. |



<a name="github.spokes.references.v1.UpdateDefaultBranchResponse"></a>

##### UpdateDefaultBranchResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| error_reason | [UpdateDefaultBranchResponse.ErrorReason](#github.spokes.references.v1.UpdateDefaultBranchResponse.ErrorReason) |  | error_reason is a machine-readable 3PC error code. |
| error_message | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | error_message is a human-readable error message. |
| checksum | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | checksum provides the Spokes checksum after the operation completed |
| committed_at | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | committed_at provides a time value, formatted as a unixtime stamp, for when the commit was applied. |



<a name="github.spokes.references.v1.ReferencesAPI-ReferencesExist"></a>

#### ReferencesExist

ReferencesExist returns a boolean indicating if the repository has refs.
Additionally specifies whether those refs are branches or tags.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.references.v1.ReferencesAPI/ReferencesExist`

<a name="github.spokes.references.v1.ReferencesExistRequest"></a>

##### ReferencesExistRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the reference lookup to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.references.v1.ReferencesExistResponse"></a>

##### ReferencesExistResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| any | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | any indicates whether any references exist in the repository |
| branches | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | branches indicates whether any branches exist |
| tags | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | tags indicates whether any tags exist |



<a name="github.spokes.references.v1.UpdateDefaultBranchResponse.ErrorReason"></a>

### UpdateDefaultBranchResponse.ErrorReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| ERROR_REASON_INVALID | 0 |  |
| ERROR_REASON_FAILED_TO_LOCK | 1 |  |
| ERROR_REASON_THREEPC | 2 |  |
| ERROR_REASON_TOO_BUSY | 3 |  |
| ERROR_REASON_TIMEOUT | 4 |  |
| ERROR_REASON_DATABASE | 5 |  |


<a name="github.spokes.references.v1.UpdateResponse.ErrorReason"></a>

### UpdateResponse.ErrorReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| ERROR_REASON_INVALID | 0 |  |
| ERROR_REASON_FAILED_TO_LOCK | 1 |  |
| ERROR_REASON_THREEPC | 2 |  |
| ERROR_REASON_TOO_BUSY | 3 |  |
| ERROR_REASON_TIMEOUT | 4 |  |
| ERROR_REASON_DATABASE | 5 |  |


