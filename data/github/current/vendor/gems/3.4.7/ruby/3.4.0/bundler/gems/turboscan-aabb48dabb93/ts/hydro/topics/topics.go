// Package topics provides a list of Hydro topics that Turboscan uses both as consumer and producer.
package topics

const (
	// Turboscan writes to this topic
	AlertEvent = "cp1-iad.ingest.turboscan.v0.AlertEvent"

	// Turboscan reads from this topic. It carries a message whenever a new analysis file has been uploaded.
	NewAnalysis = "code_scanning.v0.NewAnalysis"
	// Turboscan writes to this topic whenever it has successfully processed an analysis
	ProcessedAnalysis = "code_scanning.v0.ProcessedAnalysis"
	// Turboscan writes to this topic whenever it has failed to process an analysis
	FailedAnalysis = "code_scanning.v0.FailedAnalysis"

	// Turboscan writes to this topic whenever alerts are upserted
	InsightsEntityBatch = "github.security_center.v0.InsightsEntityBatch"

	// Turboscan reads from this topic. It carries a message whenever there is a change to repository metadata.
	// (only for repositories belonging to orgs)
	RepoUpdate = "github.security_center.v1.SecurityFeatureRepoUpdate"

	// Turboscan reads from this topic. The WorkflowEventProcessor reacts to workflow conclusion events
	// for managed analysis
	WorkflowExecution   = "cp1-iad.ingest.github.actions.v0.WorkflowExecution"
	ActionsComputeUsage = "github.actions.v0.ComputeUsage"

	// Turboscan reads from this topic. It carries a message for every push event to a repo.
	PostReceive = "cp1-iad.ingest.github.v1.PostReceive"

	// Turboscan reads from this topic. It carries a message for every pull request synchronization event.
	PullRequestSynchronize = "github.v1.PullRequestSynchronize"

	// Turboscan reads from this topic. It carries a message for every pull request create event.
	PullRequestCreate = "cp1-iad.ingest.github.v1.PullRequestCreate"

	// Turboscan writes to this topic whenever Code Scanning is enabled/disabled.
	EnablementEvent = "code_scanning.v0.EnablementEvent"

	// Turboscan writes to this topic. It carries a message for every CodeQL diagnostic telemetry event.
	CodeqlTelemetryMessage = "code_scanning.v0.CodeqlTelemetryMessage"

	// Turboscan writes to this topic. It carries a message for every CodeQL metric result.
	CodeqlMetricResult = "code_scanning.v0.CodeqlMetricResult"

	// ManagedAnalysesExpectedCodeqlRun is written by Turboscan. It carries a message for every
	// CodeQL run enqueued by the default setup pipeline.
	ManagedAnalysesExpectedCodeqlRun = "code_scanning.v0.ManagedAnalysesExpectedCodeqlRun"

	// Turboscan writes to this topic. It carries a message when a CodeQL run is created or updated.
	CodeqlRun = "turboscan.v0.CodeqlRun"

	// Turboscan writes to this topic. It carries a event when an alert is fixed with an autofix
	AutofixFixedAlertEvent = "code_scanning.v0.AutofixFixedAlertEvent"

	// Turboscan writes to this topic. It carries a event about autofix usages for a SuggestedFixAlert
	AutofixUsageEvent = "code_scanning.v0.AutofixUsageEvent"

	// Turboscan writes to this topic when an autofix generation attempt is triggered
	AutofixGenerateEvent = "code_scanning.v0.AutofixGenerateEvent"

	// Turboscan writes to this topic when an autofix generation is completed
	AutofixGenerationCompletedEvent = "code_scanning.v0.AutofixGenerationCompleted"

	// Turboscan writes to this topic. It carries a message for default setup failed validation run annotations.
	WorkflowRunAnnotation = "code_scanning.v0.DefaultSetupAnnotations"

	// Turboscan writes to this topic when a new alert link is created.
	AlertLinkCreate = "code_scanning.v0.AlertLinkCreate"

	// Turboscan writes to this topic when an alert link is updated, such as when the link changes from a ref to a PR.
	AlertLinkUpdate = "code_scanning.v0.AlertLinkUpdate"

	// Turboscan uses this topic to publish a generated fix for dependabot
	DependabotAutofixResult = "code_scanning.v0.DependabotAutofixResult"

	// Turboscan writes to this topic to add information to the audit log
	AuditEntry = "cp1-iad.ingest.audit_log.v2.AuditEntry"

	// Turboscan writes to these Autofix outcomes to track Autofix failures.
	AutofixInvalidOutcome = "code_scanning.v0.AutofixInvalidOutcome"
	AutofixErrorOutcome   = "code_scanning.v0.AutofixErrorOutcome"
)
