package expressions

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/github/actions-expressions/go/data"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/build"
	"github.com/github/launch/workflowparser"
)

type testData struct {
	parsedWorkflow *workflowparser.Workflow
	wfb            *build.WorkflowBuild
	secretSource   string
	wantBytes      []byte
	ctx            *data.Dictionary
}

func TestNewContext(t *testing.T) {
	tests := []struct {
		name      string
		data      *testData
		numInputs int
	}{
		{
			name:      "push event (not workflow dispatch)",
			data:      newTestData(t, flowevents.Push),
			numInputs: 0,
		},
		{
			name:      "workflow dispatch",
			data:      newTestData(t, flowevents.WorkflowDispatch),
			numInputs: 4,
		},
		{
			name:      "dynamic workflow",
			data:      newTestData(t, flowevents.Dynamic),
			numInputs: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotObj, err := NewContext(context.Background(), observability.NewNullObservability(), tt.data.parsedWorkflow, tt.data.wfb, tt.data.secretSource, map[string]string{"Var": "Val"})
			require.NoError(t, err)
			inputs, ok := gotObj.Get("inputs")
			require.True(t, ok)

			inputsDict, ok := inputs.(*data.Dictionary)

			require.Equal(t, tt.numInputs, len(inputsDict.Pairs()))

			gotBytes, err := json.MarshalIndent(gotObj, "", "  ")
			require.NoError(t, err)
			// Compare JSON for a better error message (includes nicely formatted diff)
			require.Equal(t, string(tt.data.wantBytes), string(gotBytes))
		})
	}
}

func TestNewInputsContext(t *testing.T) {
	tests := []struct {
		name         string
		data         *testData
		allowDynamic bool
		numInputs    int
	}{
		{
			name:         "push event has no inputs",
			data:         newTestData(t, flowevents.Push),
			numInputs:    0,
			allowDynamic: false,
		},
		{
			name:         "workflow dispatch has inputs",
			data:         newTestData(t, flowevents.WorkflowDispatch),
			numInputs:    4,
			allowDynamic: false,
		},
		{
			name:         "dynamic workflow has no inputs if allowDynamic is false",
			data:         newTestData(t, flowevents.Dynamic),
			numInputs:    0,
			allowDynamic: false,
		},
		{
			name:         "dynamic workflow has 5 inputs if allowDynamic is true, as all passed in inputs are included",
			data:         newTestData(t, flowevents.Dynamic),
			numInputs:    5,
			allowDynamic: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			githubCtx, ok := tt.data.ctx.Get("github")
			require.True(t, ok)

			githubCtxDict := githubCtx.(*data.Dictionary)

			inputTypes := map[string]string{}
			onEvent, _ := tt.data.parsedWorkflow.OnForEvent(tt.data.wfb.Event)

			if onEvent.Inputs != nil {
				for inputName, inputDef := range *onEvent.Inputs {
					inputTypes[inputName] = strings.ToLower(inputDef.Type)
				}
			}

			gotObj := NewInputsContext(inputTypes, tt.data.wfb, githubCtxDict, tt.allowDynamic)

			require.Equal(t, tt.numInputs, len(gotObj.Pairs()))
		})
	}
}

