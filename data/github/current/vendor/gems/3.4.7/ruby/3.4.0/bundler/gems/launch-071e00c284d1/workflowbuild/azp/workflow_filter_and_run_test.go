package azp

import (
	"bytes"
	"context"
	"fmt"
	"testing"
	"text/template"

	githubgo "github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/model"
	launchutils "github.com/github/launch/utils"
	"github.com/github/launch/utils/requiredworkflowutils"
	"github.com/github/launch/utils/testutils"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild"
	"github.com/github/launch/workflowparser"
)

var (
	baseBranch             = "master"
	topicBranch            = "topic"
	actionOpened           = "opened"
	actionClosed           = "closed"
	actionDeleted          = "deleted"
	shaBefore              = "abcdef"
	shaAfter               = "g12345"
	testRepoID             = int64(7)
	testRepoGlobalID       = types.GlobalID(testutils.EncodeGlobalID("Repository", testRepoID))
	testRepoGlobalIDString = testRepoGlobalID.String()
	branchRef              = "refs/heads/master"
	thingBranch            = "refs/heads/thing"
	thingTag               = "refs/tags/thing"
)

// This first test case is meant as explicit documentation of what the
// table test below is doing, and actually duplicates the first test case.
// Additional test cases that can be expressed by the table test should be added to it.
func TestProvider_GetWorkflowFilter_TestExample(t *testing.T) {
	tpl := `
on:
  push:
    paths:
    - "*Website/*.proj"
jobs:
  thing:
    steps:
    - uses: some/repo@v1.0.0`
	f := getFilterFrom(t, tpl,
		[]string{"ContosoWebsite/ContosoWebsite.proj"},
		"push",
		makePushEvent(branchRef),
		"",
		"",
		nil,
	)

	assertBothVersionsOfFiltering(t, f, tpl, true, "")
}

