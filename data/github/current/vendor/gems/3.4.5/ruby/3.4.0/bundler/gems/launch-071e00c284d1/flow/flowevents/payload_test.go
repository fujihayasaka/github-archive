package flowevents

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/github/actions-expressions/go/data"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability"
)

func TestWorkflowEventPayload_Dynamic(t *testing.T) {
	event := &DynamicEvent{
		Workflow:        "some workflow",
		Ref:             "ref",
		Inputs:          map[string]string{"name": "monalisa"},
		IntegrationName: "dependabot",
		WorkflowName:    "some-workflow",
		Slug:            "some-slug",
	}
	expected := map[string]any{"ref": "ref", "inputs": map[string]any{"name": "monalisa"}}

	payload, err := json.Marshal(event)
	require.NoError(t, err)

	workflowPayload, err := WorkflowEventPayload(Dynamic, payload)
	require.NoError(t, err)

	if !reflect.DeepEqual(workflowPayload, expected) {
		t.Errorf("WorkflowEventPayload() = %v, want %v", workflowPayload, expected)
	}
}

func TestWorkflowEventPayload_Push(t *testing.T) {
	pushPayload, err := os.ReadFile(filepath.Join("fixtures", "push.json"))
	require.NoError(t, err)

	var pushWorkflowPayload map[string]any
	err = json.Unmarshal(pushPayload, &pushWorkflowPayload)
	require.NoError(t, err)

	workflowPayload, err := WorkflowEventPayload(Dynamic, pushPayload)
	require.NoError(t, err)

	if !reflect.DeepEqual(workflowPayload, pushWorkflowPayload) {
		t.Error("WorkflowEventPayload should not modify push payload")
	}
}

func TestWorkflowEventContext_Dynamic(t *testing.T) {
	eventObj := &DynamicEvent{
		Workflow:        "some workflow",
		Ref:             "ref",
		Inputs:          map[string]string{"name": "monalisa"},
		IntegrationName: "dependabot",
		WorkflowName:    "some-workflow",
		Slug:            "some-slug",
	}
	eventBytes, err := json.Marshal(eventObj)
	require.NoError(t, err)

	wantObj := data.NewDictionary(
		data.Pair{
			Key:   "ref",
			Value: data.NewString("ref"),
		},
		data.Pair{
			Key: "inputs",
			Value: data.NewDictionary(
				data.Pair{
					Key:   "name",
					Value: data.NewString("monalisa"),
				},
			),
		},
	)
	wantBytes, err := json.MarshalIndent(wantObj, "", "  ")
	require.NoError(t, err)

	gotObj, err := WorkflowEventContext(context.Background(), observability.NewNullObservability(), Dynamic, eventBytes)
	require.NotNil(t, gotObj)
	require.NoError(t, err)
	gotBytes, err := json.MarshalIndent(gotObj, "", "  ")
	require.NoError(t, err)

	// Compare JSON for a better error message (includes nicely formatted diff)
	require.Equal(t, string(wantBytes), string(gotBytes))
}

func TestWorkflowEventContext_Push(t *testing.T) {
	eventBytes, err := os.ReadFile(filepath.Join("fixtures", "push.json"))
	require.NoError(t, err)

	wantObj, err := data.Decode(string(eventBytes))
	require.NoError(t, err)
	wantBytes, err := json.MarshalIndent(wantObj, "", "  ")
	require.NoError(t, err)

	gotObj, err := WorkflowEventContext(context.Background(), observability.NewNullObservability(), Push, eventBytes)
	require.NotNil(t, gotObj)
	require.NoError(t, err)
	gotBytes, err := json.MarshalIndent(gotObj, "", "  ")
	require.NoError(t, err)

	// Compare JSON for a better error message (includes nicely formatted diff)
	require.Equal(t, string(wantBytes), string(gotBytes))
}
