package events

const (
	// JobExecutionEvent refers to a completed job run
	JobExecutionEvent = "job_execution"

	// WorkflowExecutionEvent refers to a completed workflow run
	WorkflowExecutionEvent = "workflow_execution"

	// ReputationScoreChangeEvent refers to the change in a reputation score
	ReputationScoreChangeEvent = "reputation_score_change"

	// WorkflowChangeEvent refers to an actions workflow file changing
	WorkflowChangeEvent = "workflow_change"

	// WorkflowCancelRequest is sent on a user requesting a cancellation
	WorkflowCancelRequest = "workflow_cancel_request"

	// WorkflowUpdate is sent when a workflow run is updated
	WorkflowUpdate = "workflow_update"

	// AbuseDetectionStatusEvent refers to the detection of potenital actions abusers
	AbuseDetectionStatusEvent = "abuse_detection_status_event"

	// QueueRunEvent refers to the result of a queue run API call.
	QueueRunEvent = "queue_run_event"

	// AuditLogEvent is an event to be added to the audit log
	AuditLogEvent = "audit_log_event"

	// CacheUsageEvent refers to the update event for cache usage
	CacheUsageEvent = "cache_usage_event"
)
