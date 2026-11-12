[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/repositories/v2/repositories_api.proto



## Services

<a name="github.spokes.repositories.v2.RepositoriesAPI"></a>

### RepositoriesAPI

RepositoriesAPI contains APIs for repository related operations.

<a name="github.spokes.repositories.v2.RepositoriesAPI-GetRepositoryMetadata"></a>

#### GetRepositoryMetadata

GetRepositoryMetadata provides repository metadata, including
the hash algorithm and ref format.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.repositories.v2.RepositoriesAPI/GetRepositoryMetadata`

<a name="github.spokes.repositories.v2.GetRepositoryMetadataRequest"></a>

##### GetRepositoryMetadataRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| (oneof target) repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to get metadata for. |
| (oneof target) network | [github.spokes.types.v1.Network](../../types/v1/repository.md#github.spokes.types.v1.Network) |  | network is the network to get metadata for. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.repositories.v2.GetRepositoryMetadataResponse"></a>

##### GetRepositoryMetadataResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| hash_algorithm | [github.spokes.types.v1.HashAlgorithm](../../types/v1/hash_algorithm.md#github.spokes.types.v1.HashAlgorithm) |  | hash_algorithm is the main hash algorithm in use for this repository or network. |
| ref_format | [github.spokes.types.v1.RefFormat](../../types/v1/ref_format.md#github.spokes.types.v1.RefFormat) |  | ref_format is the ref format in use for this repository or network. |



