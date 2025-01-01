package workflowparser

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	launchutils "github.com/github/launch/utils"
)

func TestConvertParsedModelToConfiguration(t *testing.T) {
	path := "workflow.yml"
	missingSteps := "No steps defined in `steps` and no workflow called in `uses` for the following jobs: one"

	tests := []struct {
		desc         string
		workflow     string
		parsed       func(workflow string) *model.Configuration
		featureFlags types.WorkflowFeatureFlags
		wfSrc        WorkflowSource
		errorMessage *string
	}{
		{
			desc: "mix of repository and ignored actions",
			workflow: `on: push

jobs:
  one:
    steps:
    - uses: ./my-action
    - run: thing
    - uses: some/repo@v1.0.0
    - uses: docker://actions/npm@master`,
			parsed: func(workflow string) *model.Configuration {
				return &model.Configuration{
					Workflows: []*model.Workflow{
						{
							Identifier: path,
							Path:       path,
							On: &model.OnEvent{
								Event: "push",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
					},
					Actions: []*model.Action{
						{
							Uses: &model.UsesRepository{
								Repository: "some/repo",
								Path:       "",
								Ref:        "v1.0.0",
							},
						},
						{
							Identifier: "",
							Uses: &model.UsesDockerImage{
								Image: "actions/npm@master",
							},
						},
						{
							Identifier: "",
							Uses: &model.UsesPath{
								Path: "my-action",
							},
						},
					},
				}
			},
		},
		{
			desc: "empty steps list",
			workflow: `on: push

jobs:
  one:
    steps: []`,
			parsed: func(workflow string) *model.Configuration {
				return &model.Configuration{
					Workflows: []*model.Workflow{},
				}
			},
			errorMessage: &missingSteps,
		},
		{
			desc: "has name",
			workflow: `on: push

name: the name
jobs:
  one:
    steps:
    - uses: some/repo@master`,
			parsed: func(workflow string) *model.Configuration {
				return &model.Configuration{
					Workflows: []*model.Workflow{
						{
							Identifier: "the name",
							Path:       path,
							On: &model.OnEvent{
								Event: "push",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
					},
					Actions: []*model.Action{
						{
							Uses: &model.UsesRepository{
								Repository: "some/repo",
								Path:       "",
								Ref:        "master",
							},
						},
					},
				}
			},
		},
		{
			desc: "multiple triggers",
			workflow: `on: ['push', 'issues']

jobs:
  one:
    steps:
    - uses: some/repo@master`,
			parsed: func(workflow string) *model.Configuration {
				return &model.Configuration{
					Workflows: []*model.Workflow{
						{
							Identifier: path,
							Path:       path,
							On: &model.OnEvent{
								Event: "push",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
						{
							Identifier: path,
							Path:       path,
							On: &model.OnEvent{
								Event: "issues",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
					},
					Actions: []*model.Action{
						{
							Uses: &model.UsesRepository{
								Repository: "some/repo",
								Path:       "",
								Ref:        "master",
							},
						},
					},
				}
			},
		},
		{
			desc: "multiple triggers multiple lines",
			workflow: `
on:
  push:
  issues:
jobs:
  one:
    steps:
    - uses: some/repo@master`,
			parsed: func(workflow string) *model.Configuration {
				return &model.Configuration{
					Workflows: []*model.Workflow{
						{
							Identifier: path,
							Path:       path,
							On: &model.OnEvent{
								Event: "push",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
						{
							Identifier: path,
							Path:       path,
							On: &model.OnEvent{
								Event: "issues",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
					},
					Actions: []*model.Action{
						{
							Uses: &model.UsesRepository{
								Repository: "some/repo",
								Path:       "",
								Ref:        "master",
							},
						},
					},
				}
			},
		},
		{
			desc: "cron",
			workflow: `on:
  schedule:
  - cron: "* * * * *"

jobs:
  one:
    steps: ["echo hi"]`,
			parsed: func(workflow string) *model.Configuration {
				return &model.Configuration{
					Workflows: []*model.Workflow{
						{
							Identifier: path,
							Path:       path,
							On: &model.OnSchedule{
								Expression: "* * * * *",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
					},
					Actions: []*model.Action{},
				}
			},
		},
		{
			desc: "with repository dispatch and schedule event",
			workflow: `
on:
  repository_dispatch:
  schedule:
  - cron: "* * * * *"

jobs:
  one:
    steps: ["echo hi"]`,
			parsed: func(workflow string) *model.Configuration {
				return &model.Configuration{
					Workflows: []*model.Workflow{
						{
							Identifier: path,
							Path:       path,
							On: &model.OnEvent{
								Event: "repository_dispatch",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
						{
							Identifier: path,
							Path:       path,
							On: &model.OnSchedule{
								Expression: "* * * * *",
							},
							File: types.ResolvedFile{
								Path: path,
								Text: workflow,
							},
							FileReference: types.NewWorkflowFileReference(path),
						},
					},
					Actions: []*model.Action{},
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			ctx := context.Background()
			wfSrc := tt.wfSrc
			if wfSrc == nil {
				wfSrc = NullWorkflowSource{}
			}
			parsed, err := Parse(ctx, types.ResolvedFile{Text: tt.workflow, Path: "workflow.yml"}, tt.featureFlags, wfSrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			if tt.errorMessage != nil {
				assert.EqualError(t, err, *tt.errorMessage)
				return
			}

			require.NoError(t, err)
			require.NotNil(t, parsed)
			wf := WorkflowToConfiguration(parsed)

			expectedParsed := tt.parsed(tt.workflow)
			assert.ElementsMatch(t, expectedParsed.Workflows, wf.Workflows, "workflows unexpected %+v", wf.Workflows)
			assert.ElementsMatch(t, expectedParsed.Actions, wf.Actions, "actions unexpected %+v", wf.Actions)
		})
	}
}

func TestBuildReferencedWorkflowsJSON(t *testing.T) {
	tests := []struct {
		desc         string
		workflow     types.ResolvedFile
		wfSrc        WorkflowSource
		featureFlags types.WorkflowFeatureFlags
		json         string
	}{
		{
			desc: "normal workflow",
			workflow: types.ResolvedFile{Path: "some/repo/.github/workflows/w.yml", Text: `on: push

jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
				SHA: "aabbcc",
				Ref: "main"},
			json: "",
		},
		{
			desc: "simple reusable workflow",
			workflow: types.ResolvedFile{
				Path: "some/repo/.github/workflows/w.yml",
				Text: `on: push
jobs:
  a:
    uses: some/repo/.github/workflows/another.yml@main`,
				SHA: "aabbcc",
				Ref: "main",
			},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"some/repo/.github/workflows/another.yml@main": {
						Content: `
name: Called Workflow
on:
  workflow_call:
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
						RefType: "refs/heads/",
						Sha:     "aabbcc",
					},
				},
			},
			featureFlags: types.WorkflowFeatureFlags{},
			json:         "[{\"path\":\"some/repo/.github/workflows/another.yml@main\",\"sha\":\"aabbcc\",\"ref\":\"refs/heads/main\"}]",
		},
		{
			desc: "no duplicate referenced workflows in same workflow",
			workflow: types.ResolvedFile{Path: "some/repo/.github/workflows/w.yml", Text: `on: push
jobs:
  a:
    uses: some/repo/.github/workflows/another.yml@main
  b:
    uses: some/repo/.github/workflows/another.yml@main`,
				SHA: "aabbcc",
				Ref: "main"},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"some/repo/.github/workflows/another.yml@main": {
						Content: `
name: Called Workflow
on:
  workflow_call:
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
						RefType: "refs/heads/",
						Sha:     "aabbcc",
					},
				},
			},
			featureFlags: types.WorkflowFeatureFlags{},
			json:         "[{\"path\":\"some/repo/.github/workflows/another.yml@main\",\"sha\":\"aabbcc\",\"ref\":\"refs/heads/main\"}]",
		},
		{
			desc: "nested reusable workflow",
			workflow: types.ResolvedFile{Path: "some/repo/.github/workflows/w.yml", Text: `on: push
jobs:
  a:
    uses: some/repo/.github/workflows/a.yml@main`,
				SHA: "aabbcc",
				Ref: "main"},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"some/repo/.github/workflows/a.yml@main": {
						Content: `
name: Called Workflow A
on:
  workflow_call:
jobs:
  b:
    uses: some/repo/.github/workflows/b.yml@v1`,
						RefType: "refs/heads/",
						Sha:     "aabbcc",
					},
					"some/repo/.github/workflows/b.yml@v1": {
						Content: `
name: Called Workflow B
on:
  workflow_call:
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
						RefType: "refs/tags/",
						Sha:     "ppqqrr",
					},
				},
			},
			featureFlags: types.WorkflowFeatureFlags{},
			json:         "[{\"path\":\"some/repo/.github/workflows/a.yml@main\",\"sha\":\"aabbcc\",\"ref\":\"refs/heads/main\"},{\"path\":\"some/repo/.github/workflows/b.yml@v1\",\"sha\":\"ppqqrr\",\"ref\":\"refs/tags/v1\"}]",
		},
		{
			desc: "nested reusable workflow max depth",
			workflow: types.ResolvedFile{Path: "some/repo/.github/workflows/w.yml", Text: `on: push
jobs:
  a:
    uses: some/repo/.github/workflows/a.yml@main`,
				SHA: "aabbcc",
				Ref: "main"},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"some/repo/.github/workflows/a.yml@main": {
						Content: `
name: Called Workflow A
on:
  workflow_call:
jobs:
  b:
    uses: some/repo/.github/workflows/b.yml@v1`,
						RefType: "refs/heads/",
						Sha:     "aabbcc",
					},
					"some/repo/.github/workflows/b.yml@v1": {
						Content: `
name: Called Workflow B
on:
  workflow_call:
jobs:
  c:
    uses: some/repo/.github/workflows/c.yml@v1`,
						RefType: "refs/tags/",
						Sha:     "ppqqrr",
					},
					"some/repo/.github/workflows/c.yml@v1": {
						Content: `
name: Called Workflow C
on:
  workflow_call:
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
						RefType: "refs/tags/",
						Sha:     "ppqqrr",
					},
				},
			},
			featureFlags: types.WorkflowFeatureFlags{},
			json:         "[{\"path\":\"some/repo/.github/workflows/a.yml@main\",\"sha\":\"aabbcc\",\"ref\":\"refs/heads/main\"},{\"path\":\"some/repo/.github/workflows/b.yml@v1\",\"sha\":\"ppqqrr\",\"ref\":\"refs/tags/v1\"},{\"path\":\"some/repo/.github/workflows/c.yml@v1\",\"sha\":\"ppqqrr\",\"ref\":\"refs/tags/v1\"}]",
		},
		{
			desc: "no duplicate referenced workflows in nested workflows",
			workflow: types.ResolvedFile{Path: "some/repo/.github/workflows/w.yml", Text: `on: push
jobs:
  a:
    uses: some/repo/.github/workflows/a.yml@main
  b:
    uses: some/repo/.github/workflows/b.yml@main`,
				SHA: "aabbcc",
				Ref: "main"},
			wfSrc: &StubWorkflowSource{
				SourceMap: map[string]WorkflowDetails{
					"some/repo/.github/workflows/a.yml@main": {
						Content: `
name: Called Workflow
on:
  workflow_call:
jobs:
  b:
    uses: some/repo/.github/workflows/b.yml@main`,
						RefType: "refs/heads/",
						Sha:     "aabbcc",
					},
					"some/repo/.github/workflows/b.yml@main": {
						Content: `
name: Called Workflow
on:
  workflow_call:
jobs:
  c:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
						RefType: "refs/heads/",
						Sha:     "aabbcc",
					},
				},
			},
			featureFlags: types.WorkflowFeatureFlags{},
			json:         "[{\"path\":\"some/repo/.github/workflows/a.yml@main\",\"sha\":\"aabbcc\",\"ref\":\"refs/heads/main\"},{\"path\":\"some/repo/.github/workflows/b.yml@main\",\"sha\":\"aabbcc\",\"ref\":\"refs/heads/main\"}]",
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			ctx := context.Background()
			var w *Workflow
			w, _ = ParseWithCalledWorkflows(ctx, tt.workflow, tt.featureFlags, tt.wfSrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewTestObservability())
			json, _ := w.BuildReferencedWorkflowsJSON()

			// Because the json is converted from a map, ordering is not always consistent so we convert back to map and check if the maps are equal
			expectedMap := convertJSONToRefWorkflowMap(tt.json)
			actualMap := convertJSONToRefWorkflowMap(json)

			assert.Equal(t, expectedMap, actualMap)
		})
	}
}

func convertJSONToRefWorkflowMap(jsonString string) map[string]ReferencedWorkflow {
	var referencedWorkflows []ReferencedWorkflow
	jsonByte := []byte(jsonString)
	json.Unmarshal(jsonByte, &referencedWorkflows)

	referencedWorkflowsMap := make(map[string]ReferencedWorkflow)
	for _, workflow := range referencedWorkflows {
		referencedWorkflowsMap[workflow.Path] = workflow
	}

	return referencedWorkflowsMap
}