func newTestData(t *testing.T, event string) *testData {
	workflow := `
on:
  workflow_dispatch:
    inputs:
      opt1:
        description: option 1 desc
        type: boolean
      opt2:
        description: option 2 desc
        type: boolean
      str1:
        description: string 1 desc
      str2:
        description: string 2 desc
        type: text
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
`
	resolvedFile := types.ResolvedFile{
		Text: workflow,
	}
	parsedWorkflow, err := workflowparser.Parse(context.Background(), resolvedFile, types.WorkflowFeatureFlags{}, nil, nil, 0, nil)
	require.NoError(t, err)
	wfb := &build.WorkflowBuild{
		CheckoutRef:          types.NewBranchRef("main"),
		CheckoutRefProtected: true,
		CheckoutSHA:          types.CommitSha("1234567890123456789012345678901234567890"),
		Event:                event,
		EventPayload: []byte(`{
  "ref": "refs/heads/main",
  "before": "5311a2edf010dae0f39fe38af4c9c8cf3cc46228",
  "after": "289345eeab3bfbf8a1651f9668cf5ca04dffa550",
  "inputs": {
    "opt1": "TrUe",
    "opt2": "not a bool",
    "str1": "string 1 val",
    "str2": "string 2 val",
    "notdefined": "asdf"
  }
}`),
		RunEnvironment: build.RunEnvironment{
			Repository:               types.RepositoryFullName{Owner: "some-owner", Name: "some-repo"},
			RepositoryDatabaseID:     123,
			OwnerDatabaseID:          234,
			GitURL:                   "git://github.com/some-owner/some-repo.git",
			WorkflowRunID:            345,
			WorkflowRunNumber:        456,
			RetentionDays:            567,
			WorkflowRunAttempt:       678,
			ActionsCacheSizeLimit:    789,
			RepositoryVisibility:     "Public",
			ExecutingActorDatabaseID: 890,
			ExecutingActor:           "some-actor",
			Workflow:                 "some-workflow",
			HeadRef:                  types.NewBranchRef("some-head-ref"),
			BaseRef:                  types.NewBranchRef("some-base-ref"),
			Event:                    event,
			ServerURL:                "https://github.com/",
			APIURL:                   "https://api.github.com/",
			GraphQLURL:               "https://api.github.com/graphql/",
			TriggeringActor:          "some-triggering-actor",
			WorkflowRef:              "my-org/my-repo/.github/workflows/foo.yml@main",
			WorkflowSha:              "1234567890",
		},
	}
	secretSource := "Actions"

	wantObj := data.NewDictionary(
		data.Pair{
			Key: "github",
			Value: data.NewDictionary(
				data.Pair{Key: "ref", Value: data.NewString("refs/heads/main")},
				data.Pair{Key: "sha", Value: data.NewString("1234567890123456789012345678901234567890")},
				data.Pair{Key: "repository", Value: data.NewString("some-owner/some-repo")},
				data.Pair{Key: "repository_owner", Value: data.NewString("some-owner")},
				data.Pair{Key: "repository_owner_id", Value: data.NewString("234")},
				data.Pair{Key: "repositoryUrl", Value: data.NewString("git://github.com/some-owner/some-repo.git")},
				data.Pair{Key: "run_id", Value: data.NewString("345")},
				data.Pair{Key: "run_number", Value: data.NewString("456")},
				data.Pair{Key: "retention_days", Value: data.NewString("567")},
				data.Pair{Key: "run_attempt", Value: data.NewString("678")},
				data.Pair{Key: "artifact_cache_size_limit", Value: data.NewString("789")},
				data.Pair{Key: "repository_visibility", Value: data.NewString("public")},
				data.Pair{Key: "actor_id", Value: data.NewString("890")},
				data.Pair{Key: "actor", Value: data.NewString("some-actor")},
				data.Pair{Key: "workflow", Value: data.NewString("some-workflow")},
				data.Pair{Key: "head_ref", Value: data.NewString("refs/heads/some-head-ref")},
				data.Pair{Key: "base_ref", Value: data.NewString("refs/heads/some-base-ref")},
				data.Pair{Key: "event_name", Value: data.NewString(event)},
				data.Pair{Key: "server_url", Value: data.NewString("https://github.com")},
				data.Pair{Key: "api_url", Value: data.NewString("https://api.github.com")},
				data.Pair{Key: "graphql_url", Value: data.NewString("https://api.github.com/graphql")},
				data.Pair{Key: "ref_name", Value: data.NewString("main")},
				data.Pair{Key: "ref_protected", Value: data.NewBoolean(true)},
				data.Pair{Key: "ref_type", Value: data.NewString("branch")},
				data.Pair{Key: "secret_source", Value: data.NewString("Actions")},
				data.Pair{
					Key: "event",
					Value: data.NewDictionary(
						data.Pair{Key: "ref", Value: data.NewString("refs/heads/main")},
						data.Pair{Key: "before", Value: data.NewString("5311a2edf010dae0f39fe38af4c9c8cf3cc46228")},
						data.Pair{Key: "after", Value: data.NewString("289345eeab3bfbf8a1651f9668cf5ca04dffa550")},
						data.Pair{
							Key: "inputs",
							Value: data.NewDictionary(
								data.Pair{Key: "opt1", Value: data.NewString("TrUe")},
								data.Pair{Key: "opt2", Value: data.NewString("not a bool")},
								data.Pair{Key: "str1", Value: data.NewString("string 1 val")},
								data.Pair{Key: "str2", Value: data.NewString("string 2 val")},
								data.Pair{Key: "notdefined", Value: data.NewString("asdf")},
							),
						},
					),
				},
				data.Pair{Key: "workflow_ref", Value: data.NewString("my-org/my-repo/.github/workflows/foo.yml@main")},
				data.Pair{Key: "workflow_sha", Value: data.NewString("1234567890")},
				data.Pair{Key: "repository_id", Value: data.NewString("123")},
				data.Pair{Key: "triggering_actor", Value: data.NewString("some-triggering-actor")},
			),
		},
		data.Pair{
			Key:   "inputs",
			Value: data.NewDictionary(),
		},
		data.Pair{
			Key:   "vars",
			Value: data.NewDictionary(data.Pair{Key: "Var", Value: data.NewString("Val")}),
		},
	)
	if event == flowevents.WorkflowDispatch {
		inputs, _ := wantObj.Get("inputs")
		inputsDict := inputs.(*data.Dictionary)
		inputsDict.Add("opt1", data.NewBoolean(true))
		inputsDict.Add("opt2", data.NewBoolean(false))
		inputsDict.Add("str1", data.NewString("string 1 val"))
		inputsDict.Add("str2", data.NewString("string 2 val"))
	}

	wantBytes, err := json.MarshalIndent(wantObj, "", "  ")
	require.NoError(t, err)
	require.NotEqual(t, []byte("{}"), wantBytes)
	return &testData{
		parsedWorkflow: parsedWorkflow,
		wfb:            wfb,
		secretSource:   secretSource,
		wantBytes:      wantBytes,
		ctx:            wantObj,
	}
}
