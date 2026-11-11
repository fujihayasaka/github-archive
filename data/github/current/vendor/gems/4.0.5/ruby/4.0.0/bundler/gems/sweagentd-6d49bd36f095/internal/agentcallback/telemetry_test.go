package agentcallback

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
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

func TestStatMCPServerSetup(t *testing.T) {
	t.Run("complete MCP server setup with all properties and metrics", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"serverName":      "my-mcp-server",
					"success":         "true",
					"isDefaultServer": "true",
				},
				Metrics: map[string]float64{
					"setupDurationMs": 2500.0,
				},
			},
		}

		ctx := context.Background()
		progress.statMCPServerSetup(ctx, obsv)

		require.Len(t, *counterCalls, 1)
		require.Equal(t, "agent.mcp_server_setup", (*counterCalls)[0].key)
		require.Equal(t, int64(1), (*counterCalls)[0].value)
		require.Equal(t, "my-mcp-server", (*counterCalls)[0].tags["server_name"])
		require.Equal(t, "true", (*counterCalls)[0].tags["success"])
		require.Equal(t, "true", (*counterCalls)[0].tags["is_default"])

		require.Len(t, *distributionCalls, 1)
		require.Equal(t, "agent.mcp_server_setup_duration_ms", (*distributionCalls)[0].key)
		require.Equal(t, 2500*time.Millisecond, (*distributionCalls)[0].duration)
		require.Equal(t, "my-mcp-server", (*distributionCalls)[0].tags["server_name"])
		require.Equal(t, "true", (*distributionCalls)[0].tags["success"])
	})

	t.Run("MCP server setup failure", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"serverName":      "failing-server",
					"success":         "false",
					"isDefaultServer": "false",
				},
				Metrics: map[string]float64{
					"setupDurationMs": 500.0,
				},
			},
		}

		ctx := context.Background()
		progress.statMCPServerSetup(ctx, obsv)

		require.Len(t, *counterCalls, 1)
		require.Equal(t, "agent.mcp_server_setup", (*counterCalls)[0].key)
		require.Equal(t, int64(1), (*counterCalls)[0].value)
		require.Equal(t, "failing-server", (*counterCalls)[0].tags["server_name"])
		require.Equal(t, "false", (*counterCalls)[0].tags["success"])
		require.Equal(t, "false", (*counterCalls)[0].tags["is_default"])

		require.Len(t, *distributionCalls, 1)
		require.Equal(t, "agent.mcp_server_setup_duration_ms", (*distributionCalls)[0].key)
		require.Equal(t, 500*time.Millisecond, (*distributionCalls)[0].duration)
	})

	t.Run("missing duration metric", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"serverName":      "test-server",
					"success":         "true",
					"isDefaultServer": "true",
				},
				Metrics: map[string]float64{},
			},
		}

		ctx := context.Background()
		progress.statMCPServerSetup(ctx, obsv)
		require.Len(t, *counterCalls, 1)
		require.Equal(t, "agent.mcp_server_setup", (*counterCalls)[0].key)
		require.Equal(t, int64(1), (*counterCalls)[0].value)
		require.Equal(t, "test-server", (*counterCalls)[0].tags["server_name"])
		require.Equal(t, "true", (*counterCalls)[0].tags["success"])
		require.Equal(t, "true", (*counterCalls)[0].tags["is_default"])

		require.Len(t, *distributionCalls, 0)
	})

	t.Run("missing isDefaultServer property is set as unknown", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"serverName": "test-server",
					"success":    "true",
				},
				Metrics: map[string]float64{},
			},
		}

		ctx := context.Background()
		progress.statMCPServerSetup(ctx, obsv)
		require.Len(t, *counterCalls, 1)
		require.Equal(t, "agent.mcp_server_setup", (*counterCalls)[0].key)
		require.Equal(t, "unknown", (*counterCalls)[0].tags["is_default"])

		require.Len(t, *distributionCalls, 0)
	})
}

