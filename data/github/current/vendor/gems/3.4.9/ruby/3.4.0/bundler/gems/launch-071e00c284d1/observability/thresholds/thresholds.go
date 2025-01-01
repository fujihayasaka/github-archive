package thresholds

import "time"

const (
	// HTTPAuditLogLatency is the time to serve an HTTP audit log enpoint
	HTTPAuditLogLatency = time.Second * 10

	// HTTPAbuseStatusLatency is the time to serve an HTTP abuse endpoint request
	HTTPAbuseStatusLatency = time.Second * 10

	// HTTPJobStatusLatency is the time to serve an HTTP job status post-back
	// request
	HTTPJobStatusLatency = time.Second * 10

	// HTTPPreJobTokenLatency is the time to serve an HTTP pre-job token endpoint
	// request
	HTTPPreJobTokenLatency = time.Second * 10

	// HTTPRefreshTokenLatency is the time to serve an HTTP refresh-job token endpoint
	// request
	HTTPRefreshTokenLatency = time.Second * 10

	// HTTPRevokeTokenLatency is the time to serve an HTTP revoke-job token endpoint
	// request
	HTTPRevokeTokenLatency = time.Second * 10

	// HTTPRunStatusLatency is the time to serve an HTTP job status post-back
	// request
	HTTPRunStatusLatency = time.Second * 10

	// HTTPTokenCreateLatency is the time to serve an HTTP token endpoint request
	HTTPTokenCreateLatency = time.Second * 10

	// HTTPWebhookLatency is the time to serve an HTTP webhook endpoint request
	HTTPWebhookLatency = time.Millisecond * 50

	// WorkflowQueuedOrgSuccess is the time it takes to queue a workflow run when
	// org creation was necessary
	WorkflowQueuedOrgSuccess = time.Second * 120

	// WorkflowQueuedOrgUnnecessary is the time it takes to queue a workflow run
	// when org creation was not necessary
	WorkflowQueuedOrgUnnecessary = time.Second * 60

	// DefaultExchangeURL latency is the default time it takes to return an authenticated URL
	DefaultExchangeURL = time.Second * 5

	// ExchangeStepLogURL is the time to exchange an authenticated url for a
	// completed step log
	ExchangeStepLogURL = time.Second * 5

	// ExchangeJobLogURL is the time to exchange an url for a completed job log.
	ExchangeJobLogURL = time.Second * 5

	// DeleteArtifact is the time to delete an artifact from Actions Service.
	DeleteArtifact = time.Second * 10

	// DefaultSelfHostedRunners is the time for various self-hosted runners calls.
	DefaultSelfHostedRunners = time.Second * 1

	// DefaultRunnerScaleSets is the time for various runner scale sets calls.
	DefaultRunnerScaleSets = time.Second * 1

	// DefaultArtifactCache is the time for various artifact cache calls.
	DefaultArtifactCache = time.Second * 1

	// DefaultChecks is the time to get all the check steps from a changeId from Actions Service.
	DefaultChecks = time.Second * 10

	// ResourceAcquisition is the time taken to acquire AZP resources.
	ResourceAcquisition = time.Second * 30

	// CreateGitHubToken is the time taken to create a GitHub Access Token.
	CreateGitHubToken = time.Second * 1

	// AuthenticateRequest is the time taken to authenticate an outgoing AZP
	// request.
	AuthenticateRequest = time.Millisecond * 500

	// AuthenticateAsServicePrincipal is the time taken to authenticate as the
	// service principal.
	AuthenticateAsServicePrincipal = time.Millisecond * 500

	// DeleteBuildLogs is the time to delete the logs from Actions Service.
	DeleteBuildLogs = time.Second * 10

	// RunStartDelay is the time from when an event triggers and action, to when launch is notified the first run of the job started
	RunStartDelay = time.Second * 60 * 5

	// RunCompletionDelay is the time from when a run is completed, to when launch is notified the run has completed
	RunCompletionDelay = time.Second * 60

	// HTTPGateStatusLatency is the time to serve an HTTP gate status post-back
	// request
	HTTPGateStatusLatency = time.Second * 10

	// NotifyGate is the time to update gate conclusion in Actions Service
	NotifyGate = time.Second * 10

	// NextGlobalIDLatency is the time it takes to convert legacy global ids to the next global id format
	NextGlobalIDLatency = time.Second * 8
)
