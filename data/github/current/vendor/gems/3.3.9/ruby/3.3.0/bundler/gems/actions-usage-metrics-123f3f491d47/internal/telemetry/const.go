package telemetry

const (
	// Http.
	HttpConnections_StatsKey     = "actions_usage_metrics.http.connections"
	HttpDurationKey              = "http.duration"
	HttpErrorKey                 = "http.error"
	HttpMethodKey                = "http.method"
	HttpRequestCount_StatsKey    = "actions_usage_metrics.http.request.count"
	HttpRequestDuration_StatsKey = "actions_usage_metrics.http.request.duration"
	HttpResponseCount_StatsKey   = "actions_usage_metrics.http.response.count"
	HttpResponseSize_StatsKey    = "actions_usage_metrics.http.response.size"
	HttpSizeKey                  = "http.size"
	HttpStartTimeKey             = "http.start_time"
	HttpStatusCodeKey            = "http.status_code"
	HttpStatusKey                = "http.status"
	HttpStatusTextKey            = "http.status_text"
	HttpTargetKey                = "http.target"

	// Kusto.
	Kusto_KustoDelay_StatsKey        = "actions_usage_metrics.kusto.kusto_delay"
	Kusto_MaterializedDelay_StatsKey = "actions_usage_metrics.kusto.materialized_delay"
	Kusto_TotalDelay_StatsKey        = "actions_usage_metrics.kusto.total_delay"
	KustoTableNameTag                = "table.name"

	// Export.
	ExportCount_StatsKey                  = "actions_usage_metrics.export.count"
	ExportDuration_StatsKey               = "actions_usage_metrics.export.duration"
	ExportGetStatusCount_StatsKey         = "actions_usage_metrics.export.get_status.count"
	ExportGetStatusDuration_StatsKey      = "actions_usage_metrics.export.get_status.duration"
	ExportGetDownloadURLCount_StatsKey    = "actions_usage_metrics.export.get_download_url.count"
	ExportGetDownloadURLDuration_StatsKey = "actions_usage_metrics.export.get_download_url.duration"
	ExportStatusKey                       = "export.status"
	ExportTypeKey                         = "export.type"
	ExportUpdateStatusCount_StatsKey      = "actions_usage_metrics.export.update_status.count"
	ExportUpdateStatusDuration_StatsKey   = "actions_usage_metrics.export.update_status.duration"

	// Statuses.
	StatusKey     = "status"
	FailedStatus  = "failed"
	SuccessStatus = "success"

	// Other.
	DatadogEndpointKey = "gh.metrics.endpoint"
	FilterKey          = "gh.actions.usage_metrics.filter_key"
	FilterOperatorKey  = "gh.actions.usage_metrics.filter_operator"
	GitHubRequestIDKey = "gh.request_id"

	// Twirp.
	TwirpRequests_StatsKey = "actions_usage_metrics.twirp.requests"

	//  Repos
	ReposFindByIdCount_StatsKey        = "actions_usage_metrics.repositories.find_by_id.count"
	ReposFindNil_StatsKey              = "actions_usage_metrics.repositories.find_by_id.nil_repo"
	ReposFindByIdDuration_StatsKey     = "actions_usage_metrics.repositories.find_by_id.duration"
	ReposFindByIdMissingCount_StatsKey = "actions_usage_metrics.repositories.find_by_id.missing.count"
	ReposGetAllDuration_StatsKey       = "actions_usage_metrics.repositories.get_all.duration"

	// OTel Keys
	OTelKeyExportId          = "gh.actions.usage_metrics.export_id"
	OTelKeyOwnerId           = "gh.actions.usage_metrics.owner_id"
	OTelKeyScopeRepoId       = "gh.actions.usage_metrics.scope_repository_id"
	OTelKeyExportType        = "gh.actions.usage_metrics.export_type"
	OTelKeyDuration          = "gh.actions.usage_metrics.duration"
	OTelKeyBytesTransferred  = "gh.actions.usage_metrics.export_bytes_transferred"
	OTelKeyBlobName          = "gh.actions.usage_metrics.export_blob_name"
	OTelKeyStatus            = "gh.actions.usage_metrics.export_status"
	OTelKeyName              = "gh.actions.usage_metrics.unsupported_parameter_name"
	OTelKeyType              = "gh.actions.usage_metrics.unsupported_parameter_type"
	OTelKeyQuery             = "gh.actions.usage_metrics.kusto_query"
	OTelKeyParams            = "gh.actions.usage_metrics.kusto_query_parameters"
	OTelKeyTableOrView       = "gh.actions.usage_metrics.kusto_table"
	OTelKeyKustoDelay        = "gh.actions.usage_metrics.kusto_delay"
	OTelKeyMaterializedDelay = "gh.actions.usage_metrics.kusto_materialized_delay"
	OTelKeyTotalDelay        = "gh.actions.usage_metrics.kusto_total_delay"
	OTelKeyRepoId            = "gh.actions.usage_metrics.repository_id"
	OTelKeyLength            = "gh.actions.usage_metrics.count"
	OTelKeyMeta              = "gh.actions.usage_metrics.twirp_error_metadata"
	OTelKeyTwirpError        = "gh.actions.usage_metrics.twirp_error"
	OtelHttpSize             = "gh.actions.usage_metrics.http_size"
	OtelHttpStartTime        = "gh.actions.usage_metrics.http.start_time"
	OtelHttpStatusCode       = "gh.actions.usage_metrics.http_status_code"
	OtelHttpStatus           = "gh.actions.usage_metrics.http.status"
	OtelHttpStatusText       = "gh.actions.usage_metrics.http.status_text"
	OtelHttpTarget           = "gh.actions.usage_metrics.http_target"
	OtelHttpDuration         = "gh.actions.usage_metrics.http_duration"
	OtelHttpError            = "gh.actions.usage_metrics.http.error"
	OtelHttpMethod           = "gh.actions.usage_metrics.http_method"
)
