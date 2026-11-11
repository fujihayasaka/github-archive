[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/repositories/v1/replica_item.proto



## Types

<a name="github.spokes.repositories.v1.ReplicaItem"></a>

### ReplicaItem
ReplicaItem contains information about a replica of a repository.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| ip | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>ip is the ip address of the replica.</p> |
| absolute_path | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>absolute_path is the path for the repository on disk.</p> |
| host_name | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | <p>name of the host that holds the replica. NOTE: only use this field to match up the replicas (like a primary key), but not for anything else.</p> |
| route_type | [ReplicaType](#github.spokes.repositories.v1.ReplicaType) |  | <p>replica type indicates how a 'git push' should use this replica.</p> |





<a name="github.spokes.repositories.v1.ReplicaType"></a>

### ReplicaType


| Name | Number | Description |
| ---- | ------ | ----------- |
| REPLICA_TYPE_INVALID | 0 | This may be used if the type is not known. |
| REPLICA_TYPE_NOERROR | 1 | Equivalent to "noerror" from gitauth. This is returned, for example, when a replica is non-voting or has an unexpected checksum. |
| REPLICA_TYPE_NORMAL | 2 | Equivalent to no value from gitauth. |


