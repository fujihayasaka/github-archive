package workflows_test

import (
	"context"
	"flag"
	"fmt"
	"os"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/workflows"
	"github.com/stretchr/testify/require"
)

// We run all tests against the next version because this is typically the same
// as the current version. When introducing a new next, it makes sense to run
// existing tests against it to ensure that the new version is compatible.
// If you want to run tests against the stable version, change the following
// line to use workflows.StableVersion.
var defaultWT = workflows.NewLibrary().GetWorkflowTemplateByVersion(context.Background(), 0, workflows.NextVersion)

// For self-hosted runners, we need to specify the runner labels in the library.
var selfhostedWT = workflows.NewLibrary(workflows.WithDefaultNonGHHostedRunnerLabel("code-scanning")).GetWorkflowTemplateByVersion(context.Background(), 0, workflows.NextVersion)

var artifactActionV3WT = workflows.NewLibrary(workflows.WithArtifactActionV3(true)).GetWorkflowTemplateByVersion(context.Background(), 0, workflows.NextVersion)

var customRegistriesWT = workflows.NewLibrary(workflows.WithCustomRegistries(true)).GetWorkflowTemplateByVersion(context.Background(), 0, workflows.NextVersion)

func TestRenderVersions(t *testing.T) {
	// This test renders the current and next versions of the workflow templates
	// and ensures that they are not empty, and versions can be rendered
	// (i.e. there is no predicate used in the template that cannot be resolved).
	lib := workflows.NewLibrary()
	stable := lib.GetWorkflowTemplateByVersion(context.Background(), 0, workflows.StableVersion)
	next := lib.GetWorkflowTemplateByVersion(context.Background(), 0, workflows.NextVersion)

	s, err := stable.CodeQLWorkflow(&ts.CodeqlConfig{})
	require.NoError(t, err)
	require.NotEmpty(t, s)

	s, err = next.CodeQLWorkflow(&ts.CodeqlConfig{})
	require.NoError(t, err)
	require.NotEmpty(t, s)
}

func TestCodeQL_EnterpriseIncludesRegistry(t *testing.T) {
	created, err := customRegistriesWT.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages: []string{"javascript"},
	})
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/enterprise-workflow-with-registry.expected")
}

func TestCodeQL_1Language(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"javascript"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/single-language.expected")
}

func TestCodeQL_2Languages(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"c#", "javascript"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/two-languages.expected")
}

func TestCodeQL_3to2Languages(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"c#", "javascript", "typescript"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/two-languages.expected")
}

func TestCodeQL_ExcludeValidation(t *testing.T) {
	created, err := defaultWT.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages: []string{"c#", "javascript", "typescript"},
	})
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/two-languages-steady-state.expected")
}

func TestCodeQL_RunnerLabelsFromLibrary(t *testing.T) {
	created, err := selfhostedWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"c#"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/self-hosted.expected")
}

func TestCodeQL_RunnerLabelsWithCSRunnerFlagTrue(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages:          []string{"c#"},
		UsingCSRunnerLabel: true,
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/self-hosted.expected")
}

func TestCodeQL_RunnerLabelsFromLibraryWithCSRunnerFlagTrue(t *testing.T) {
	created, err := selfhostedWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages:          []string{"c#"},
		UsingCSRunnerLabel: true,
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/self-hosted.expected")
}

func TestCodeQL_RunnerLabelsFromLibraryWithCSRunnerFlagTrueAndCustomLabel(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages:          []string{"c#"},
		RunnerLabel:        "custom-runner",
		UsingCSRunnerLabel: true,
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/self-hosted-custom-label.expected")
}

func TestCodeQL_RunnerLabelsWithCSRunnerFlagFalse(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages:          []string{"javascript"},
		RunnerLabel:        "custom-runner",
		UsingCSRunnerLabel: false,
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/single-language.expected")
}

func TestCodeQL_WithSecurityExtended(t *testing.T) {
	s, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		QuerySuiteType: ts.ExtendedQuerySuiteType(),
		Languages:      []string{"c#", "javascript"},
	}, false)
	require.NoError(t, err)
	require.NotEmpty(t, s)

	requireMatchesExpected(t, s, "references/security-extended.expected")
}

func TestCodeQL_WithAutobuild(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"java"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/autobuild.expected")
}

