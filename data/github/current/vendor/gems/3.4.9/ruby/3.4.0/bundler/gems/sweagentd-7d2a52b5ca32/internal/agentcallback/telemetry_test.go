package agentcallback

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/testutils"
	"github.com/stretchr/testify/require"
)

func TestJobEventUnmarshall(t *testing.T) {
	t.Run("unmarshall job event - telemetry", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-telemetry.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.Equal(t, "telemetry", jobEvent.Kind)
		require.Equal(t, "get_completion_with_tools_turn", jobEvent.Telemetry.Event)

		require.Equal(t, 4, len(jobEvent.Telemetry.Properties))
		propertyValue, exists := jobEvent.Telemetry.Properties["model"]
		require.True(t, exists, "expected model to exist in properties")
		require.NotNil(t, propertyValue, "Claude 3.7 Sonnet (Preview)")

		require.Equal(t, 12, len(jobEvent.Telemetry.Metrics))
		metricValue, exists := jobEvent.Telemetry.Metrics["turnDurationMs"]
		require.True(t, exists, "expected turn_duration_ms to exist in metrics")
		require.NotNil(t, metricValue, 12400)
	})

	t.Run("unmarshal job event - log", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-log.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.Equal(t, "log", jobEvent.Kind)
		require.Contains(t, jobEvent.Message.StringValue, "undefined")

		require.Equal(t, "", jobEvent.Message.Role)
		require.Equal(t, "", jobEvent.Message.ToolCallID)
		require.Nil(t, jobEvent.Message.ToolCalls)
	})

	t.Run("unmarshal job event - message user", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-message-user.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.Equal(t, "message", jobEvent.Kind)
		require.Equal(t, "user", jobEvent.Message.Role)
	})

	t.Run("unmarshall job event - message tool", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-message-tool.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.Equal(t, "message", jobEvent.Kind)
		require.Equal(t, "tool", jobEvent.Message.Role)
		require.Equal(t, "tooluse_AtGRSdiVQAScJE_17B7oPg", jobEvent.Message.ToolCallID)

		require.Equal(t, "Claude 3.7 Sonnet", jobEvent.ModelCall.Model)
		require.Equal(t, "c5973912-25d8-4e9d-b604-21a66f91ce3b", jobEvent.ModelCall.APIID)

		require.Equal(t, 8, len(jobEvent.Telemetry.Properties))
		propertyValue, exists := jobEvent.Telemetry.Properties["toolName"]
		require.True(t, exists, "expected toolName to exist in properties")
		require.NotNil(t, propertyValue, "reply_to_comment")

		require.Equal(t, 4, len(jobEvent.Telemetry.Metrics))
		metricValue, exists := jobEvent.Telemetry.Metrics["durationMs"]
		require.True(t, exists, "expected durationMs to exist in metrics")
		require.NotNil(t, metricValue, 2967)
		require.Contains(t, jobEvent.Message.Content, "My Content")
	})

	t.Run("unmarshal job event - message assistant", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-message-assistant.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.Equal(t, "message", jobEvent.Kind)
		require.Equal(t, "assistant", jobEvent.Message.Role)
		require.Equal(t, 1, len(jobEvent.Message.ToolCalls))
		require.Equal(t, "function", jobEvent.Message.ToolCalls[0].Type)
	})

	t.Run("unmarshal job event - response", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-response.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.NotNil(t, jobEvent.Kind)
		require.Equal(t, "response", jobEvent.Kind)
		require.Equal(t, "assistant", jobEvent.Response.Role)
	})

	t.Run("unmarshal job event - model call success", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-model_call_success.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.NotNil(t, jobEvent.Kind)
		require.Equal(t, "model_call_success", jobEvent.Kind)

		require.Equal(t, "72f7b1a0-1fe7-454c-a6b8-338cd17970e3", jobEvent.ResponseChunk.ID)

		require.Equal(t, "Claude 3.7 Sonnet", jobEvent.ResponseChunk.Model)

		require.Equal(t, int64(69), jobEvent.ResponseChunk.Usage.CompletionTokens)
		require.Equal(t, int64(6963), jobEvent.ResponseChunk.Usage.PromptTokens)
		require.Equal(t, int64(7032), jobEvent.ResponseChunk.Usage.TotalTokens)

		require.Equal(t, "chat.completion.chunk", jobEvent.ResponseChunk.Object)

		require.NotNil(t, jobEvent.ResponseChunk)

		require.Equal(t, "tool_calls", jobEvent.ResponseChunk.Choices[0].FinishReason)
		require.Equal(t, "assistant", jobEvent.ResponseChunk.Choices[0].Delta.Role)

		require.Equal(t, "tool_calls", jobEvent.ResponseChunk.Choices[1].FinishReason)
		require.Equal(t, "assistant", jobEvent.ResponseChunk.Choices[1].Delta.Role)
		require.Equal(t, "bash", jobEvent.ResponseChunk.Choices[1].Delta.Toolcalls[0].Function.Name)
		require.Equal(t, "function", jobEvent.ResponseChunk.Choices[1].Delta.Toolcalls[0].Type)
		require.Equal(t, "tooluse_cqYOO6bbQvCuUYW5GhgISw", jobEvent.ResponseChunk.Choices[1].Delta.Toolcalls[0].ID)

		require.Equal(t, int64(5212), jobEvent.ModelCallDurationMs)
	})

	t.Run("unmarshal job event - model call failure", func(t *testing.T) {
		content := testutils.ReadFixture("../testutils/fixtures/job-event-model-call-failure.json")
		jobEvent := ProgressJobEvent{}
		err := json.Unmarshal([]byte(content), &jobEvent)

		require.NoError(t, err)
		require.NotNil(t, jobEvent.Kind)
		require.Equal(t, "model_call_failure", jobEvent.Kind)

		require.Empty(t, jobEvent.ResponseChunk.ID)

		require.NotNil(t, jobEvent.ModelCall)
		require.Equal(t, "claude-sonnet-4", jobEvent.ModelCall.Model)
		require.Equal(t, int64(400), jobEvent.ModelCall.Status)
		require.Equal(t, "0602:29277D:245ABBC:2CAE3B9:685970E1", jobEvent.ModelCall.RequestID)
		require.Contains(t, jobEvent.ModelCall.Error, "one or more attachments was not accessible")
		require.Equal(t, int64(339), jobEvent.ModelCallDurationMs)
	})
}

