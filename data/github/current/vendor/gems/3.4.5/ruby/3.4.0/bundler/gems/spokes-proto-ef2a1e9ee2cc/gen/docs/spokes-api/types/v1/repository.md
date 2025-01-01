[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/types/v1/repository.proto



## Types

<a name="github.spokes.types.v1.Repository"></a>

### Repository
Repository is the identifier of a Git repository.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| type | [Repository.Type](#github.spokes.types.v1.Repository.Type) |  | <p>type is the type identifier of the repository. (required)</p> |
| id | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>is is the numerical identifier of the repository. (required)</p> |





<a name="github.spokes.types.v1.Repository.Type"></a>

### Repository.Type


| Name | Number | Description |
| ---- | ------ | ----------- |
| TYPE_INVALID | 0 | TYPE_INVALID is present because enums require a zero value. This should never be used. |
| TYPE_REPOSITORY | 1 | TYPE_REPOSITORY is used if the repository is a normal Git repository. |
| TYPE_WIKI | 2 | TYPE_WIKI is used if the repository is a wiki Git repository. |
| TYPE_GIST | 3 | TYPE_GIST is used if the repository is a Gist. |