func TestCodeQL_ActionVersion(t *testing.T) {
	ctx := flipper.WithFeatureEnabled(context.Background(), flipper.CodeScanningDefaultSetupCodeqlRC)
	// We cannot use defaultWT here because the ActionVersion depends on the FF
	wt := workflows.NewLibrary().GetWorkflowTemplateByVersion(ctx, 0, workflows.NextVersion)
	created, err := wt.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"javascript"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/codeql-action-rc.expected")
}

func TestCodeQL_ArtifactActionV3(t *testing.T) {
	created, err := artifactActionV3WT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"javascript"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/artifact-action-v3.expected")
}

func TestCodeQL_Go(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"go"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/go.expected")
}

func TestCodeQL_Swift(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"swift", "ruby"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/swift.expected")
}

func TestCodeQL_SwiftSelfHosted(t *testing.T) {
	created, err := selfhostedWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"swift"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/swift-self-hosted.expected")
}

func TestCodeQL_SwiftWithCSRunnerLabelFlag(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages:          []string{"swift"},
		UsingCSRunnerLabel: true,
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/swift-self-hosted.expected")
}

func TestCodeQL_AutoAdjust(t *testing.T) {
	created, err := defaultWT.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages:              []string{"python", "java", "ruby"},
		UsingCombinedLanguages: true,
	}, true)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/adjustment.expected")
}

func TestCodeQL_JavaBuildless(t *testing.T) {
	created, err := defaultWT.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages:              []string{"java"},
		JavaExtractionOptions:  ts.JavaExtractionOptions_BUILDLESS,
		UsingCombinedLanguages: true,
	})
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/java-buildless.expected")
}

func TestCodeQL_CSharpBuildless(t *testing.T) {
	created, err := defaultWT.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages:               []string{"csharp"},
		CSharpExtractionOptions: ts.CSharpExtractionOptions_BUILDLESS,
		UsingCombinedLanguages:  true,
	})
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/csharp-buildless.expected")
}

func TestThreatModel(t *testing.T) {
	created, err := defaultWT.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages:   []string{"c#", "javascript", "typescript"},
		ThreatModel: ts.ThreatModel_REMOTE_LOCAL,
	})
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/threat-model.expected")
}

func TestPacksNoFeatureflag(t *testing.T) {
	// If the `packs` feature flag is off then we want to render the single languge version.
	wt := workflows.NewLibrary().GetWorkflowTemplate(context.Background(), 1)
	created, err := wt.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"javascript"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/single-language-stable.expected")
}

func TestCodeScanningSecretsProviderDemoWithFeatureFlag(t *testing.T) {
	ctx := flipper.WithFeatureEnabled(context.Background(), flipper.CodeScanningPrivateRegistry)
	wt := workflows.NewLibrary().GetWorkflowTemplateByVersion(ctx, 1, workflows.NextVersion)
	created, err := wt.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages:              []string{"java"},
		JavaExtractionOptions:  ts.JavaExtractionOptions_BUILDLESS,
		UsingCombinedLanguages: true,
	})
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/java_proxy.expected")
}

func TestActionsYmlWithFeatureFlag(t *testing.T) {
	ctx := flipper.WithFeatureEnabled(context.Background(), flipper.CodeScanningActionsYml)
	wt := workflows.NewLibrary().GetWorkflowTemplate(ctx, 1)
	created, err := wt.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages:              []string{"javascript"},
		UsingCombinedLanguages: true,
	})
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/yml_analysis.expected")
}

func TestStableVersion(t *testing.T) {
	// We want to render the Stable version to avoid breaking changes
	wt := workflows.NewLibrary().GetWorkflowTemplateByVersion(context.Background(), 0, workflows.StableVersion)
	created, err := wt.CodeQLValidationWorkflow(&ts.CodeqlConfig{
		Languages: []string{"javascript-typescript"},
	}, false)
	require.NoError(t, err)

	requireMatchesExpected(t, created, "references/single-language-stable.expected")
}

var overwrite = flag.Bool("overwrite-workflows", false, "Overwrite expected workflows")

// requireMatchesExpected asserts that the generated workflow matches the one
// stored in the file in expectedPath.
func requireMatchesExpected(t *testing.T, actual string, expectedPath string) {
	t.Helper()
	if *overwrite {
		b, err := os.OpenFile(expectedPath, os.O_TRUNC|os.O_WRONLY, 0)
		if err != nil {
			t.Fatalf("could not open expected workflow file: %s", err)
		}
		fmt.Fprint(b, actual)
		b.Close()
		return
	}

	b, err := os.ReadFile(expectedPath)
	require.NoError(t, err)
	reference := string(b)

	require.Equal(t, reference, actual)
}
