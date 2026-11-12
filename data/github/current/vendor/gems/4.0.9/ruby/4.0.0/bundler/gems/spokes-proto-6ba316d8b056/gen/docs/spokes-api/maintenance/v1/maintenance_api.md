[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/maintenance/v1/maintenance_api.proto



## Services

<a name="github.spokes.maintenance.v1.MaintenanceAPI"></a>

### MaintenanceAPI

MaintenanceAPI contains APIs for maintenance-related operations.

<a name="github.spokes.maintenance.v1.MaintenanceAPI-MaintenanceInfo"></a>

#### MaintenanceInfo

MaintenanceInfo returns maintenance statuses for repository replicas.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.maintenance.v1.MaintenanceAPI/MaintenanceInfo`

<a name="github.spokes.maintenance.v1.MaintenanceInfoRequest"></a>

##### MaintenanceInfoRequest

MaintenanceInfoRequest is a request for maintenance status information.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to get maintenance status for. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request_context provides request-level context. |



<a name="github.spokes.maintenance.v1.MaintenanceInfoResponse"></a>

##### MaintenanceInfoResponse

MaintenanceInfoResponse holds the calculated maintenance statuses for all replicas.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| replicas | [ReplicaMaintenanceStatus](#github.spokes.maintenance.v1.ReplicaMaintenanceStatus) | repeated | replicas contains maintenance status for each replica host. |