func TestProvider_GetWorkflowFilter(t *testing.T) {
	tests := []struct {
		desc             string
		runs             bool
		event            flowevents.GitHubEvent
		modifiedFiles    *[]string
		workflowTemplate templateData
		parseErrorMsg    string
		workflowPath     string
	}{
		{
			desc:          "runs when sole filter is matching path filter",
			runs:          true,
			event:         makePushEvent(branchRef),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Paths:     []string{`"*Website/*.proj"`},
				EventName: "push",
			},
		},
		{
			desc:          "does not run when sole filter is non-matching path filter",
			runs:          false,
			event:         makePushEvent(branchRef),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Paths:     []string{`"**/*.yaml"`},
				EventName: "push",
			},
		},
		{
			desc:          "runs when multiple path filters match",
			runs:          true,
			event:         makePushEvent(branchRef),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Paths:     []string{`"thing.*"`, `"*.js"`},
				EventName: "push",
			},
		},
		{
			desc:          "does not run when paths are excluded",
			runs:          false,
			event:         makePushEvent(branchRef),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Paths:     []string{`"thing.*"`, `"!*.js"`},
				EventName: "push",
			},
		},
		{
			desc:          "ignores path filter for required workflow",
			runs:          true,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowPath:  "required/3/.github.workflows/CI.yaml",
			workflowTemplate: templateData{
				Workflows: []string{"CI"},
				Paths:     []string{`"thing.md"`},
				EventName: "pull_request",
			},
		},
		{
			desc:          "ignores branch filter for required workflow",
			runs:          true,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowPath:  "required/3/.github.workflows/CI.yaml",
			workflowTemplate: templateData{
				Workflows: []string{"CI"},
				EventName: "pull_request",
				Branch:    "other",
			},
		},
		{
			desc:          "required workflow ignores type filter, and runs inspite of it for default types",
			runs:          true,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowPath:  "required/thing.yaml",
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"thing*"`},
				EventName: "pull_request",
				Types:     `"closed"`,
			},
		},
		{
			desc:          "runs when a tag filter matches",
			runs:          true,
			event:         makePushEvent(thingTag),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Tags:      []string{`"thing"`},
				EventName: "push",
			},
		},
		{
			desc:          "does not run when a tag exclude matches",
			runs:          false,
			event:         makePushEvent("refs/tags/v0.1.1"),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Tags:      []string{`v*`, `"!v0*"`},
				EventName: "push",
			},
		},
		{
			desc:          "runs when a negative ref glob exists but does not match",
			runs:          true,
			event:         makePushEvent("refs/tags/v6.1.1"),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Tags:      []string{`"*"`, `"!v0*"`},
				EventName: "push",
			},
		},
		{
			desc:          "runs when a ref filter matches",
			runs:          true,
			event:         makePushEvent(thingBranch),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "thing*",
				EventName: "push",
			},
		},
		{
			desc:          "does not run if a tag filter is the only filter, and doesn't match",
			runs:          false,
			event:         makePushEvent(thingTag),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Tags:      []string{"noMatch"},
				EventName: "push",
			},
		},
		{
			desc:          "branch push does not run if only tag filter present",
			runs:          false,
			event:         makePushEvent(thingBranch),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Tags:      []string{`"*"`},
				EventName: "push",
			},
		},
		{
			desc:          "does not run if positive exact match is only substring of ref",
			runs:          false,
			event:         makePushEvent("refs/heads/not-master"),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    `master`,
				EventName: "push",
			},
		},
		{
			desc:          "rejects branch pushes when tags are only ref filter present",
			runs:          false,
			event:         makePushEvent(thingBranch),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Tags:      []string{`"*"`},
				EventName: "push",
			},
		},
		{
			desc:          "rejects branch pushes when tags are only ref filter present, and it contains only negative globs",
			runs:          false,
			event:         makePushEvent(thingBranch),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Tags:      []string{`"!v*"`},
				EventName: "push",
			},
		},
		{
			desc:          "rejects tag pushes when branch is only ref filter present",
			runs:          false,
			event:         makePushEvent(thingTag),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    `"*"`,
				EventName: "push",
			},
		},
		{
			desc:          "runs pull requests if branch filter matches",
			runs:          true,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				EventName: "pull_request",
			},
		},
		{
			desc:          "does not run pull requests if branch filter doesn't match",
			runs:          false,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "other",
				EventName: "pull_request",
			},
		},
		{
			desc:          "runs pull requests with branch filter and paths",
			runs:          true,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"thing*"`},
				EventName: "pull_request",
			},
		},
		{
			desc:          "does not runs pull requests with branch filter and paths if branch doesn't match",
			runs:          false,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "other",
				Paths:     []string{`"thing*"`},
				EventName: "pull_request",
			},
		},
		{
			desc:          "does not runs pull requests with branch filter and paths if path doesn't match",
			runs:          false,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"other*"`},
				EventName: "pull_request",
			},
		},
		{
			desc:          "runs pull requests if action matches default",
			runs:          true,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"thing*"`},
				EventName: "pull_request",
			},
		},
		{
			desc:          "does not run pull requests if action does not match default and no other filters",
			runs:          false,
			event:         makePullRequest(actionClosed),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				EventName: "pull_request",
			},
		},
		{
			desc:          "does not run pull requests if action does not match default",
			runs:          false,
			event:         makePullRequest(actionClosed),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"thing*"`},
				EventName: "pull_request",
			},
		},
		{
			desc:          "runs pull requests if action matches type",
			runs:          true,
			event:         makePullRequest(actionClosed),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"thing*"`},
				Types:     `"closed"`,
				EventName: "pull_request",
			},
		},
		{
			desc:          "runs pull requests if action matches type glob",
			runs:          true,
			event:         makePullRequest(actionClosed),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"thing*"`},
				Types:     `"*"`,
				EventName: "pull_request",
			},
		},
		{
			desc:          "does not run pull requests if action does not match type",
			runs:          false,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				Paths:     []string{`"thing*"`},
				Types:     `"closed"`,
				EventName: "pull_request",
			},
		},
		{
			desc:          "runs if action matches type",
			runs:          true,
			event:         &githubgo.IssueCommentEvent{Action: &actionDeleted},
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Types:     `deleted`,
				EventName: "issue_comment",
			},
		},
		{
			desc:          "does not run if action does not match type",
			runs:          false,
			event:         &githubgo.IssueCommentEvent{Action: &actionDeleted},
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Types:     `created`,
				EventName: "issue_comment",
			},
		},
		{
			desc:          "runs if there are no given or default types",
			runs:          true,
			event:         &githubgo.RepositoryDispatchEvent{Action: &actionOpened},
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				EventName: "repository_dispatch",
			},
		},
		{
			desc:          "runs when collection filter is matching workflow name",
			runs:          true,
			event:         makeWorkflowRunEvent("CI", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI", "CD"`},
				EventName: "workflow_run",
			},
		},
		{
			desc:          "does not run when workflow_run event is triggered by changes originating from fork with passing branch filters",
			runs:          false,
			event:         makeWorkflowRunEventTriggeredFromFork("CI", "closed", ""),
			modifiedFiles: &[]string{"modified-file.js"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI", "CD"`},
				EventName: "workflow_run",
				Branch:    baseBranch,
			},
		},
		{
			desc:          "runs when workflow_run event is triggered by changes originating from fork with passing branches-ignore filters",
			runs:          true,
			event:         makeWorkflowRunEventTriggeredFromFork("my-test-wf-run", "closed", "other-branch"),
			modifiedFiles: &[]string{"other-workflow.yml"},
			workflowTemplate: templateData{
				Workflows:      []string{`"my-test-wf-run"`},
				EventName:      "workflow_run",
				BranchesIgnore: []string{baseBranch},
			},
		},
		{
			desc:          "doesn't run when workflow_run event is triggered by changes originating from fork with branches-ignore filters not passing",
			runs:          false,
			event:         makeWorkflowRunEventTriggeredFromFork("my-test-wf-run", "closed", ""),
			modifiedFiles: &[]string{"other-workflow.yml"},
			workflowTemplate: templateData{
				Workflows:      []string{`"my-test-wf-run"`},
				EventName:      "workflow_run",
				BranchesIgnore: []string{baseBranch},
			},
		},
		{
			desc:          "runs when workflow_run event is triggered by changes originating from fork with no branch filters",
			runs:          true,
			event:         makeWorkflowRunEventTriggeredFromFork("my-test-wf-run", "closed", ""),
			modifiedFiles: &[]string{"other-workflow.yml"},
			workflowTemplate: templateData{
				Workflows: []string{`"my-test-wf-run"`},
				EventName: "workflow_run",
			},
		},
		{
			desc:          "runs when collection filter is matching workflow name & action",
			runs:          true,
			event:         makeWorkflowRunEvent("CI", "requested"),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI", "CD"`},
				EventName: "workflow_run",
				Types:     "requested",
			},
		},
		{
			desc:          "runs when sole filter is matching workflow name",
			runs:          true,
			event:         makeWorkflowRunEvent("CI", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI"`},
				EventName: "workflow_run",
			},
		},
		{
			desc:          "runs when sole filter is matching workflow name, case insensitive",
			runs:          true,
			event:         makeWorkflowRunEvent("IAMAWORKFLOWNAME", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"iAmaWoRKFLowName"`},
				EventName: "workflow_run",
			},
		},
		{
			desc:          "runs when sole filter is matching workflow name & action",
			runs:          true,
			event:         makeWorkflowRunEvent("CI", "completed"),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI"`},
				EventName: "workflow_run",
				Types:     "completed",
			},
		},
		{
			desc:          "does not run when workflow name does not match",
			runs:          false,
			event:         makeWorkflowRunEvent("CD", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI"`},
				EventName: "workflow_run",
			},
		},
		{
			desc:          "does not run when workflow action does not match",
			runs:          false,
			event:         makeWorkflowRunEvent("CI", "requested"),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI"`},
				EventName: "workflow_run",
				Types:     "completed",
			},
		},
		{
			desc:          "does not run when sole workflow filter is recursive",
			runs:          false,
			event:         makeWorkflowRunEvent("IAMAWORKFLOWNAME", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			parseErrorMsg: "Workflow 'IAMAWORKFLOWNAME' cannot listen to itself.",
			workflowTemplate: templateData{
				WorkflowName: "IAMAWORKFLOWNAME",
				Workflows:    []string{`"iAmaWoRKFLowName"`},
				EventName:    "workflow_run",
			},
		},
		{
			desc:          "does not run when collection workflow filter is recursive",
			runs:          false,
			event:         makeWorkflowRunEvent("CI", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			parseErrorMsg: "Workflow 'CI' cannot listen to itself.",
			workflowTemplate: templateData{
				WorkflowName: "CI",
				Workflows:    []string{`"CI", "CD"`},
				EventName:    "workflow_run",
			},
		},
		{
			desc:          "does not run when workflows filter is empty",
			runs:          false,
			event:         makeWorkflowRunEvent("CI", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			parseErrorMsg: fmt.Sprintf("`on.workflow_run` does not reference any workflows. See https://docs.github.com/actions/learn-github-actions/events-that-trigger-workflows#workflow_run for more information"),
			workflowTemplate: templateData{
				WorkflowName: "CI",
				Workflows:    []string{},
				EventName:    "workflow_run",
			},
		},
		{
			desc:          "runs workflow runs if the branch filter matches",
			runs:          true,
			event:         makeWorkflowRunEvent("CI", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI"`},
				EventName: "workflow_run",
				Branch:    "master",
			},
		},
		{
			desc:          "does not run workflow runs if the branch filter does not match",
			runs:          false,
			event:         makeWorkflowRunEvent("CI", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI"`},
				EventName: "workflow_run",
				Branch:    "trunk",
			},
		},
		{
			desc:          "ignores branch filtering if there is no branch information",
			runs:          true,
			event:         makeWorkflowRunEventForMerge("CI", ""),
			modifiedFiles: &[]string{"ContosoWebsite/ContosoWebsite.proj"},
			workflowTemplate: templateData{
				Workflows: []string{`"CI"`},
				EventName: "workflow_run",
				Branch:    "master",
			},
		},
		{
			desc:          "runs pull requests target if branch filter matches",
			runs:          true,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				EventName: "pull_request_target",
			},
		},
		{
			desc:          "does not run pull requests target if branch filter doesn't match",
			runs:          false,
			event:         makePullRequestOpened(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "other",
				EventName: "pull_request_target",
			},
		},
		{
			desc:          "runs merge group target if branch filter matches",
			runs:          true,
			event:         makeMergeGroup(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "master",
				EventName: "merge_group",
			},
		},
		{
			desc:          "does not run merge group target if branch filter matches",
			runs:          false,
			event:         makeMergeGroup(),
			modifiedFiles: &[]string{"thing.js"},
			workflowTemplate: templateData{
				Branch:    "staging",
				EventName: "merge_group",
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.desc, func(tt *testing.T) {
			rendered := getTemplate(tc.workflowTemplate)

			f := getFilterFrom(tt, rendered, *tc.modifiedFiles, tc.workflowTemplate.EventName, tc.event, tc.parseErrorMsg, tc.workflowPath, nil)
			filter := &workflowbuild.MockWorkflowFilter{}
			filter.EXPECT().ShouldRun(mock.Anything, mock.Anything).Return(true)
			assert.NotEqual(tt, filter, f)
			assertBothVersionsOfFiltering(tt, f, rendered, tc.runs, tc.workflowPath)
		})
	}
}

func assertBothVersionsOfFiltering(t *testing.T, f workflowbuild.WorkflowFilter, rendered string, shouldRun bool, workflowPath string) {
	dbg := fmt.Sprintf("filters with workflow:\n%s\n\nand filter: %+v", rendered, f)

	if workflowPath == "" {
		workflowPath = "file.yml"
	}

	runIt := f.ShouldRun(context.TODO(), model.Workflow{
		Path: workflowPath,
	})

	assert.Equal(t, shouldRun, runIt, dbg)
}

func TestProvider_GetWorkflowFilter_EventNotIncludedInOn(t *testing.T) {
	rendered := getTemplate(templateData{EventName: "repository_dispatch"})
	f := getFilterFrom(t, rendered, []string{}, "issue_comment", &githubgo.IssueCommentEvent{Action: &actionDeleted}, "", "", nil)
	filter := &workflowbuild.MockWorkflowFilter{}
	filter.EXPECT().ShouldRun(mock.Anything, mock.Anything).Return(true)
	assert.NotEqual(t, filter, f)

	assertBothVersionsOfFiltering(t, f, rendered, false, "")
}

func TestProvider_GetWorkflowFilter_AlwaysRunDynamicEvents(t *testing.T) {
	rendered := getTemplate(templateData{EventName: "repository_dispatch"})
	f := getFilterFrom(t, rendered, []string{}, "dynamic", nil, "", "", nil)
	filter := &workflowbuild.MockWorkflowFilter{}
	filter.EXPECT().ShouldRun(mock.Anything, mock.Anything).Return(true)
	assert.NotEqual(t, filter, f)

	assertBothVersionsOfFiltering(t, f, rendered, true, "")
}

func TestProvider_GetWorkflowFilter_PullRequestTarget(t *testing.T) {
	ctx := context.Background()
	rendered := getTemplate(templateData{
		Branch:    "master",
		Paths:     []string{`"thing*"`},
		EventName: "pull_request_target"})

	mockTwirpClient := newClientWithFlags(nil)
	filterer := NewWorkflowFilterer(observability.NewNullObservability(), mockTwirpClient.IsFeatureEnabledForRepoOrOwners)
	files := []types.ResolvedFile{
		{
			Path: "file.yml",
			Text: rendered,
		},
	}

	mockClient := github.MockClient{}

	mockClient.EXPECT().GetFilterDiff(mock.Anything, mock.Anything,
		mock.MatchedBy(func(sha types.BeforeAfterSHA) bool { return sha.After.String() == shaAfter }),
		mock.MatchedBy(func(ref types.GitRef) bool { return ref.String() == "refs/heads/master" }),
		mock.Anything).Return(&github.FilterDiffResult{
		Paths: []string{"thing.js"},
	}, nil)

	parsed, err := workflowparser.ParseWorkflows(ctx, files, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.NoError(t, err)
	require.Len(t, parsed.InvalidWorkflows, 0)

	f, err := filterer.GetWorkflowFilter(context.TODO(), parsed, "pull_request_target", makePullRequestOpened(), &mockClient)
	require.NoError(t, err, "error generating filter")

	filter := &workflowbuild.MockWorkflowFilter{}
	filter.EXPECT().ShouldRun(mock.Anything, mock.Anything).Return(true)
	assert.NotEqual(t, filter, f)

	assertBothVersionsOfFiltering(t, f, rendered, true, "")
}

func TestProvider_RunsForSchedules(t *testing.T) {
	f := getFilterFrom(t, `
on:
  schedule:
    - cron: "* * * * *"
jobs:
  thing:
    steps:
    - uses: some/repo@v1.0.0`, nil, "schedule", makePushEvent(branchRef), "", "", nil)

	rendered := getTemplate(templateData{EventName: "pull_request"})
	assertBothVersionsOfFiltering(t, f, rendered, true, "")
}

func TestProvider_RecursiveWorkflows(t *testing.T) {

}

func newClientWithFlags(flags map[string]bool) *ghtwirp.MockClient {
	ghTwirpMock := &ghtwirp.MockClient{}
	// tests that don't use flags will disabled the behavior by default
	if flags == nil {
		ghTwirpMock.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.TreatEmptyAdvisoriesAsPassed, mock.Anything).Return(false)
		ghTwirpMock.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.PathsIgnoreEmptyPushBypassesParser, mock.Anything).Return(false)
		return ghTwirpMock
	}

	for flag, enabled := range flags {
		ghTwirpMock.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, flag, mock.Anything).Return(enabled)
	}
	return ghTwirpMock
}

