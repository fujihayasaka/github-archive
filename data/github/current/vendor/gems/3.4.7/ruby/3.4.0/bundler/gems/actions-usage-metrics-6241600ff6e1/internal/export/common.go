package export

import (
	"time"

	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

const (
	BlobStatusMetadataKey = "Status"

	// Blob expires after 1 hour.
	BlobExpiryTimeRelativeToNow = time.Duration(1) * time.Hour

	// Consider the export failed after this duration without an update.
	ExportTimeoutAfterDuration = time.Duration(20) * time.Second

	// SAS token starts 5 minutes before now to account for clock skew.
	SasTokenStartTimeRelativeToNow = -time.Duration(5) * time.Minute

	// SAS token expires after 10 minutes.
	SasTokenEndTimeRelativeToNow = time.Duration(10) * time.Minute

	// Update the export status every 5 seconds.
	UpdateStatusEveryDuration = time.Duration(5) * time.Second

	// Container names.
	ExportContainerName       = "export"
	ExportStatusContainerName = "export-status"
)

func getRunnerTypeDisplayString(runnerType proto.RunnerType) string {
	switch runnerType {
	case proto.RunnerType_RUNNER_TYPE_HOSTED:
		return "hosted"
	case proto.RunnerType_RUNNER_TYPE_SELF_HOSTED:
		return "self-hosted"
	case proto.RunnerType_RUNNER_TYPE_HOSTED_LARGER:
		return "hosted-larger"
	default:
		return "unknown"
	}
}

func getRunnerRuntimeDisplayString(runnerRuntime proto.RunnerRuntime) string {
	switch runnerRuntime {
	case proto.RunnerRuntime_RUNNER_RUNTIME_LINUX:
		return "linux"
	case proto.RunnerRuntime_RUNNER_RUNTIME_WINDOWS:
		return "windows"
	case proto.RunnerRuntime_RUNNER_RUNTIME_MACOS:
		return "macos"
	default:
		return "unknown"
	}
}
