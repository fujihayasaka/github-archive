[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/backups/v1/backups_api.proto



## Services

<a name="github.spokes.backups.v1.BackupsAPI"></a>

### BackupsAPI



<a name="github.spokes.backups.v1.BackupsAPI-PerformBackup"></a>

#### PerformBackup



##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.backups.v1.BackupsAPI/PerformBackup`

<a name="github.spokes.backups.v1.PerformBackupRequest"></a>

##### PerformBackupRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | The repository to backup. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | The request context. |
| parent_repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | The parent repository ID, if any. |



<a name="github.spokes.backups.v1.PerformBackupResponse"></a>

##### PerformBackupResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| error_reason | [BackupErrorReason](#github.spokes.backups.v1.BackupErrorReason) |  | The reason for an error that was encountered, if any. |
| error_message | [string](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | A message describing any errors in more detail. |



<a name="github.spokes.backups.v1.BackupErrorReason"></a>

### BackupErrorReason


| Name | Number | Description |
| ---- | ------ | ----------- |
| BACKUP_ERROR_REASON_INVALID | 0 | No reason set (invalid). |
| BACKUP_ERROR_REASON_NO_ERROR | 1 | No error incurred (operation successful) |
| BACKUP_ERROR_REASON_CHECKSUM_MISMATCH | 2 | The checksum of the repository changed during the backup. |
| BACKUP_ERROR_REASON_CONCURRENT_BACKUP_RACE_DETECTED | 3 | Another backup is already in progress. |


