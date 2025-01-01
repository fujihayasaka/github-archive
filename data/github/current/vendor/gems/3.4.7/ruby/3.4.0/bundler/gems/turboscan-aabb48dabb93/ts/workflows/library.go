package workflows

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
)

// Workflow template versions used in production:
// StableVersion is the stable version
// NextVersion is the next version to be released
// The next version is used on repositories that have the FF enabled
// therefore NextVersion will not be enabled on GHES releases.
//
// When both versions are the same, there is no next version
// being released.
const (
	StableVersion = "v35"
	NextVersion   = StableVersion
)

// Library is a collection of workflow templates and provides
// utility methods for selecting the correct template for a given
// repository and Turboscan instance.
type Library struct {
	defaultNonGitHubHostedRunnerLabel string
	forceNextVersion                  bool
	useArtifactActionV3               bool
	useCustomRegistries               bool
}

func NewLibrary(opts ...LibraryOption) *Library {
	l := &Library{}
	for _, opt := range opts {
		opt(l)
	}
	return l
}

type LibraryOption func(*Library)

func WithDefaultNonGHHostedRunnerLabel(runnerLabel string) LibraryOption {
	return func(l *Library) {
		l.defaultNonGitHubHostedRunnerLabel = runnerLabel
	}
}

func WithForceNextVersion(v bool) LibraryOption {
	return func(l *Library) {
		l.forceNextVersion = v
	}
}

func WithArtifactActionV3(useArtifactActionV3 bool) LibraryOption {
	return func(l *Library) {
		l.useArtifactActionV3 = useArtifactActionV3
	}
}

func WithCustomRegistries(useCustomRegistries bool) LibraryOption {
	return func(l *Library) {
		l.useCustomRegistries = useCustomRegistries
	}
}

func (tl *Library) GetVersion(ctx context.Context, repo ts.RepositoryEID) string {
	if tl.forceNextVersion || flipper.HasWorkflowUpgradeNextVersion(ctx, repo) {
		return NextVersion
	}
	return StableVersion
}

// GetWorkflowTemplate will return the template that should be used for the given repository.
// Use this method unless you are sure you need to use GetLatestVersion or GetNextVersion.
func (tl *Library) GetWorkflowTemplate(ctx context.Context, repo ts.RepositoryEID) *WorkflowTemplate {
	version := StableVersion
	if tl.forceNextVersion || flipper.HasWorkflowUpgradeNextVersion(ctx, repo) {
		version = NextVersion
	}

	return tl.GetWorkflowTemplateByVersion(ctx, repo, version)
}

// GetWorkflowTemplateByVersion returns a new WorkflowTemplate with the given version
func (tl *Library) GetWorkflowTemplateByVersion(ctx context.Context, repo ts.RepositoryEID, version string) *WorkflowTemplate {
	var inputs TemplateInputs

	// Set repository-specific settings controlled via FFs
	if flipper.HasCodeScanningDefaultSetupCodeqlRC(ctx, repo) {
		inputs.codeqlActionVersion = CodeQLActionRCVersion
	} else {
		inputs.codeqlActionVersion = CodeQLActionVersionV3
	}
	inputs.IncludeCCRAnalysis = flipper.HasSuggestedFixIncludeCCRQuality(ctx, flipper.UnknownOrg, repo)
	inputs.ubuntu2204Runner = flipper.HasCodeScanningUbuntu2204Runner(ctx, flipper.UnknownOrg, repo)

	// Set library-level settings
	inputs.runnerLabel = tl.defaultNonGitHubHostedRunnerLabel
	if tl.useArtifactActionV3 {
		inputs.artifactActionVersion = ArtifactActionVersionV3
	} else {
		inputs.artifactActionVersion = ArtifactActionVersionV4
	}
	inputs.CustomRegistries = tl.useCustomRegistries

	return &WorkflowTemplate{
		Version:     version,
		partialData: inputs,
	}
}
