package telemetry

const (
	// ---------------------------------------------------------------------------------------------
	// Metric Name constants.

	// EnabledDurationMetricName is the name of the metric for enabled check duration
	EnabledDurationMetricName string = "vexi.is_enabled.duration"
	// ErrorCountMetricName is the name of the error count metric.
	ErrorCountMetricName string = "vexi.error_count"

	// HydroAdapterStartupDurationMetricName is the name of the startup duration metric for the hydro adapter.
	HydroAdapterStartupDurationMetricName string = "vexi.hydro_adapter.start.duration"

	// HydroAdapterCacheRedinessDurationMetricName is the name of the cache readiness duration metric.
	HydroAdapterCacheRedinessDurationMetricName string = "vexi.hydro_adapter.cache.readiness.duration"

	// HydroAdapterUpdateSuccess is the name of the metric for the hydro adapter update success.
	HydroAdapterUpdateSuccess string = "vexi.hydro_adapter.update.success"

	// HydroAdapterStartFailed is the name of the metric for the hydro adapter start failure during resilient start. The retryable tag indicates if the failure is retryable.
	HydroAdapterStartFailed string = "vexi.hydro_adapter.start.failed"

	// HydroAdapterResilientStartDurationMetric is the name of the metric for the resilient start duration in hydro adapter.
	HydroAdapterResilientStartDurationMetric = "vexi.hydro_adapter.resilient_start.duration"

	// HydroAdapterResilientStartBackgroundDurationMetricName is the name of the metric for the background startup duration in resilient start.
	HydroAdapterResilientStartBackgroundDurationMetricName string = "vexi.hydro_adapter.resilient_start.background.duration"

	// HydroAdapterResilientStartTimeout is the name of the metric for the hydro adapter start timeout.
	HydroAdapterResilientStartTimeout string = "vexi.hydro_adapter.resilient_start.timeout"

	// VexiEmptyFeatureFlagInputMetricName is the name of the metric to indicate empty feature flag name was passed to an enabled check.
	VexiEmptyFeatureFlagInputMetricName string = "vexi.is_enabled.empty_feature_flag_input.count"

	// PersistentHostAdapterNoFileCacheCountName is the name of a count of the a cache file not being present when we start the service
	PersistentHostAdapterNoFileCacheCountName string = "vexi.persistent_host_adapter.cache.file.no_file.count"

	// PersistentHostAdapterEnvironmentOverrideMetricName is the name of the metric for the vexi persistent cache environment override.
	PersistentHostAdapterEnvironmentOverrideMetricName string = "vexi.persistent_host_adapter.cache.environment_override"

	// PersistentHostAdapterEnvironmentOverrideCountName is the name of the metric for the vexi persistent cache environment override count.
	PersistentHostAdapterEnvironmentOverrideCountName string = "vexi.persistent_host_adapter.cache.environment_override.count"

	// PersistentHostAdapterCacheSerializationDurationMetricName is the name of the metric for the vexi persistent cache serialization duration.
	PersistentHostAdapterCacheSerializationDurationMetricName string = "vexi.persistent_host_adapter.cache.serialization.duration"

	// PersistentHostAdapterCacheLoadDurationMetricName is the name of the metric for the vexi persistent cache load duration.
	PersistentHostAdapterCacheLoadDurationMetricName string = "vexi.persistent_host_adapter.cache.load.duration"

	// PersistentHostAdapterResilientStartDurationMetricName is the name of the metric for the vexi persistent host adapter resilient start duration.
	PersistentHostAdapterResilientStartDurationMetricName string = "vexi.persistent_host_adapter.resilient_start.duration"

	// VexiEnabledCheckErrorMetricName is the name of the metric for errors during an enabled check.
	VexiEnabledCheckErrorMetricName string = "vexi.enabled_check.error"

	// ---------------------------------------------------------------------------------------------
	// Stats tag constants.

	// ClientNameTag is the tag name for the client name related to the metric emitted.
	ClientNameTag = "vexi.client.name"

	// AdapterNameTagName is the tag name for the adapter name related to the metric emitted.
	AdapterNameTagName string = "adapter_name"

	// ErrorCauseTagName is the tag/field name for the error cause metric/log.
	ErrorCauseTagName string = "cause"

	// EnabledResultTag indicates if the Enabled method resulted in a true or false.
	EnabledResultTag = "gh.vexi.is_enabled.result"

	// VexiVersionTagName is the tag name for the vexi version related to the metric emitted.
	VexiVersionTagName string = "vexi_version"

	// LegacyAppNameTagName is the tag name for the app name related to the metric emitted.
	// Once all services are using the latest version of vexi, this should be removed.
	LegacyAppNameTagName string = "app_name"

	// AppNameTagName is the tag name for the app name related to the metric emitted.
	AppNameTagName string = "gh.vexi.app_name"

	// CacheName is the name of the feature cache
	CacheName string = "cache_name"

	// EmptyActorsPassedTag is the tag name for indicating whether empty actors were passed to the feature flag check.
	EmptyActorsPassedTag string = "empty_actors_passed"

	// FeatureFlagTag is the tag name for the name of the feature flag.
	FeatureFlagTag = "feature_flag.key"

	// MethodTag is the tag name for the method that was called.
	MethodTag = "gh.vexi.method"

	// SegmentTag is the tag name for the name of the segment.
	SegmentTag = "segment.key"

	// ---------------------------------------------------------------------------------------------
	// ResultReason constants

	// ResultReason indicates the reason for the result of the Enabled method.
	// Values should be in line with the ruby client https://github.com/github/feature-management-client-ruby/blob/main/generated/vexi/lib/vexi/client.rb
	ResultReason = "result_reason"

	// ReasonAllChecksFalse is the tag name for indicating whether all checks were false used in the ResultReason tag.
	ReasonAllChecksFalse string = "all_checks_false"

	// ReasonNotFound is the tag name for indicating whether the feature flag was not found used in the ResultReason tag.
	ReasonNotFound string = "not_found"

	// ReasonFullyEnabled is the tag name for indicating whether the feature flag was fully enabled used in the ResultReason tag.
	ReasonFullyEnabled string = "fully_enabled"

	// ReasonPercentageOfCalls is the tag name for indicating whether the feature flag was enabled for a percentage of calls used in the ResultReason tag.
	ReasonPercentageOfCalls string = "percentage_of_calls"

	// ReasonPercentageOfActors is the tag name for indicating whether the feature flag was enabled for a percentage of actors used in the ResultReason tag.
	ReasonPercentageOfActors string = "percentage_of_actors"

	// ReasonActorMatch is the tag name for indicating whether the feature flag was enabled for a specific actor used in the ResultReason tag.
	ReasonActorMatch string = "actor_match"

	// ReasonEvaluationCancelled is the tag name for indicating whether the feature flag evaluation was cancelled used in the ResultReason tag.
	ReasonEvaluationCancelled string = "cancelled"

	// ReasonEvaluationFailed is the tag name for indicating whether the feature flag evaluation failed used in the ResultReason tag.
	ReasonEvaluationFailed string = "error"

	// ReasonCustomGate is the tag name for indicating whether the feature flag was enabled for a custom fate used in the ResultReason tag.
	ReasonCustomGate string = "custom_gate"

	// ReasonFeatureFlagNameEmpty is the tag name for indicating that the feature flag name was required but not provided used in the ResultReason tag.
	ReasonFeatureFlagNameEmpty string = "feature_flag_name_empty"

	// ReasonAdapterNotReady is the tag name for indicating that the adapter is not ready used in the ResultReason tag.
	ReasonAdapterNotReady string = "adapter_not_ready"

	// ReasonUnknownError is the tag name for indicating an unknown error occurred used in the ResultReason tag.
	ReasonUnknownError string = "unknown_error"

	// ---------------------------------------------------------------------------------------------
	// Log field constants.

	// AdapterNameFieldName is the log field for the adapter name.
	AdapterNameFieldName string = "gh.vexi.adapter.name"

	// CustomGateEvaluatorNameFieldName is the log field name for the custom gate evaluator name.
	CustomGateEvaluatorNameFieldName string = "gh.vexi.custom_gate_evaluator.name"

	// CustomGateNameFieldName is the log field name for the custom gate name.
	CustomGateNameFieldName string = "gh.vexi.custom_gate.name"

	// VexiContextFieldName is the log field name for the function that is currently running in Vexi. E.g. "is_enabled", etc.
	VexiContextFieldName string = "gh.vexi.context"

	// VexiVersionFieldName is the log field for the vexi version.
	VexiVersionFieldName string = "gh.vexi.version"

	// FeatureFlagFieldName is the log field for the feature flag name.
	FeatureFlagFieldName = "feature_flag.key"

	// SegmentFieldName is the log field for the segment name.
	SegmentFieldName = "gh.vexi.segment.key"

	// OwningServiceField is the log field for the owning service name.
	OwningServiceField = "gh.vexi.owning_service"

	// AppNameFieldName is the log field for the app name.
	AppNameFieldName = "gh.vexi.app_name"

	// HydroAdapterStartupDurationFieldName is the log field for the duration of the hydro adapter startup.
	HydroAdapterStartupDurationFieldName = "gh.vexi.adapter.hydro.startup.duration"

	// ClientNameFieldName is the log field for the client name.
	ClientNameFieldName = "gh.vexi.client.name"

	// EmptyOrNilActorsIndexFieldName is the log field that indicates the index of the empty or nil actors passed to the feature flag check.
	EmptyOrNilActorsIndexFieldName = "gh.vexi.empty_or_nil_actors.index"

	// SampleRate is the log field that, when present, indicates that metrics are samled at the specified rate
	SampleRate = "gh.vexi.sample_rate"
)