func TestStatRuntimeTiming(t *testing.T) {
	t.Run("known section emits distribution metric", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"name":    "runtime.initial_clone",
					"success": "true",
				},
				Metrics: map[string]float64{
					"durationMs": 1200.0,
				},
			},
		}

		progress.statRuntimeTiming(context.Background(), obsv)

		require.Len(t, *distributionCalls, 1)
		require.Equal(t, metricRuntimeTimingDurationMs, (*distributionCalls)[0].key)
		require.Equal(t, 1200*time.Millisecond, (*distributionCalls)[0].duration)
		require.Equal(t, "runtime.initial_clone", (*distributionCalls)[0].tags["timing.name"])
		require.Equal(t, "true", (*distributionCalls)[0].tags["timing.success"])
	})

	t.Run("unknown section does not emit distribution metric", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"name":    "runtime.unknown_section",
					"success": "true",
				},
				Metrics: map[string]float64{
					"durationMs": 1200.0,
				},
			},
		}

		progress.statRuntimeTiming(context.Background(), obsv)
		require.Len(t, *distributionCalls, 0)
	})

	t.Run("missing success still emits distribution metric", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"name": "runtime.initial_clone",
				},
				Metrics: map[string]float64{
					"durationMs": 1200.0,
				},
			},
		}

		progress.statRuntimeTiming(context.Background(), obsv)
		require.Len(t, *distributionCalls, 1)
		require.Equal(t, "runtime.initial_clone", (*distributionCalls)[0].tags["timing.name"])
		_, hasSuccess := (*distributionCalls)[0].tags["timing.success"]
		require.False(t, hasSuccess)
	})

	t.Run("all allowlisted names emit metrics", func(t *testing.T) {
		for name := range runtimeTimingAllowlist {
			t.Run(name, func(t *testing.T) {
				obsv, _, distributionCalls := setupMockStatter(true)

				progress := &ProgressJobEvent{
					Telemetry: Telemetry{
						Properties: map[string]string{
							"name":    name,
							"success": "true",
						},
						Metrics: map[string]float64{
							"durationMs": 100.0,
						},
					},
				}

				progress.statRuntimeTiming(context.Background(), obsv)

				require.Len(t, *distributionCalls, 1, "expected metric for allowlisted name %q", name)
				require.Equal(t, name, (*distributionCalls)[0].tags["timing.name"])
			})
		}
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

func TestStatToolCall(t *testing.T) {
	job := &jobs.Job{}

	// validationToolNames mirrors the production set so the test count stays in sync automatically.
	validationToolNames := make([]string, 0, len(validationTools))
	for name := range validationTools {
		validationToolNames = append(validationToolNames, name)
	}

	t.Run("validation tool gets parallel_validation tag when enabled", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentParallelValidation:         true,
			featureflags.CopilotSWEAgentParallelValidationDisabled: false,
		})

		for _, toolName := range validationToolNames {
			progress := &ProgressJobEvent{
				Telemetry: Telemetry{
					Properties: map[string]string{
						"toolName":   toolName,
						"resultType": "success",
					},
					Metrics: map[string]float64{
						"durationMs": 1000.0,
					},
				},
			}

			progress.statToolCall(context.Background(), obsv, ffClient, job)
		}

		require.Len(t, *distributionCalls, len(validationToolNames))
		for _, call := range *distributionCalls {
			require.Equal(t, "agent.tool_call_duration_ms", call.key)
			require.Equal(t, "true", call.tags["parallel_validation"])
			require.Equal(t, "false", call.tags["trivial_change"])
			require.Equal(t, "false", call.tags["trivial_change_skip"])
			require.Equal(t, "false", call.tags["trivial_change_code_review"])
			require.Equal(t, "false", call.tags["trivial_change_skip_code_review"])
		}
	})

	t.Run("validation tool gets parallel_validation false when disabled", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentParallelValidation:         false,
			featureflags.CopilotSWEAgentParallelValidationDisabled: false,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "codeql_checker",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 2000.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Equal(t, "false", (*distributionCalls)[0].tags["parallel_validation"])
	})

	t.Run("validation tool gets parallel_validation false when kill switch active", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentParallelValidation:         true,
			featureflags.CopilotSWEAgentParallelValidationDisabled: true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "parallel_validation",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Equal(t, "false", (*distributionCalls)[0].tags["parallel_validation"])
	})

	t.Run("non-validation tool does not get parallel_validation tag", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentParallelValidation: true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "bash",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 300.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		_, hasTag := (*distributionCalls)[0].tags["parallel_validation"]
		require.False(t, hasTag, "non-validation tool should not have parallel_validation tag")
		_, hasTag = (*distributionCalls)[0].tags["trivial_change"]
		require.False(t, hasTag, "non-validation tool should not have trivial_change tag")
	})

	t.Run("validation tool gets trivial_change tags when all flags enabled", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentParallelValidation:             true,
			featureflags.CopilotSWEAgentTrivialChange:                  true,
			featureflags.CopilotSWEAgentTrivialChangeSkip:              true,
			featureflags.CopilotSWEAgentTrivialChangeCodeReview:        true,
			featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview:    true,
			featureflags.CopilotSWEAgentTrivialChangeDisable:           false,
			featureflags.CopilotSWEAgentTrivialChangeSkipDisable:       false,
			featureflags.CopilotSWEAgentTrivialChangeCodeReviewDisable: false,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "code_review",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 1000.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		call := (*distributionCalls)[0]
		require.Equal(t, "true", call.tags["trivial_change"])
		require.Equal(t, "true", call.tags["trivial_change_skip"])
		require.Equal(t, "true", call.tags["trivial_change_code_review"])
		require.Equal(t, "true", call.tags["trivial_change_skip_code_review"])
	})

	t.Run("trivial_change false when top-level kill switch active", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTrivialChange:               true,
			featureflags.CopilotSWEAgentTrivialChangeDisable:        true,
			featureflags.CopilotSWEAgentTrivialChangeSkip:           true,
			featureflags.CopilotSWEAgentTrivialChangeCodeReview:     true,
			featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview: true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "parallel_validation",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		call := (*distributionCalls)[0]
		require.Equal(t, "false", call.tags["trivial_change"])
		require.Equal(t, "false", call.tags["trivial_change_skip"])
		require.Equal(t, "false", call.tags["trivial_change_code_review"])
		require.Equal(t, "false", call.tags["trivial_change_skip_code_review"])
	})

	t.Run("trivial_change_skip false when skip kill switch active", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTrivialChange:               true,
			featureflags.CopilotSWEAgentTrivialChangeSkip:           true,
			featureflags.CopilotSWEAgentTrivialChangeSkipDisable:    true,
			featureflags.CopilotSWEAgentTrivialChangeCodeReview:     true,
			featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview: true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "codeql_checker",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		call := (*distributionCalls)[0]
		require.Equal(t, "true", call.tags["trivial_change"])
		require.Equal(t, "false", call.tags["trivial_change_skip"])
		require.Equal(t, "true", call.tags["trivial_change_code_review"])
		require.Equal(t, "false", call.tags["trivial_change_skip_code_review"], "skip_code_review requires skip to be enabled")
	})

	t.Run("trivial_change_code_review false when code review kill switch active", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTrivialChange:                  true,
			featureflags.CopilotSWEAgentTrivialChangeSkip:              true,
			featureflags.CopilotSWEAgentTrivialChangeCodeReview:        true,
			featureflags.CopilotSWEAgentTrivialChangeCodeReviewDisable: true,
			featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview:    true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "code_review",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		call := (*distributionCalls)[0]
		require.Equal(t, "true", call.tags["trivial_change"])
		require.Equal(t, "true", call.tags["trivial_change_skip"])
		require.Equal(t, "false", call.tags["trivial_change_code_review"])
		require.Equal(t, "false", call.tags["trivial_change_skip_code_review"], "skip_code_review requires code_review to be enabled")
	})

	t.Run("direct validation tool emits trivial_change assessment and disagreement counters from restricted properties", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTrivialChange:               true,
			featureflags.CopilotSWEAgentTrivialChangeSkip:           true,
			featureflags.CopilotSWEAgentTrivialChangeSkipDisable:    true,
			featureflags.CopilotSWEAgentTrivialChangeCodeReview:     true,
			featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview: true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "code_review",
					"resultType": "success",
				},
				RestrictedProperties: map[string]string{
					"trivialChange.isTrivial":    "true",
					"trivialChange.disagreement": "true",
					"trivialChange.alertCount":   "2",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Len(t, *counterCalls, 2)

		assessment := (*counterCalls)[0]
		require.Equal(t, metricValidationTrivialChangeAssessment, assessment.key)
		require.Equal(t, int64(1), assessment.value)
		require.Equal(t, "code_review", assessment.tags["validation_tool"])
		require.Equal(t, "true", assessment.tags["trivial_change_is_trivial"])
		require.Equal(t, "true", assessment.tags["trivial_change_disagreement"])
		require.Equal(t, "true", assessment.tags["trivial_change_alerts_found"])
		require.Equal(t, "true", assessment.tags["trivial_change"])
		require.Equal(t, "false", assessment.tags["trivial_change_skip"])
		require.Equal(t, "true", assessment.tags["trivial_change_code_review"])
		require.Equal(t, "false", assessment.tags["trivial_change_skip_code_review"])

		disagreement := (*counterCalls)[1]
		require.Equal(t, metricValidationTrivialChangeDisagreement, disagreement.key)
		require.Equal(t, assessment.tags, disagreement.tags)
	})

	t.Run("direct validation tool emits trivial_change counters from properties", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTrivialChange: true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":                   "codeql_checker",
					"resultType":                 "success",
					"trivialChange.isTrivial":    "true",
					"trivialChange.disagreement": "true",
					"trivialChange.alertCount":   "1",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Len(t, *counterCalls, 2)

		assessment := (*counterCalls)[0]
		require.Equal(t, metricValidationTrivialChangeAssessment, assessment.key)
		require.Equal(t, "codeql_checker", assessment.tags["validation_tool"])
		require.Equal(t, "true", assessment.tags["trivial_change_is_trivial"])
		require.Equal(t, "true", assessment.tags["trivial_change_disagreement"])
		require.Equal(t, "true", assessment.tags["trivial_change_alerts_found"])

		disagreement := (*counterCalls)[1]
		require.Equal(t, metricValidationTrivialChangeDisagreement, disagreement.key)
		require.Equal(t, assessment.tags, disagreement.tags)
	})

	t.Run("restricted telemetry properties win over properties", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTrivialChange: true,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":                   "code_review",
					"resultType":                 "success",
					"trivialChange.isTrivial":    "false",
					"trivialChange.disagreement": "false",
					"trivialChange.alertCount":   "0",
				},
				RestrictedProperties: map[string]string{
					"trivialChange.isTrivial":    "true",
					"trivialChange.disagreement": "true",
					"trivialChange.alertCount":   "2",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Len(t, *counterCalls, 2)

		assessment := (*counterCalls)[0]
		require.Equal(t, metricValidationTrivialChangeAssessment, assessment.key)
		require.Equal(t, "code_review", assessment.tags["validation_tool"])
		require.Equal(t, "true", assessment.tags["trivial_change_is_trivial"])
		require.Equal(t, "true", assessment.tags["trivial_change_disagreement"])
		require.Equal(t, "true", assessment.tags["trivial_change_alerts_found"])

		disagreement := (*counterCalls)[1]
		require.Equal(t, metricValidationTrivialChangeDisagreement, disagreement.key)
		require.Equal(t, assessment.tags, disagreement.tags)
	})

	t.Run("parallel validation emits per-tool trivial_change assessment and disagreement counters", func(t *testing.T) {
		obsv, counterCalls, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentParallelValidation:             true,
			featureflags.CopilotSWEAgentTrivialChange:                  true,
			featureflags.CopilotSWEAgentTrivialChangeSkip:              true,
			featureflags.CopilotSWEAgentTrivialChangeCodeReview:        true,
			featureflags.CopilotSWEAgentTrivialChangeSkipCodeReview:    true,
			featureflags.CopilotSWEAgentTrivialChangeDisable:           false,
			featureflags.CopilotSWEAgentTrivialChangeSkipDisable:       false,
			featureflags.CopilotSWEAgentTrivialChangeCodeReviewDisable: false,
		})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":                              "parallel_validation",
					"resultType":                            "success",
					"trivialChange.codeReview.isTrivial":    "true",
					"trivialChange.codeReview.disagreement": "true",
					"trivialChange.codeReview.alertCount":   "1",
					"trivialChange.codeQL.isTrivial":        "false",
				},
				Metrics: map[string]float64{
					"durationMs": 750.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Len(t, *counterCalls, 3)

		codeReviewAssessment := (*counterCalls)[0]
		require.Equal(t, metricValidationTrivialChangeAssessment, codeReviewAssessment.key)
		require.Equal(t, "parallel_validation", codeReviewAssessment.tags["tool.name"])
		require.Equal(t, "code_review", codeReviewAssessment.tags["validation_tool"])
		require.Equal(t, "true", codeReviewAssessment.tags["trivial_change_is_trivial"])
		require.Equal(t, "true", codeReviewAssessment.tags["trivial_change_disagreement"])
		require.Equal(t, "true", codeReviewAssessment.tags["trivial_change_alerts_found"])

		codeReviewDisagreement := (*counterCalls)[1]
		require.Equal(t, metricValidationTrivialChangeDisagreement, codeReviewDisagreement.key)
		require.Equal(t, codeReviewAssessment.tags, codeReviewDisagreement.tags)

		codeQLAssessment := (*counterCalls)[2]
		require.Equal(t, metricValidationTrivialChangeAssessment, codeQLAssessment.key)
		require.Equal(t, "parallel_validation", codeQLAssessment.tags["tool.name"])
		require.Equal(t, "codeql_checker", codeQLAssessment.tags["validation_tool"])
		require.Equal(t, "false", codeQLAssessment.tags["trivial_change_is_trivial"])
		require.Equal(t, "false", codeQLAssessment.tags["trivial_change_disagreement"])
		require.Equal(t, "unknown", codeQLAssessment.tags["trivial_change_alerts_found"])
	})

	t.Run("parallel_validation emits codeql_skip_reason tag", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":                         "parallel_validation",
					"resultType":                       "success",
					"validation.codeQL.skipReason":     "trivial_change",
					"validation.codeReview.skipReason": "no_changes",
				},
				Metrics: map[string]float64{
					"durationMs": 100.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		call := (*distributionCalls)[0]
		require.Equal(t, "trivial_change", call.tags["codeql_skip_reason"])
		require.Equal(t, "no_changes", call.tags["code_review_skip_reason"])
	})

	t.Run("parallel_validation omits skip reason tags when not present", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "parallel_validation",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 100.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		call := (*distributionCalls)[0]
		_, hasTag := call.tags["codeql_skip_reason"]
		require.False(t, hasTag, "codeql_skip_reason should be absent when property not set")
		_, hasTag = call.tags["code_review_skip_reason"]
		require.False(t, hasTag, "code_review_skip_reason should be absent when property not set")
	})

	t.Run("codeql_checker emits skip_reason tag", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":          "codeql_checker",
					"resultType":        "success",
					"codeql.skipReason": "circuit_breaker",
				},
				Metrics: map[string]float64{
					"durationMs": 50.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Equal(t, "circuit_breaker", (*distributionCalls)[0].tags["skip_reason"])
	})

	t.Run("code_review emits skip_reason tag", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":              "code_review",
					"resultType":            "success",
					"codeReview.skipReason": "budget_exhausted",
				},
				Metrics: map[string]float64{
					"durationMs": 10.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		require.Equal(t, "budget_exhausted", (*distributionCalls)[0].tags["skip_reason"])
	})

	t.Run("codeql_checker omits skip_reason tag when not present", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":   "codeql_checker",
					"resultType": "success",
				},
				Metrics: map[string]float64{
					"durationMs": 500.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		_, hasTag := (*distributionCalls)[0].tags["skip_reason"]
		require.False(t, hasTag, "skip_reason should be absent when property not set")
	})

	t.Run("unknown skip reason values are dropped", func(t *testing.T) {
		obsv, _, distributionCalls := setupMockStatter(true)
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		progress := &ProgressJobEvent{
			Telemetry: Telemetry{
				Properties: map[string]string{
					"toolName":                         "parallel_validation",
					"resultType":                       "success",
					"validation.codeQL.skipReason":     "unexpected_value",
					"validation.codeReview.skipReason": "",
				},
				Metrics: map[string]float64{
					"durationMs": 100.0,
				},
			},
		}

		progress.statToolCall(context.Background(), obsv, ffClient, job)

		require.Len(t, *distributionCalls, 1)
		call := (*distributionCalls)[0]
		_, hasTag := call.tags["codeql_skip_reason"]
		require.False(t, hasTag, "unknown skip reason value should not produce a tag")
		_, hasTag = call.tags["code_review_skip_reason"]
		require.False(t, hasTag, "empty skip reason value should not produce a tag")
	})
}