// counterCall represents a recorded counter call for testing
type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

// distributionCall represents a recorded distribution call for testing
type distributionCall struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

// setupMockStatter creates a MockStatter with counter and distribution tracking.
// Returns the observability exporters, counter calls slice, and distribution calls slice.
func setupMockStatter(withDistribution bool) (observability.Exporters, *[]counterCall, *[]distributionCall) {
	mockStatter := &observability.MockStatter{}

	counterCalls := []counterCall{}
	mockStatter.MockCounter = func(key string, tags stats.Tags, value int64) {
		counterCalls = append(counterCalls, counterCall{key, tags, value})
	}

	obsv := observability.NewNoopExporters()

	if withDistribution {
		distributionCalls := []distributionCall{}
		obsv.Statter = &mockStatterWithDistribution{
			MockStatter:       mockStatter,
			distributionCalls: &distributionCalls,
		}
		return obsv, &counterCalls, &distributionCalls
	}

	obsv.Statter = mockStatter
	return obsv, &counterCalls, nil
}

func TestStatCodeQLCheckerCompletion(t *testing.T) {
	t.Run("complete codeql metrics with all properties and metrics", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)

		// Create progress event with complete codeql telemetry
		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"codeql.language":                "go",
					"codeql.aborted":                 "false",
					"codeql.databaseCreationSuccess": "true",
					"codeql.analysisSuccess":         "true",
				},
				Metrics: map[string]float64{
					"codeql.databaseCreationTimeMs": 5000.0,
					"codeql.analysisTimeMs":         3000.0,
				},
			},
		}

		ctx := context.Background()
		progress.statCodeQLCheckerCompletion(ctx, obsv)

		// Verify counter calls
		require.Len(t, *counterCalls, 2)

		// Check database creation success counter
		require.Equal(t, "codeql.databaseCreationSuccess", (*counterCalls)[0].key)
		require.Equal(t, int64(1), (*counterCalls)[0].value)
		require.Equal(t, "go", (*counterCalls)[0].tags["codeql.language"])
		require.Equal(t, "false", (*counterCalls)[0].tags["codeql.aborted"])

		// Check analysis success counter
		require.Equal(t, "codeql.analysisSuccess", (*counterCalls)[1].key)
		require.Equal(t, int64(1), (*counterCalls)[1].value)
		require.Equal(t, "go", (*counterCalls)[1].tags["codeql.language"])
		require.Equal(t, "false", (*counterCalls)[1].tags["codeql.aborted"])

		// Verify distribution calls
		require.Len(t, *distributionCalls, 2)

		// Check database creation time distribution
		require.Equal(t, "codeql.databaseCreationTimeMs", (*distributionCalls)[0].key)
		require.Equal(t, 5*time.Second, (*distributionCalls)[0].duration)
		require.Equal(t, "go", (*distributionCalls)[0].tags["codeql.language"])
		require.Equal(t, "false", (*distributionCalls)[0].tags["codeql.aborted"])

		// Check analysis time distribution
		require.Equal(t, "codeql.analysisTimeMs", (*distributionCalls)[1].key)
		require.Equal(t, 3*time.Second, (*distributionCalls)[1].duration)
		require.Equal(t, "go", (*distributionCalls)[1].tags["codeql.language"])
		require.Equal(t, "false", (*distributionCalls)[1].tags["codeql.aborted"])
	})

	t.Run("codeql metrics with failures", func(t *testing.T) {
		obsv, counterCalls, _ := setupMockStatter(false)

		// Create progress event with codeql failures
		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"codeql.language":                "javascript",
					"codeql.aborted":                 "true",
					"codeql.databaseCreationSuccess": "false",
					"codeql.analysisSuccess":         "false",
				},
			},
		}

		ctx := context.Background()
		progress.statCodeQLCheckerCompletion(ctx, obsv)

		// Verify counter calls for failures
		require.Len(t, *counterCalls, 2)

		// Check database creation failure counter
		require.Equal(t, "codeql.databaseCreationFailure", (*counterCalls)[0].key)
		require.Equal(t, int64(1), (*counterCalls)[0].value)
		require.Equal(t, "javascript", (*counterCalls)[0].tags["codeql.language"])
		require.Equal(t, "true", (*counterCalls)[0].tags["codeql.aborted"])

		// Check analysis failure counter
		require.Equal(t, "codeql.analysisFailure", (*counterCalls)[1].key)
		require.Equal(t, int64(1), (*counterCalls)[1].value)
		require.Equal(t, "javascript", (*counterCalls)[1].tags["codeql.language"])
		require.Equal(t, "true", (*counterCalls)[1].tags["codeql.aborted"])
	})

	t.Run("unknown language and missing aborted flag", func(t *testing.T) {
		obsv, counterCalls, _ := setupMockStatter(false)

		// Create progress event with minimal properties
		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"codeql.databaseCreationSuccess": "true",
					"codeql.analysisSuccess":         "true",
				},
			},
		}

		ctx := context.Background()
		progress.statCodeQLCheckerCompletion(ctx, obsv)

		// Verify defaults are applied
		require.Len(t, *counterCalls, 2)

		// Check that default values are used
		require.Equal(t, "unknown", (*counterCalls)[0].tags["codeql.language"])
		require.Equal(t, "false", (*counterCalls)[0].tags["codeql.aborted"])
		require.Equal(t, "unknown", (*counterCalls)[1].tags["codeql.language"])
		require.Equal(t, "false", (*counterCalls)[1].tags["codeql.aborted"])
	})

	t.Run("missing properties and metrics", func(t *testing.T) {
		obsv, counterCalls, _ := setupMockStatter(false)

		// Create progress event with no relevant properties/metrics
		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{},
				Metrics:    map[string]float64{},
			},
		}

		ctx := context.Background()
		progress.statCodeQLCheckerCompletion(ctx, obsv)

		// Should not make any counter or distribution calls when properties are missing
		require.Len(t, *counterCalls, 0)
	})
}

// mockStatterWithDistribution extends MockStatter to capture DistributionMs calls
type mockStatterWithDistribution struct {
	*observability.MockStatter

	distributionCalls *[]distributionCall
}

func (m *mockStatterWithDistribution) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	*m.distributionCalls = append(*m.distributionCalls, distributionCall{key, tags, duration})
}
