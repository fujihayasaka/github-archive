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
	StableVersion = "v32"
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
	includeActionsYmlAnalysis := flipper.HasCodeScanningActionsYml(ctx, 0, repo)
	setupPrivateRegistryProxy := flipper.HasCodeScanningPrivateRegistry(ctx, 0, repo)

	actions := getActionVersionForRepo(ctx, repo)
	if tl.forceNextVersion || flipper.HasWorkflowUpgradeNextVersion(ctx, repo) {
		return tl.getRenderedWorkflow(NextVersion, actions, includeActionsYmlAnalysis, setupPrivateRegistryProxy)
	}
	return tl.getRenderedWorkflow(StableVersion, actions, includeActionsYmlAnalysis, setupPrivateRegistryProxy)
}

func (tl *Library) GetWorkflowTemplateByVersion(ctx context.Context, repo ts.RepositoryEID, version string) *WorkflowTemplate {
	includeActionsYMLAnalysis := flipper.HasCodeScanningActionsYml(ctx, 0, repo)
	setupPrivateRegistryProxy := flipper.HasCodeScanningPrivateRegistry(ctx, 0, repo)
	actionsVersion := getActionVersionForRepo(ctx, repo)
	return tl.getRenderedWorkflow(version, actionsVersion, includeActionsYMLAnalysis, setupPrivateRegistryProxy)
}

func (tl *Library) getArtifactActionVersion() string {
	// See https://github.com/actions/upload-artifact?tab=readme-ov-file#v4---whats-new
	// v4 is not supported on GHES so we must stay on v3 there,
	// but v3 still uses Node16 so we want to avoid using it on dotcom.
	if tl.useArtifactActionV3 {
		return ArtifactActionVersionV3
	} else {
		return ArtifactActionVersionV4
	}
}

func (tl *Library) getRenderedWorkflow(version string, actionVersion string, includeActionsYMLAnalysis bool, setupPrivateRegistryProxy bool) *WorkflowTemplate {
	return &WorkflowTemplate{
		Version: version,

		defaultNonGitHubHostedRunnerLabel: tl.defaultNonGitHubHostedRunnerLabel,
		codeqlActionVersion:               actionVersion,
		artifactActionVersion:             tl.getArtifactActionVersion(),
		useCustomRegistries:               tl.useCustomRegistries,
		includeActionsYmlAnalysis:         includeActionsYMLAnalysis,
		setupProxy:                        setupPrivateRegistryProxy,
	}
}

func getActionVersionForRepo(ctx context.Context, repo ts.RepositoryEID) string {
	if flipper.HasCodeScanningDefaultSetupCodeqlRC(ctx, repo) {
		return CodeQLActionRCVersion
	}
	return CodeQLActionVersionV3
}
