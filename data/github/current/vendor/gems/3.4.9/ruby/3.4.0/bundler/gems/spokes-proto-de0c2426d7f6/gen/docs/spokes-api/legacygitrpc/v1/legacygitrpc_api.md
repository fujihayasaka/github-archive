[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/legacygitrpc/v1/legacygitrpc_api.proto



## Services

<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcAPI"></a>

### LegacyGitrpcAPI



<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-LegacyGitrpcReader"></a>

#### LegacyGitrpcReader

LegacyGitrpcReader sends an rpc_reader request to the ernicorn.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.legacygitrpc.v1.LegacyGitrpcAPI/LegacyGitrpcReader`

<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcReaderRequest"></a>

##### LegacyGitrpcReaderRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the request to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| ernicorn_request | [ErnicornRequest](#github.spokes.legacygitrpc.v1.ErnicornRequest) |  | ernicorn_request is the request to be sent to the ernicorn. |
| topology_context | [TopologyContext](#github.spokes.legacygitrpc.v1.TopologyContext) |  | This information will be provided as the response to any write operation, so any subsequent read operation can read its own writes, providing our users a causal consistency guarantee. |



<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcReaderResponse"></a>

##### LegacyGitrpcReaderResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| response | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | response from the ernicorn, to be decoded by the Ruby client. |



<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-LegacyGitrpcWriter"></a>

#### LegacyGitrpcWriter

LegacyGitrpcWriter sends an rpc_writer request to the ernicorn.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.legacygitrpc.v1.LegacyGitrpcAPI/LegacyGitrpcWriter`

<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcWriterRequest"></a>

##### LegacyGitrpcWriterRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to scope the request to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| ernicorn_request | [ErnicornRequest](#github.spokes.legacygitrpc.v1.ErnicornRequest) |  | ernicorn_request is the request to be sent to the ernicorn. |
| topology_context | [TopologyContext](#github.spokes.legacygitrpc.v1.TopologyContext) |  | This information will be provided as the response to any write operation, so any subsequent read operation can read its own writes, providing our users a causal consistency guarantee. |



<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcWriterResponse"></a>

##### LegacyGitrpcWriterResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| responses | [WriteServerResponse](#github.spokes.legacygitrpc.v1.WriteServerResponse) | repeated |  |



<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-Bertrpc"></a>

#### Bertrpc

Bertrpc sends a bertrpc request to the ernicorn.
This should only be used by things like build_maint_rpc, where the application really
needs to know about replicas and on-disk paths.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.legacygitrpc.v1.LegacyGitrpcAPI/Bertrpc`

<a name="github.spokes.legacygitrpc.v1.BertrpcRequest"></a>

##### BertrpcRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| host | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | host is the host to send the request to. |
| path | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | path is the on-disk path to scope the request to. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| ernicorn_request | [ErnicornRequest](#github.spokes.legacygitrpc.v1.ErnicornRequest) |  | ernicorn_request is the request to be sent to the ernicorn. |



<a name="github.spokes.legacygitrpc.v1.BertrpcResponse"></a>

##### BertrpcResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| ernicorn_response | [ErnicornResponse](#github.spokes.legacygitrpc.v1.ErnicornResponse) |  |  |



<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-GetCacheKey"></a>

#### GetCacheKey

GetCacheKey returns the cache key for a repository.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.legacygitrpc.v1.LegacyGitrpcAPI/GetCacheKey`

<a name="github.spokes.legacygitrpc.v1.GetCacheKeyRequest"></a>

##### GetCacheKeyRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository used to retrieve the cache key. |
| use_primary | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | use_primary indicates whether we should be using the primary database or can use a replica. |



<a name="github.spokes.legacygitrpc.v1.GetCacheKeyResponse"></a>

##### GetCacheKeyResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| cache_key | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | cache_key is the cache key for the repository. |



<a name="github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-GetCacheKeys"></a>

#### GetCacheKeys

GetCacheKeys returns the cache keys for a list of repositories.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.legacygitrpc.v1.LegacyGitrpcAPI/GetCacheKeys`

<a name="github.spokes.legacygitrpc.v1.GetCacheKeysRequest"></a>

##### GetCacheKeysRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repositories | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) | repeated | repositories are the repositories for which to retrieve the cache keys. |
| use_primary | [bool](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | use_primary indicates whether we should be using the primary database or can use a replica. |



<a name="github.spokes.legacygitrpc.v1.GetCacheKeysResponse"></a>

##### GetCacheKeysResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repositories_with_cache_keys | [RepositoryWithCacheKey](#github.spokes.legacygitrpc.v1.RepositoryWithCacheKey) | repeated | repositories_with_cache_keys are the cache keys and their corresponding repositories. |



<a name="github.spokes.legacygitrpc.v1.StatusCode"></a>

### StatusCode


| Name | Number | Description |
| ---- | ------ | ----------- |
| STATUS_CODE_INVALID | 0 |  |
| STATUS_CODE_OK | 1 |  |
| STATUS_CODE_DEADLINE_EXCEEDED | 2 |  |
| STATUS_CODE_REQUEST_CANCELLED | 3 |  |
| STATUS_CODE_INVALID_REQUEST | 4 |  |
| STATUS_CODE_INVALID_GIT_PATH | 5 |  |
| STATUS_CODE_ERROR_ENCODING_REQUEST | 6 |  |
| STATUS_CODE_ERROR_CONNECTING_TO_ERNICORN | 7 |  |
| STATUS_CODE_ERROR_TALKING_TO_ERNICORN | 8 |  |
| STATUS_CODE_ERROR_PROCESSING_ERNICORN_RESPONSE | 9 |  |


