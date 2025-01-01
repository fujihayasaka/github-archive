package constants

import "time"

const (
	// WorkflowMaxRunTimeDays is used in user visible error messages.
	WorkflowMaxRunTimeDays = 35

	// WorkflowMaxRunTime is the maximum supported workflow run time. The healing job cancels in-progress workflow older than this.
	// Some contributing factors to run completion times:
	// * Environment protection gates can take up to 30 days to open or timeout. https://docs.github.com/en/actions/reference/environments
	// * Workflow jobs can be queued for hours, waiting for an idle self-hosted runner or due to hosted concurrency limits.
	// * A workflow job can run for up to 6 hours on a hosted runner.
	WorkflowMaxRunTime = WorkflowMaxRunTimeDays * time.Hour * 24

	// ActionRunnerStatusSecretDurationHours is used for setting the validity period of status callback URLs.
	// This long duration should be fine since run callback URLs are only valid when runs are in progress.
	// 1 day of padding added for postback processing.
	ActionRunnerStatusSecretDuration = WorkflowMaxRunTime + time.Hour*24

	// CodespacesIntegrationName is the name of the integration that is used to create & manage codespaces.
	CodespacesIntegrationName = "codespaces"
)
