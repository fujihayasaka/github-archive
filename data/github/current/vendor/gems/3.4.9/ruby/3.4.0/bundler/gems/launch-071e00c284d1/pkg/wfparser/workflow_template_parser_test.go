package wfparser

import (
	"context"
	"testing"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/actions-workflow-parser/go/template"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability"
	"github.com/github/launch/types"
)

const (
	wf_simple = `
on: push
name: "simple"
jobs:
  thing:
  steps:
  - uses: owner/repo@master`

	wf_snapshot = `
on: push
name: "simple"
jobs:
  thing:
   runs-on: ubuntu-latest
   snapshot: TestCustomImageName
   steps:
   - uses: owner/repo@master`

	// "uses" is not implemented in actions-workflow-parser yet
	wf_uses = `
name: Caller
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - run: exit 0

  remote:
    uses: ./.github/workflows/called.yaml`

	// "uses" is not implemented in actions-workflow-parser yet
	wf_remote_uses = `
name: Caller
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - run: exit 0

  remote:
    uses: my-org/my-called-workflow-repo/.github/workflows/called.yml@172239021f7ba04fe7327647b213799853a9eb89`

	wf_called = `

name: Called
on:
  workflow_call:
jobs:
  build:
    runs-on: ubuntu-latest
	steps:
	- run: exit 0`

	// evaluating workflow-level concurrency is not implemented in actions-workflow-parser yet
	wf_concurrency_expressions = `
on: push
name: "simple"
concurrency:
  group: ${{ github.ref }}
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - uses: owner/repo@master`
)

func TestLoadWorkflow(t *testing.T) {
	workflowFilePath := ".github/workflows/workflow.yml"

	resolvedFiles := []WorkflowReferencedFile{
		{
			Path: workflowFilePath,
			Text: wf_simple,
		},
	}

	ctx := context.Background()
	obs := observability.NewNullObservability()

	result, err := LoadWorkflow(ctx, obs, workflowFilePath, NewFileProvider(ctx, obs, resolvedFiles), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, result)
}

func TestLoadWorkflow_FromLab(t *testing.T) {
	workflowFilePath := ".github/workflows-lab/workflow.yml"

	resolvedFiles := []WorkflowReferencedFile{
		{
			Path: workflowFilePath,
			Text: wf_simple,
		},
	}

	ctx := context.Background()
	obs := observability.NewNullObservability()

	result, err := LoadWorkflow(ctx, obs, workflowFilePath, NewFileProvider(ctx, obs, resolvedFiles), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, result)
}

func TestLoadRequiredWorkflow(t *testing.T) {
	workflowFilePath := ".github/workflows/workflow.yml"

	// this is how the wfb.WorkflowFilePath will look for a required workflow
	requiredWorkflowFilePath := "required/1234/.github/workflows/workflow.yml"

	resolvedFiles := []WorkflowReferencedFile{
		{
			Path: workflowFilePath,
			Text: wf_simple,
		},
	}

	ctx := context.Background()
	obs := observability.NewNullObservability()

	result, err := LoadWorkflow(ctx, obs, requiredWorkflowFilePath, NewFileProvider(ctx, obs, resolvedFiles), types.LimitedReadWorkflowPermissions)

	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, workflowFilePath, result.FileTable[0])
}

func TestToParserPermissionsPolicy(t *testing.T) {
	testCases := []struct {
		name        string
		policy      types.DefaultWorkflowPermissions
		expected    parser.PermissionsPolicy
		expectedErr string
	}{
		{
			name:     "Limited read",
			policy:   types.LimitedReadWorkflowPermissions,
			expected: parser.PermissionsPolicyLimitedRead,
		},
		{
			name:     "Write",
			policy:   types.WriteWorkflowPermissions,
			expected: parser.PermissionsPolicyWrite,
		},
		{
			name:        "Unknown",
			policy:      types.DefaultWorkflowPermissions("not a real permissions policy"),
			expectedErr: "unknown permissions policy",
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual, err := toParserPermissionPolicy(tc.policy)
			if tc.expectedErr == "" {
				require.NoError(t, err)
				require.Equal(t, tc.expected, actual)
			} else {
				require.ErrorContains(t, err, tc.expectedErr)
			}
		})
	}
}

func TestLoadWorkflowWithSnapshotKeywordAndWithoutParseOption(t *testing.T) {
	workflowFilePath := ".github/workflows/workflow.yml"

	resolvedFiles := []WorkflowReferencedFile{
		{
			Path: workflowFilePath,
			Text: wf_snapshot,
		},
	}

	ctx := context.Background()
	obs := observability.NewNullObservability()

	result, err := LoadWorkflow(ctx, obs, workflowFilePath, NewFileProvider(ctx, obs, resolvedFiles), types.LimitedReadWorkflowPermissions)
	require.NoError(t, err)
	require.NotNil(t, result)
	// Make sure the only error in the result is the expected one about the snapshot keyword
	require.Len(t, result.Errors, 1)
	require.Contains(t, result.Errors[0].Error(), "The key 'snapshot' is not allowed")
}

func TestLoadWorkflowWithSnapshotKeywordAndParseOption(t *testing.T) {
	workflowFilePath := ".github/workflows/workflow.yml"

	resolvedFiles := []WorkflowReferencedFile{
		{
			Path: workflowFilePath,
			Text: wf_snapshot,
		},
	}

	ctx := context.Background()
	obs := observability.NewNullObservability()

	parseOptions := []func(*template.ParseOptions){
		func(options *template.ParseOptions) {
			options.AllowSnapshotKeyword = true
		},
	}

	result, err := LoadWorkflow(ctx, obs, workflowFilePath, NewFileProvider(ctx, obs, resolvedFiles), types.LimitedReadWorkflowPermissions, parseOptions...)
	require.NoError(t, err)
	require.NotNil(t, result)
	// Ensure the result contains no errors
	require.Len(t, result.Errors, 0)
}
