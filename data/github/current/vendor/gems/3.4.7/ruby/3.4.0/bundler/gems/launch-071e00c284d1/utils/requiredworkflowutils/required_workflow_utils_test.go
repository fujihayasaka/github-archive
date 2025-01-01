package requiredworkflowutils

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/flow/flowevents"
)

func TestIsRequiredWorkflow(t *testing.T) {
	assert.Equal(t, false, IsRequiredWorkflow("dynamic/prebuild/abc.yml"))
	assert.Equal(t, false, IsRequiredWorkflow(".github/workflows/abc.yml"))
	assert.Equal(t, false, IsRequiredWorkflow(".github/workflow-lab/abc.yml"))
	assert.Equal(t, true, IsRequiredWorkflow("required/1234/required_workflows/abc.yml"))
	assert.Equal(t, true, IsRequiredWorkflow("required/1234/abc.yml"))
}

func TestExtractAndRemoveMetadataFromRequiredWorkflowPath(t *testing.T) {
	type response struct {
		repoID  int64
		path    string
		wantErr bool
	}

	type testInput struct {
		path string
		want response
	}

	inputs := []testInput{
		{path: "dynamic/prebuild/abc.yml", want: response{0, "dynamic/prebuild/abc.yml", false}},
		{path: ".github/workflows/abc.yml", want: response{0, ".github/workflows/abc.yml", false}},
		{path: ".github/workflow-lab/abc.yml", want: response{0, ".github/workflow-lab/abc.yml", false}},
		{path: "required/12345/required_workflows/abc.yml", want: response{12345, "required_workflows/abc.yml", false}},
		{path: "required/abc.yml", want: response{0, "", true}},
		{path: "required/12revsg34/abc.yml", want: response{0, "", true}},
		{path: "required/12345/abc.yml", want: response{12345, "abc.yml", false}},
		{path: "required/1234567891011/abc.yml", want: response{1234567891011, "abc.yml", false}},
		{path: "required/1234567891011/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/foo.yml", want: response{1234567891011, "a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/foo.yml", false}},
		{path: "requiredworkflow/abc.yml", want: response{0, "requiredworkflow/abc.yml", false}},
		{path: "required/1234/4567/workflow/abc.yml", want: response{1234, "4567/workflow/abc.yml", false}},
	}

	for _, input := range inputs {
		actualRepoID, actualPath, err := ExtractAndRemoveMetadataFromRequiredWorkflowPath(input.path)
		if input.want.wantErr {
			assert.Error(t, err)
		} else {
			require.NoError(t, err)
		}
		assert.Equal(t, input.want.repoID, actualRepoID)
		assert.Equal(t, input.want.path, actualPath)
	}
}

func TestConstructRequiredWorkflowPath(t *testing.T) {
	type testInput struct {
		path         string
		sourceRepoID int64
		want         string
	}

	inputs := []testInput{
		{path: "required_workflows/abc.yml", sourceRepoID: 12345, want: "required/12345/required_workflows/abc.yml"},
		{path: "abc.yml", sourceRepoID: 12345, want: "required/12345/abc.yml"},
		{path: "abc.yml", sourceRepoID: 1234567891011, want: "required/1234567891011/abc.yml"},
		{path: "a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/foo.yml", sourceRepoID: 1234567891011, want: "required/1234567891011/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/foo.yml"},
		{path: "4567/workflow/abc.yml", sourceRepoID: 1234, want: "required/1234/4567/workflow/abc.yml"},
	}

	for _, input := range inputs {
		actualPath := ConstructRequiredWorkflowPath(input.path, input.sourceRepoID)
		assert.Equal(t, input.want, actualPath)
	}
}

func TestRemoveMetadataFromRequiredWorkflowPath(t *testing.T) {
	assert.Equal(t, "dynamic/prebuild/abc.yml", RemoveMetadataFromRequiredWorkflowPath("dynamic/prebuild/abc.yml"))
	assert.Equal(t, ".github/workflows/abc.yml", RemoveMetadataFromRequiredWorkflowPath(".github/workflows/abc.yml"))
	assert.Equal(t, ".github/workflow-lab/abc.yml", RemoveMetadataFromRequiredWorkflowPath(".github/workflow-lab/abc.yml"))
	assert.Equal(t, "required_workflows/abc.yml", RemoveMetadataFromRequiredWorkflowPath("required/1234/required_workflows/abc.yml"))
	assert.Equal(t, "abc.yml", RemoveMetadataFromRequiredWorkflowPath("required/1234/abc.yml"))
	assert.Equal(t, "a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/foo.yml", RemoveMetadataFromRequiredWorkflowPath("required/1234567891011/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/foo.yml"))
}

func TestAllowedEventForRulesetWorkflows(t *testing.T) {
	type testInput struct {
		event            string
		allowedWorkflows bool
		name             string
	}

	inputs := []testInput{
		{
			name:             "With a pull request event",
			event:            flowevents.PullRequest,
			allowedWorkflows: true,
		},
		{
			name:             "With pull request target event",
			event:            flowevents.PullRequestTarget,
			allowedWorkflows: true,
		},
		{
			name:             "With merge group event",
			event:            flowevents.MergeGroup,
			allowedWorkflows: true,
		},
		{
			name:             "With a workflow dispatch event",
			event:            flowevents.WorkflowDispatch,
			allowedWorkflows: false,
		},
	}

	for _, input := range inputs {
		t.Run(input.name, func(t *testing.T) {
			assert.Equal(t, input.allowedWorkflows, IsEventAllowedForWorkflowRulesets(input.event))
		})
	}
}
