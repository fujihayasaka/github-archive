package hydro

import (
	"testing"
	"time"

	"github.com/golang/protobuf/proto"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	hydro "github.com/github/launch/hydro/schemas/github/actions/v0"
	hydro_schemas_github_v1_entities "github.com/github/launch/hydro/schemas/github/v1/entities"
)

func TestMessageEncoder(t *testing.T) {
	t.Run("Test with single WorkflowExecution Message", func(tt *testing.T) {
		messages := []proto.Message{
			&hydro.WorkflowExecution{
				ExternalProvider:          hydro.WorkflowExecution_AZP,
				ExternalProviderReference: "my-sample-project-191923",
				WorkflowStartTime:         newTimestampFromString(tt, "2014-10-31T00:00:00.000Z"),
				WorkflowEndTime:           newTimestampFromString(tt, "2014-10-31T23:59:59.999Z"),
			},
		}
		json, err := encodeProtoMessagesAsJSON(messages, "")
		require.NoError(tt, err)
		expected := `{
			"events": [
				{
					"schema": "github.actions.v0.WorkflowExecution",
					"value": "{\"workflowStartTime\":\"2014-10-31T00:00:00Z\",\"workflowEndTime\":\"2014-10-31T23:59:59.999Z\",\"externalProvider\":\"AZP\",\"externalProviderReference\":\"my-sample-project-191923\"}"
				}
			]
		}`
		require.JSONEq(tt, expected, json)
	})
	t.Run("Test with single WorkflowExecution Message and a partition key", func(tt *testing.T) {
		messages := []proto.Message{
			&hydro.WorkflowExecution{
				ExternalProvider:          hydro.WorkflowExecution_AZP,
				ExternalProviderReference: "my-sample-project-191923",
				WorkflowStartTime:         newTimestampFromString(tt, "2014-10-31T00:00:00.000Z"),
				WorkflowEndTime:           newTimestampFromString(tt, "2014-10-31T23:59:59.999Z"),
			},
		}
		json, err := encodeProtoMessagesAsJSON(messages, "a-partition-key")
		require.NoError(tt, err)
		expected := `{
			"events": [
				{
					"schema": "github.actions.v0.WorkflowExecution",
					"value": "{\"workflowStartTime\":\"2014-10-31T00:00:00Z\",\"workflowEndTime\":\"2014-10-31T23:59:59.999Z\",\"externalProvider\":\"AZP\",\"externalProviderReference\":\"my-sample-project-191923\"}",
					"partition_key": "a-partition-key"
				}
			]
		}`
		require.JSONEq(tt, expected, json)
	})
	t.Run("Test with single RepoEnabled Message", func(tt *testing.T) {
		messages := []proto.Message{
			&hydro.RepoEnabled{
				Actor: &hydro_schemas_github_v1_entities.User{
					Id:    16631042,
					Login: "joshmgross",
				},
				Repository: &hydro_schemas_github_v1_entities.Repository{
					Id:   244068992,
					Name: "dotfiles",
				},
			},
		}
		json, err := encodeProtoMessagesAsJSON(messages, "")
		require.NoError(tt, err)
		expected := `{
			"events": [
				{
					"schema": "github.actions.v0.RepoEnabled",
					"value": "{\"actor\":{\"id\":16631042,\"login\":\"joshmgross\"},\"repository\":{\"id\":244068992,\"name\":\"dotfiles\"}}"
				}
			]
		}`
		require.JSONEq(tt, expected, json)
	})
	t.Run("Test with multiple messages", func(tt *testing.T) {
		messages := []proto.Message{
			&hydro.WorkflowExecution{
				ExternalProvider:          hydro.WorkflowExecution_AZP,
				ExternalProviderReference: "my-sample-project-191923",
				WorkflowStartTime:         newTimestampFromString(tt, "2014-10-31T00:00:00.000Z"),
				WorkflowEndTime:           newTimestampFromString(tt, "2014-10-31T23:59:59.999Z"),
			},
			&hydro.RepoEnabled{
				Actor: &hydro_schemas_github_v1_entities.User{
					Id:    16631042,
					Login: "joshmgross",
				},
				Repository: &hydro_schemas_github_v1_entities.Repository{
					Id:   244068992,
					Name: "dotfiles",
				},
			},
		}
		json, err := encodeProtoMessagesAsJSON(messages, "")
		require.NoError(tt, err)
		expected := `{
			"events": [
				{
					"schema": "github.actions.v0.WorkflowExecution",
					"value": "{\"workflowStartTime\":\"2014-10-31T00:00:00Z\",\"workflowEndTime\":\"2014-10-31T23:59:59.999Z\",\"externalProvider\":\"AZP\",\"externalProviderReference\":\"my-sample-project-191923\"}"
				},
				{
					"schema": "github.actions.v0.RepoEnabled",
					"value": "{\"actor\":{\"id\":16631042,\"login\":\"joshmgross\"},\"repository\":{\"id\":244068992,\"name\":\"dotfiles\"}}"
				}
			]
		}`
		require.JSONEq(tt, expected, json)
	})
}

func TestSchemaNameGeneration(t *testing.T) {
	t.Run("Test with WorkflowExecution Message", func(tt *testing.T) {
		schema := getSchemaNameForMessage(&hydro.WorkflowExecution{})
		require.Equal(tt, "github.actions.v0.WorkflowExecution", schema)
	})
}

func newTimestampFromString(t *testing.T, str string) *timestamp.Timestamp {
	time, err := time.Parse(time.RFC3339, str)
	require.NoError(t, err)
	stamp := timestamppb.New(time)
	require.NoError(t, err)
	return stamp
}
