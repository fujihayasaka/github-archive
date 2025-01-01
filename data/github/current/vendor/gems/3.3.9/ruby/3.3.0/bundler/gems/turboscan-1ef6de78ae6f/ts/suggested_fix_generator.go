package ts

import (
	"context"
)

type ThrottlerWorkload uint8

const (
	ThrottlerWorkload_HIGH ThrottlerWorkload = iota
	ThrottlerWorkload_LOW
)

func (workload ThrottlerWorkload) String() string {
	switch workload {
	case ThrottlerWorkload_HIGH:
		return "high_priority"
	case ThrottlerWorkload_LOW:
		return "low_priority"
	default:
		return "invalid"
	}
}

func (workload ThrottlerWorkload) ProcessedMetric() string {
	return "generate_suggested_fixes_job.processed"
}

func (workload ThrottlerWorkload) StateChangeDurationMetric() string {
	return "generate_suggested_fixes_job.sfa_state_change"
}

type TransientError struct {
	Err error
}

func (e *TransientError) Error() string {
	return e.Err.Error()
}

func (e *TransientError) Unwrap() error {
	return e.Err
}

type FixGenerator interface {
	// For Code Scanning Autofix
	GenerateFix(
		ctx context.Context,
		tool ToolName,
		toolVersion string,
		sfa *SuggestedFixAlert,
		proximaEnv bool,
		downloadFunc DownloadFilesFunc,
		userID uint64, // ID of the user that requests the fix
		workload ThrottlerWorkload,
	) (GenerateFixResult, error)

	// For Dependabot Autofix
	GenerateDependabotFix(
		ctx context.Context,
		sarif string,
		filePaths []string,
		downloadFunc DownloadFilesFunc,
		repoID RepositoryEID,
		proximaEnv bool,
	) (GenerateFixResult, error)
}

type DownloadFilesFunc func(ctx context.Context, filepath string) ([]byte, error)

type GenerateFixResult struct {
	SuggestedFixAlertState SuggestedFixAlertState
	SuggestedFix           *SuggestedFix
}