func getFilterFrom(t *testing.T, workflowFileText string, modifiedPaths []string, eventType string, event flowevents.GitHubEvent, parseErrorMsg string, workflowPath string, featureFlags map[string]bool) workflowbuild.WorkflowFilter {
	ctx := context.Background()
	mockTwirpClient := newClientWithFlags(featureFlags)
	filterer := NewWorkflowFilterer(observability.NewNullObservability(), mockTwirpClient.IsFeatureEnabledForRepoOrOwners)

	if workflowPath == "" {
		workflowPath = "file.yml"
	}

	var workflowFileReference types.WorkflowFileReference
	// if the workflow is a required workflow
	if requiredworkflowutils.IsRequiredWorkflow(workflowPath) {
		workflowFileReference = types.NewRulesetWorkflowFileReference(workflowPath, types.GitRef("refs/heads/main"), types.CommitSha("1234567890123456789012345678901234567890"))
	} else {
		workflowFileReference = types.NewWorkflowFileReference(workflowPath)
	}

	files := []types.ResolvedFile{
		{
			Path: workflowPath,
			Text: workflowFileText,
		},
	}

	mockClient := github.MockClient{}

	if len(modifiedPaths) == 0 {
		// empty commit scenario
		mockClient.EXPECT().GetFilterDiff(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&github.FilterDiffResult{
			Paths:    modifiedPaths,
			Advisory: "empty",
		}, nil)
	} else {
		mockClient.EXPECT().GetFilterDiff(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&github.FilterDiffResult{
			Paths: modifiedPaths,
		}, nil)
	}

	parsed, err := workflowparser.ParseWorkflows(ctx, files, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	if len(parseErrorMsg) == 0 {
		require.NoError(t, err)
		require.Len(t, parsed.InvalidWorkflows, 0)
	} else {
		require.Len(t, parsed.InvalidWorkflows, 1)
		require.EqualError(t, parsed.InvalidWorkflows[workflowFileReference], parseErrorMsg)
	}

	f, err := filterer.GetWorkflowFilter(context.TODO(), parsed, eventType, event, &mockClient)
	require.NoError(t, err, "error generating filter")
	return f
}

func makeMergeGroup() *githubgo.MergeGroupEvent {
	action := "checks_requested"

	return &githubgo.MergeGroupEvent{
		Action: &action,
		Repo: &githubgo.Repository{
			ID:     &testRepoID,
			NodeID: &testRepoGlobalIDString,
		},
		MergeGroup: &githubgo.MergeGroup{
			HeadSHA: &shaAfter,
			BaseRef: &branchRef,
			HeadRef: &thingBranch,
		},
	}
}

func makePullRequestOpened() *githubgo.PullRequestEvent {
	return makePullRequest(actionOpened)
}

func makePullRequest(action string) *githubgo.PullRequestEvent {
	return &githubgo.PullRequestEvent{
		Action: &action,
		Repo: &githubgo.Repository{
			ID:     &testRepoID,
			NodeID: &testRepoGlobalIDString,
		},
		PullRequest: &githubgo.PullRequest{
			Base: &githubgo.PullRequestBranch{
				Ref: &baseBranch,
				SHA: &shaBefore,
			},
			Head: &githubgo.PullRequestBranch{
				Ref: &topicBranch,
				SHA: &shaAfter,
			},
		},
	}
}

func makePushEvent(ref string) *githubgo.PushEvent {
	push := &githubgo.PushEvent{
		Ref:    &ref,
		Before: &shaBefore,
		After:  &shaAfter,
		Repo: &githubgo.PushEventRepository{
			ID:     &testRepoID,
			NodeID: &testRepoGlobalIDString,
		},
	}
	return push
}

func makeWorkflowRunEvent(workflowName, eventAction string) *githubgo.WorkflowRunEvent {
	headBranch := "master"
	workflowRun := &githubgo.WorkflowRunEvent{
		Action: &eventAction,
		Repository: &githubgo.Repository{
			ID:     &testRepoID,
			NodeID: &testRepoGlobalIDString,
		},
		Workflow: &githubgo.Workflow{
			Name: workflowName,
		},
		WorkflowRun: &githubgo.WorkflowRun{
			CheckSuite: &githubgo.CheckSuite{
				HeadBranch: &headBranch,
				Repository: &githubgo.Repository{
					ID:     &testRepoID,
					NodeID: &testRepoGlobalIDString,
				},
			},
			HeadRepository: &githubgo.Repository{
				ID:     &testRepoID,
				NodeID: &testRepoGlobalIDString,
			},
		},
	}
	return workflowRun
}

func makeWorkflowRunEventForMerge(workflowName, eventAction string) *githubgo.WorkflowRunEvent {
	wre := makeWorkflowRunEvent(workflowName, eventAction)
	wre.WorkflowRun.CheckSuite.HeadBranch = nil
	return wre
}

func makeWorkflowRunEventTriggeredFromFork(workflowName, eventAction string, forkBranchOrTagName string) *githubgo.WorkflowRunEvent {
	wre := makeWorkflowRunEvent(workflowName, eventAction)
	forkRepoID := testRepoID + 1
	wre.WorkflowRun.HeadRepository.ID = &forkRepoID
	if forkBranchOrTagName != "" {
		wre.WorkflowRun.HeadBranch = &forkBranchOrTagName
	}
	return wre
}

type templateData struct {
	WorkflowName   string
	Workflows      []string
	Branch         string
	BranchesIgnore []string
	EventName      string
	Paths          []string
	Tags           []string
	Types          string
}

var templateText = `on:
  {{ .EventName }}:
  {{- if .Branch }}
    branches: {{ .Branch }}
  {{- end }}

  {{- if .BranchesIgnore }}
    branches-ignore:
    {{- range .BranchesIgnore }}
      - {{ . }}
    {{- end }}
  {{- end }}

  {{- if .Paths }}
    paths:
    {{- range .Paths }}
      - {{ . }}
    {{- end }}
  {{- end }}

  {{- if .Tags }}
    tags:
    {{- range .Tags }}
      - {{ . }}
    {{- end }}
  {{- end }}

  {{- if .Types }}
    types: {{ .Types}}
  {{- end }}

  {{- if .Workflows }}
    workflows: {{ .Workflows}}
  {{- end }}
{{- if .WorkflowName }}
name: {{ .WorkflowName}}
{{- end }}
jobs:
  thing:
    steps:
    - uses: some/repo@v1.0.0`

var parsedTemplate = template.Must(template.New("workflow.yml").Parse(templateText))

func getTemplate(d templateData) string {
	var out bytes.Buffer
	err := parsedTemplate.Execute(&out, d)
	if err != nil {
		panic(err)
	}
	return out.String()
}

type scenario struct {
	modified     []string
	eventName    string
	event        *githubgo.PushEvent
	featureFlags map[string]bool
}

func TestPathsIgnore(t *testing.T) {
	assertRuns(t, `
 on:
   push:
     paths-ignore: ["not-there/*"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`,
		scenario{
			modified:  []string{"ContosoWebsite/ContosoWebsite.proj"},
			eventName: "push",
			event:     makePushEvent(branchRef),
		},
	)
}

func TestPathsIgnoreWithRef(t *testing.T) {
	assertRuns(t, `
 on:
   push:
     branches-ignore: ["not-ignored"]
     paths-ignore: ["not-there/*"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`,
		scenario{
			modified:  []string{"ContosoWebsite/ContosoWebsite.proj"},
			eventName: "push",
			event:     makePushEvent(branchRef),
		},
	)
}

func TestPathsIgnoreWithEmptyCommit(t *testing.T) {
	// Will this run on an empty commit?
	// Reference: https://github.com/github/c2c-actions-support/issues/3464
	emptyCommitScenario := scenario{
		modified:  []string{},
		eventName: "push",
		event:     makePushEvent(branchRef),
	}

	workflowFile := `
 on:
   push:
     paths-ignore: ["docs/**"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`

	tests := []struct {
		description string
		scenario    scenario
		shouldRun   bool
	}{
		{
			description: "both feature flags off (default behavior)",
			scenario: scenario{
				modified:  emptyCommitScenario.modified,
				event:     emptyCommitScenario.event,
				eventName: emptyCommitScenario.eventName,
				featureFlags: map[string]bool{
					github.TreatEmptyAdvisoriesAsPassed:       false,
					github.PathsIgnoreEmptyPushBypassesParser: false,
				},
			},
			shouldRun: false,
		},
		{
			description: "actions_treat_empty_advisories_as_passed FF enabled",
			scenario: scenario{
				modified:  emptyCommitScenario.modified,
				event:     emptyCommitScenario.event,
				eventName: emptyCommitScenario.eventName,
				featureFlags: map[string]bool{
					github.TreatEmptyAdvisoriesAsPassed:       true,
					github.PathsIgnoreEmptyPushBypassesParser: false,
				},
			},
			shouldRun: false,
		},
		{
			description: "actions_paths_ignore_empty_push_bypasses_parser FF enabled",
			scenario: scenario{
				modified:  emptyCommitScenario.modified,
				event:     emptyCommitScenario.event,
				eventName: emptyCommitScenario.eventName,
				featureFlags: map[string]bool{
					github.TreatEmptyAdvisoriesAsPassed:       false,
					github.PathsIgnoreEmptyPushBypassesParser: true,
				},
			},
			shouldRun: false,
		},
		{
			description: "both FFs enabled",
			scenario: scenario{
				modified:  emptyCommitScenario.modified,
				event:     emptyCommitScenario.event,
				eventName: emptyCommitScenario.eventName,
				featureFlags: map[string]bool{
					github.TreatEmptyAdvisoriesAsPassed:       true,
					github.PathsIgnoreEmptyPushBypassesParser: true,
				},
			},
			shouldRun: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.description, func(t *testing.T) {
			if tc.shouldRun {
				assertRuns(t, workflowFile, tc.scenario)
			} else {
				refuteRuns(t, workflowFile, tc.scenario)
			}
		})
	}
}

func TestPathsIgnoreWithRefPathFailed(t *testing.T) {
	refuteRuns(t, `
 on:
   push:
     branches-ignore: ["not-ignored"]
     paths-ignore: ["**"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`,
		scenario{
			modified:  []string{"ContosoWebsite/ContosoWebsite.proj"},
			eventName: "push",
			event:     makePushEvent(branchRef),
		},
	)
}

func TestPathsIgnoreWithRefWhereRefFails(t *testing.T) {
	refuteRuns(t, `
 on:
   push:
     branches-ignore: ["**"]
     paths-ignore: ["not-there"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`,
		scenario{
			modified:  []string{"ContosoWebsite/ContosoWebsite.proj"},
			eventName: "push",
			event:     makePushEvent(branchRef),
		},
	)
}

func TestPathsOnlyTagsWhenPushingToBranchFails(t *testing.T) {
	refuteRuns(t, `
 on:
   push:
     tags-ignore: ["**"]
     paths: ["**"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`,
		scenario{
			modified:  []string{"ContosoWebsite/ContosoWebsite.proj"},
			eventName: "push",
			event:     makePushEvent(branchRef),
		},
	)
}

func TestIgnoresPathFiltersForTags(t *testing.T) {
	assertRuns(t, `
 on:
   push:
     tags: ["**"]
     paths: ["not-changed"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`,
		scenario{
			modified:  []string{"ContosoWebsite/ContosoWebsite.proj"},
			eventName: "push",
			event:     makePushEvent(thingTag),
		},
	)

	// check equivalent branch filter does run path filtering
	refuteRuns(t, `
 on:
   push:
     branches: ["**"]
     paths: ["not-changed"]
 jobs:
   thing:
     steps:
     - uses: some/repo@v1.0.0`,
		scenario{
			modified:  []string{"ContosoWebsite/ContosoWebsite.proj"},
			eventName: "push",
			event:     makePushEvent(branchRef),
		},
	)
}

func runsOnAssertion(t *testing.T, expected bool, workflowFile string, scenario scenario) {
	runIt := getFilterFrom(t, workflowFile, scenario.modified, scenario.eventName, scenario.event, "", "", scenario.featureFlags).
		ShouldRun(context.TODO(), model.Workflow{
			Path: "file.yml",
		})

	assert.Equal(t, expected, runIt)
}

func assertRuns(t *testing.T, workflowFile string, scenario scenario) {
	runsOnAssertion(t, true, workflowFile, scenario)
}

func refuteRuns(t *testing.T, workflowFile string, scenario scenario) {
	runsOnAssertion(t, false, workflowFile, scenario)
}
