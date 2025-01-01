[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/objects/v1/objects_api.proto



## Services

<a name="github.spokes.objects.v1.ObjectsAPI"></a>

### ObjectsAPI

ObjectsAPI contains APIs for object-related Git operations.

<a name="github.spokes.objects.v1.ObjectsAPI-ResolveObject"></a>

#### ResolveObject

ResolveObject returns a single resolved object by revision.

If the input 'object_name' is ambiguous and could refer to multiple
objects, an InvalidArgument error (e.g. "object_name is an ambiguous
short object ID") will be returned.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.objects.v1.ObjectsAPI/ResolveObject`

<a name="github.spokes.objects.v1.ResolveObjectRequest"></a>

##### ResolveObjectRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the object lookup to. |
| object_name | [github.spokes.types.v1.Revision](../../types/v1/revision.md#github.spokes.types.v1.Revision) |  | object_name is the revision which will be used to look up the object. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.objects.v1.ResolveObjectResponse"></a>

##### ResolveObjectResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| oid | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) |  | oid is the resolve object ID. |



<a name="github.spokes.objects.v1.ObjectsAPI-ResolveObjects"></a>

#### ResolveObjects

ResolveObjects returns multiple resolved objects.
The entries in the response are in the same order as the items in the request.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.objects.v1.ObjectsAPI/ResolveObjects`

<a name="github.spokes.objects.v1.ResolveObjectsRequest"></a>

##### ResolveObjectsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the object lookup to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| selectors | [github.spokes.types.selectors.v1.ObjectSelector](../../types/selectors/v1/object_selector.md#github.spokes.types.selectors.v1.ObjectSelector) | repeated | selectors defines the objects to select.

Reference names passed here must be valid ref, branch, or tag names and follow the rules in https://git-scm.com/docs/git-check-ref-format#_description. For example, "main", "refs/heads/main", "v1.0", "refs/tags/v1.0" are all valid ref names. In particular, ref names may not include NUL (\0), NL (\n), or colon (:). If a selector includes an invalid reference name, the corresponding response item will be the error "unprocessable".

Path names passed here may not include a NUL (\0) or NL (\n) character. If a path includes a forbidden character, even if it is valid, the corresponding response item will be the error "unprocessable". |



<a name="github.spokes.objects.v1.ResolveObjectsResponse"></a>

##### ResolveObjectsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [ResolveObjectsResponse.ResolvedItem](#github.spokes.objects.v1.ResolveObjectsResponse.ResolvedItem) | repeated | items is the list of resolved objects, in the same order that they appear in the request. |



<a name="github.spokes.objects.v1.ObjectsAPI-ExpandOids"></a>

#### ExpandOids

ExpandOids returns the full oid for a list of abbreviated oids.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.objects.v1.ObjectsAPI/ExpandOids`

<a name="github.spokes.objects.v1.ExpandOidsRequest"></a>

##### ExpandOidsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the object lookup to. |
| selectors | [github.spokes.types.selectors.v1.ObjectSelector](../../types/selectors/v1/object_selector.md#github.spokes.types.selectors.v1.ObjectSelector) | repeated | selectors is the list of abbreviated oids and their corresponding types to expand. The users of this API can specify the long version of the OID, but it would not make sense to perform this RPC if you already have the long version of the OID. At most 1000 elements are allowed. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.objects.v1.ExpandOidsResponse"></a>

##### ExpandOidsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| oids | [ExpandOidsResponse.ExpandedOid](#github.spokes.objects.v1.ExpandOidsResponse.ExpandedOid) | repeated | oids is the list of expanded OIDs. |



<a name="github.spokes.objects.v1.ObjectsAPI-ReadObjects"></a>

#### ReadObjects

ReadObjects returns the list of objects that have been requested.
The entries in the response are in the same order as the items in the
request. The response contains a polymorphic list of objects, which can
be one of the following:
- CommitObject
- BlobObject
- TreeObject
- TagObject
- ErrorObject

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.objects.v1.ObjectsAPI/ReadObjects`

<a name="github.spokes.objects.v1.ReadObjectsRequest"></a>

##### ReadObjectsRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the object lookup to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| selectors | [github.spokes.types.selectors.v1.ObjectSelector](../../types/selectors/v1/object_selector.md#github.spokes.types.selectors.v1.ObjectSelector) | repeated | selectors represents the objects we want to read. At most 1000 objects can be read at once. |



<a name="github.spokes.objects.v1.ReadObjectsResponse"></a>

##### ReadObjectsResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| objects | [Object](#github.spokes.objects.v1.Object) | repeated | objects represent the list of objects that have been read. |



<a name="github.spokes.objects.v1.ErrorObject.ErrorReason"></a>

### ErrorObject.ErrorReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| ERROR_REASON_INVALID | 0 |  |
| ERROR_REASON_MISSING | 1 |  |
| ERROR_REASON_AMBIGUOUS | 2 |  |
| ERROR_REASON_TYPE_MISMATCH | 3 |  |
| ERROR_REASON_TOO_LARGE | 4 |  |


<a name="github.spokes.objects.v1.ExpandOidsResponse.ErrorResult.ErrorReason"></a>

### ExpandOidsResponse.ErrorResult.ErrorReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| ERROR_REASON_INVALID | 0 |  |
| ERROR_REASON_MISSING | 1 |  |
| ERROR_REASON_AMBIGUOUS | 2 |  |
| ERROR_REASON_TYPE_MISMATCH | 3 |  |


