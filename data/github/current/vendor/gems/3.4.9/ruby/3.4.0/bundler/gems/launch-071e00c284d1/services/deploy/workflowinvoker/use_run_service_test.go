package workflowinvoker

import (
	"context"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	launchutils "github.com/github/launch/utils"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowparser"
)

func TestUseRunService(t *testing.T) {
	testCases := []struct {
		name                                                string
		planSKU                                             string
		appMode                                             launchconfig.AppMode
		isMultiTenant                                       bool
		repo                                                types.RepositoryFullName
		repoGlobalID                                        types.GlobalID
		rootWorkflowText                                    string
		rootWorkflowPath                                    string
		workflowContent                                     string
		wfSrc                                               workflowparser.WorkflowSource
		runServiceFeatureFlagResult                         bool
		runServiceProximaFeatureFlagResult                  bool
		runServiceFeatureFlagForHardCodedHostedLabelsResult bool
		runServiceDependabotFlagResult                      bool
		runServicePagesFlagResult                           bool
		annotationFeatureFlagResult                         bool
		pagesMariner2RunnerLabelFlagResult                  bool
		pagesSelfHostedRunnerLabelFlagResult                bool
		runServiceFeatureFlagForFreePlansResult             bool
		want                                                bool
	}{
		{
			name:                               "Not in enterprise mode",
			appMode:                            launchconfig.EnterpriseAppMode,
			repo:                               types.RepositoryFullName{Owner: "github", Name: "github"},
			repoGlobalID:                       types.GlobalID("R_kgAD"),
			runServiceFeatureFlagResult:        true,
			runServiceProximaFeatureFlagResult: true,
			want:                               false,
		},
		{
			name:                               "Not in MultiTenant configuration",
			isMultiTenant:                      true,
			repo:                               types.RepositoryFullName{Owner: "github", Name: "github"},
			repoGlobalID:                       types.GlobalID("R_kgAD"),
			runServiceFeatureFlagResult:        true,
			runServiceProximaFeatureFlagResult: false,
			want:                               false,
		},
		{
			name:                               "In MultiTenant configuration",
			isMultiTenant:                      true,
			repo:                               types.RepositoryFullName{Owner: "github", Name: "github"},
			repoGlobalID:                       types.GlobalID("R_kgAD"),
			runServiceFeatureFlagResult:        true,
			runServiceProximaFeatureFlagResult: true,
			want:                               true,
		},
		{
			name:                               "Owner in runServiceEnabledOrgs",
			repo:                               types.RepositoryFullName{Owner: "bbq-beets-four-nines", Name: "octocat"},
			repoGlobalID:                       types.GlobalID("R_kgAZ"),
			runServiceFeatureFlagResult:        true,
			runServiceProximaFeatureFlagResult: true,
			want:                               true,
		},
		{
			name:                        "Repo in noRunServiceRepos",
			repo:                        types.RepositoryFullName{Owner: "bbq-beets", Name: "Actions-canary"},
			repoGlobalID:                types.GlobalID("R_kgAZ"),
			runServiceFeatureFlagResult: true,
			want:                        false,
		},
		{
			name:                        "Feature enabled for actor",
			repo:                        types.RepositoryFullName{Owner: "github", Name: "github"},
			repoGlobalID:                types.GlobalID("R_kgAD"),
			runServiceFeatureFlagResult: true,
			want:                        true,
		},
		{
			name:                        "Feature not enabled for actor",
			repo:                        types.RepositoryFullName{Owner: "octocat", Name: "hello-world"},
			repoGlobalID:                types.GlobalID("R_kgAC"),
			runServiceFeatureFlagResult: false,
			want:                        false,
		},
		{
			name:                        "Annotation in file, feature enabled for actor",
			repo:                        types.RepositoryFullName{Owner: "github", Name: "launch"},
			repoGlobalID:                types.GlobalID("R_kgAZ"),
			rootWorkflowText:            "# run-in-four-nines\non: push",
			annotationFeatureFlagResult: true,
			want:                        true,
		},
		{
			name:                        "Annotation in file, feature not enabled for actor",
			repo:                        types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID:                types.GlobalID("R_kgAZ"),
			rootWorkflowText:            "# run-in-four-nines\non: push",
			annotationFeatureFlagResult: false,
			want:                        false,
		},
		{
			name:                           "Runs for a dependabot dynamic workflow if it's been flagged in",
			repo:                           types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID:                   types.GlobalID("R_kgAZ"),
			rootWorkflowPath:               "dynamic/dependabot/dependabot.yml",
			runServiceDependabotFlagResult: true,
			want:                           true,
		},
		{
			name:                           "Does not run for a dependabot dynamic workflow that is not flagged in",
			repo:                           types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID:                   types.GlobalID("R_kgAZ"),
			rootWorkflowPath:               "dynamic/dependabot/dependabot.yml",
			runServiceDependabotFlagResult: false,
			want:                           false,
		},
		{
			name:         "Runs for a pages dynamic workflow if it's been flagged in",
			repo:         types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID: types.GlobalID("R_kgAZ"),
			// if ur curios though, actual path is: dynamic/pages/pages-build-deployment
			rootWorkflowPath:               "dynamic/pages/thisactuallydoesntmatter.yml",
			runServicePagesFlagResult:      true,
			runServiceDependabotFlagResult: false,
			want:                           true,
		},
		{
			name:         "Does not run for a pages dynamic workflow that is not flagged in",
			repo:         types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID: types.GlobalID("R_kgAZ"),
			// if ur curios though, actual path is: dynamic/pages/pages-build-deployment
			rootWorkflowPath:               "dynamic/pages/thisactuallydoesntmatter.yml",
			runServicePagesFlagResult:      false,
			runServiceDependabotFlagResult: false,
			want:                           false,
		},
		{
			name:         "Does not run for a pages dynamic workflow if it's been flagged in and uses mariner2 runner label",
			repo:         types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID: types.GlobalID("R_kgAZ"),
			// if ur curios though, actual path is: dynamic/pages/pages-build-deployment
			rootWorkflowPath:                   "dynamic/pages/thisactuallydoesntmatter.yml",
			runServicePagesFlagResult:          true,
			runServiceDependabotFlagResult:     false,
			pagesMariner2RunnerLabelFlagResult: true,
			want:                               false,
		},
		{
			name:         "Does not run for a pages dynamic workflow if it's been flagged in and uses self-hosted runner label",
			repo:         types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID: types.GlobalID("R_kgAZ"),
			// if ur curios though, actual path is: dynamic/pages/pages-build-deployment
			rootWorkflowPath:                     "dynamic/pages/thisactuallydoesntmatter.yml",
			runServicePagesFlagResult:            true,
			runServiceDependabotFlagResult:       false,
			pagesSelfHostedRunnerLabelFlagResult: true,
			want:                                 false,
		},
		{
			name:         "Does not run for a pages dynamic workflow if it's been flagged in and uses self-hosted runner label & mariner2 runner label",
			repo:         types.RepositoryFullName{Owner: "github", Name: "other-repo"},
			repoGlobalID: types.GlobalID("R_kgAZ"),
			// if ur curios though, actual path is: dynamic/pages/pages-build-deployment
			rootWorkflowPath:                     "dynamic/pages/thisactuallydoesntmatter.yml",
			runServicePagesFlagResult:            true,
			runServiceDependabotFlagResult:       false,
			pagesSelfHostedRunnerLabelFlagResult: true,
			pagesMariner2RunnerLabelFlagResult:   true,
			want:                                 false,
		},
		{
			name:         "Uses hard-coded hosted labels and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: true,
		},
		{
			name:         "Uses hard-coded hosted labels as array and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    runs-on: [ubuntu-latest, macos-latest]
    steps:
    - uses: owner/repo@master`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: true,
		},
		{
			name:         "Uses hard-coded hosted labels with self-hosted and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    runs-on: [ubuntu-latest, self-hosted]
    steps:
    - uses: owner/repo@master`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: false,
		},
		{
			name:         "Uses expressions for runs-on and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    runs-on: ${{ 'ubuntu-latest' }}
    steps:
    - uses: owner/repo@master`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: false,
		},
		{
			name:         "Uses mapping type of runs-on and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    runs-on:
      labels: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: false,
		},
		{
			name:         "Uses hard-coded hosted labels and feature flag disabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: false,
			want: false,
		},
		{
			name:         "Uses hard-coded hosted labels in called workflow, but not used and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: false,
			want: false,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:         "Uses hard-coded hosted labels in called workflow, and used and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: true,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:         "Uses hard-coded hosted labels in called workflow, and used and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: true,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:         "Uses hard-coded hosted labels in called nested workflow, and used and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master
  thing:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: true,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    uses: actions/workflows/.github/workflows/node2.yml@v1`,
						RefType: "refs/heads/",
					},
					"actions/workflows/.github/workflows/node2.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:         "Uses hard-coded hosted labels + self-hosted in nested called workflow, and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master
  thing:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: false,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    uses: actions/workflows/.github/workflows/node2.yml@v1`,
						RefType: "refs/heads/",
					},
					"actions/workflows/.github/workflows/node2.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build:
    runs-on: self-hosted
    steps:
    - uses: owner/repo@master
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:         "Uses hard-coded hosted labels using runson map in called workflow, we don't support this, and used and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: false,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
   thing:
     runs-on:
       labels: ubuntu-latest
     steps:
     - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:         "Uses hard-coded hosted labels using runson map just group in called workflow, we don't support this, and used and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: false,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  thing:
    runs-on:
      group: runner
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:         "Uses hard-coded hosted labels using runson map + normal in called workflow, we don't support this, and used and feature flag enabled",
			repo:         types.RepositoryFullName{Owner: "github", Name: "use-hardcoded"},
			repoGlobalID: types.GlobalID("R_kgAX"),
			workflowContent: `
on: push
name: "simple"
jobs:
  thing:
    uses: actions/workflows/.github/workflows/node.yml@v1`,
			runServiceFeatureFlagForHardCodedHostedLabelsResult: true,
			want: false,
			wfSrc: &workflowparser.StubWorkflowSource{
				SourceMap: map[string]workflowparser.WorkflowDetails{
					"actions/workflows/.github/workflows/node.yml@v1": {
						Content: `
on:
  workflow_call:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master
  thing:
    runs-on:
      group: runner
    steps:
    - uses: owner/repo@master`,
						RefType: "refs/heads/",
					},
				}},
		},
		{
			name:                                    "Free plan with free feature enabled",
			planSKU:                                 ghtwirp.FreePlan,
			repo:                                    types.RepositoryFullName{Owner: "github", Name: "free-repo"},
			repoGlobalID:                            types.GlobalID("R_free"),
			runServiceFeatureFlagForFreePlansResult: true,
			runServiceFeatureFlagResult:             false,
			runServiceProximaFeatureFlagResult:      false,
			want:                                    true,
		},
		{
			name:                                    "Free organization plan with free feature enabled",
			planSKU:                                 ghtwirp.FreeOrganizationPlan,
			repo:                                    types.RepositoryFullName{Owner: "non-enabled-org", Name: "repo"},
			repoGlobalID:                            types.GlobalID("R_free_org"),
			runServiceFeatureFlagForFreePlansResult: true,
			runServiceFeatureFlagResult:             false,
			runServiceProximaFeatureFlagResult:      false,
			want:                                    true,
		},
		{
			name:                               "Free organization in enabled org",
			planSKU:                            ghtwirp.FreeOrganizationPlan,
			repo:                               types.RepositoryFullName{Owner: "bbq-beets-four-nines", Name: "repo"},
			repoGlobalID:                       types.GlobalID("R_enabled"),
			runServiceFeatureFlagResult:        false,
			runServiceProximaFeatureFlagResult: true,
			want:                               true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			tctx := context.Background()

			if tc.appMode == "" {
				tc.appMode = launchconfig.HostedAppMode
			}

			testutils.SetLaunchConfigEnv(t, []testutils.EnvPair{
				{Key: "LAUNCH_MODE", Value: tc.appMode.String()},
				{Key: "LAUNCH_IS_MULTI_TENANT", Value: strconv.FormatBool(tc.isMultiTenant)},
			}...)

			featureEnabledForRepoOrOwners := func(ctx context.Context, flag string, repoGID types.GlobalID) bool {
				require.Equal(t, tctx, ctx)
				require.Equal(t, tc.repoGlobalID, repoGID)

				switch flag {
				case ghclient.RunServiceFeatureFlag:
					return tc.runServiceFeatureFlagResult
				case ghclient.AllowRunServiceAnnotation:
					return tc.annotationFeatureFlagResult
				case ghclient.RunServiceDependabotFlag:
					return tc.runServiceDependabotFlagResult
				case ghclient.RunServicePagesFlag:
					return tc.runServicePagesFlagResult
				case ghclient.PagesMariner2RunnerLabelFlag:
					return tc.pagesMariner2RunnerLabelFlagResult
				case ghclient.PagesSelfHostedRunnerLabelFlag:
					return tc.pagesSelfHostedRunnerLabelFlagResult
				case ghclient.RunServiceFeatureFlagForHardCodedHostedLabels:
					return tc.runServiceFeatureFlagForHardCodedHostedLabelsResult
				case ghclient.RunServiceProximaFeatureFlag:
					return tc.runServiceProximaFeatureFlagResult
				case ghclient.RunServiceFeatureFlagForFreePlans:
					return tc.runServiceFeatureFlagForFreePlansResult
				default:
					require.Fail(t, "unexpected feature flag", flag)
				}
				return false
			}

			file := types.ResolvedFile{Path: tc.rootWorkflowPath, Text: tc.rootWorkflowText}
			var parsedWorkflow *workflowparser.Workflow
			if tc.workflowContent != "" {
				wfSrc := tc.wfSrc
				if wfSrc == nil {
					wfSrc = workflowparser.NullWorkflowSource{}
				}
				file := types.ResolvedFile{Text: tc.workflowContent, Path: "workflow.yml"}
				r, err := workflowparser.ParseWithCalledWorkflows(tctx, file, types.WorkflowFeatureFlags{}, wfSrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
				require.NoError(t, err)
				parsedWorkflow = r
			}

			got := useRunService(tctx, parsedWorkflow, tc.planSKU, tc.repo, tc.repoGlobalID, &file, featureEnabledForRepoOrOwners)
			require.Equal(t, tc.want, got)
		})
	}
}
