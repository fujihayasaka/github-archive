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

type CapiIntegrationType uint8

const (
	CapiIntegrationCodeScanning CapiIntegrationType = iota
	CapiIntegrationDependabot
	CapiIntegrationCCR
)

func (c CapiIntegrationType) String() string {
	switch c {
	case CapiIntegrationCodeScanning:
		return "code_scanning"
	case CapiIntegrationDependabot:
		return "dependabot"
	case CapiIntegrationCCR:
		return "ccr"
	default:
		return "invalid"
	}
}

type CapiInteraction struct {
	ID   string
	Type string
}

type FixGenerator interface {
	// For Code Scanning Autofix
	GenerateFix(
		ctx context.Context,
		tool ToolName,
		toolVersion string,
		sfa *SuggestedFixAlert,
		downloadFunc DownloadFilesFunc,
		userID uint64, // ID of the user that requests the fix
		workload ThrottlerWorkload,
		isCampaign bool,
	) (GenerateFixResult, error)

	// For Dependabot Autofix
	GenerateDependabotFix(
		ctx context.Context,
		sarif string,
		filePaths []string,
		downloadFunc DownloadFilesFunc,
		repoID RepositoryEID,
		integration CapiIntegrationType,
		interaction CapiInteraction,
	) (GenerateFixResult, error)
}

type DownloadFilesFunc func(ctx context.Context, filepath string) ([]byte, error)

type GenerateFixResult struct {
	SuggestedFixAlertState SuggestedFixAlertState
	SuggestedFix           *SuggestedFix
}
