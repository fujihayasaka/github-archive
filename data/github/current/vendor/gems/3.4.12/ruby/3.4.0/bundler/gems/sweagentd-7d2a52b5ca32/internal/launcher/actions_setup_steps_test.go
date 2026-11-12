package launcher

import (
	"context"
	"html/template"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
)

func TestActionsLauncher_addActionsLogging(t *testing.T) {
	tests := []struct {
		name          string
		copilotAPIURL string
		tenantSlug    string
		sessionID     string
		stepsYaml     any
		expectError   bool
		expectedError string
		expectedURL   string
	}{
		{
			name:          "successful tenant placeholder replacement",
			copilotAPIURL: "https://<tenant>.api.github.com",
			tenantSlug:    "my-tenant",
			sessionID:     "test-session-123",
			stepsYaml: []any{
				map[string]any{
					"name": "Test Step",
					"run":  "echo 'test'",
				},
			},
			expectError: false,
			expectedURL: "https://my-tenant.api.github.com/agents/sessions/test-session-123/logs",
		},
		{
			name:          "tenant placeholder but no tenant in context",
			copilotAPIURL: "https://<tenant>.api.github.com",
			tenantSlug:    "",
			sessionID:     "session-error",
			stepsYaml: []any{
				map[string]any{
					"name": "Failing Step",
					"run":  "echo 'fail'",
				},
			},
			expectError:   true,
			expectedError: "error replacing tenant placeholder in copilot API URL",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Set up context with tenant slug if provided
			ctx := t.Context()
			if tt.tenantSlug != "" {
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{
					TenantSlug: tt.tenantSlug,
				})
			} else {
				// Add data but leave tenant slug empty
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
			}

			// Create ActionsLauncher with the test URL
			launcher := &ActionsLauncher{
				opts: ActionsLauncherOpts{
					AgentLauncherOpts: AgentLauncherOpts{
						CopilotAPIURL: tt.copilotAPIURL,
					},
				},
			}

			// Create launch options
			opts := LaunchAgentOpts{
				SessionID: tt.sessionID,
			}

			// Call the method under test
			result, err := launcher.addActionsLogging(ctx, tt.stepsYaml, opts)

			// Assert results
			if tt.expectError {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tt.expectedError)
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, result)

				// Verify the result is a slice
				resultSteps, ok := result.([]any)
				assert.True(t, ok, "Result should be a slice")

				// Verify we have the right number of steps (each original step becomes 3: before log, original, after log)
				originalSteps := tt.stepsYaml.([]any)
				expectedStepCount := len(originalSteps) * 3
				assert.Len(t, resultSteps, expectedStepCount, "Should have 3 steps for each original step")

				// Verify session log steps contain the expected URL
				for i, step := range resultSteps {
					stepMap, ok := step.(map[string]any)
					if !ok {
						continue
					}

					// Check if this is a session log step (every 1st and 3rd step in each group of 3)
					if i%3 == 0 || i%3 == 2 {
						runCmd, hasRun := stepMap["run"].(string)
						if hasRun && strings.Contains(runCmd, "session-log.sh") {
							assert.Contains(t, runCmd, tt.expectedURL, "Session log step should contain expected URL")
						}
					}

					ifCondition, hasIf := stepMap["if"].(string)
					assert.True(t, hasIf, "Each step should have an if condition")
					assert.Contains(t, ifCondition, "${{ env.SHOULD_CONTINUE == 'true' }}", "Session log step should have correct if condition")
				}
			}
		})
	}
}

func TestActionsLauncher_downloadSetupStepsWorkflow(t *testing.T) {
	ctx := t.Context()
	opts := LaunchAgentOpts{
		GitHubRepoOwner: "test-owner",
		GitHubRepoName:  "test-repo",
		GitHubRepoID:    12345,
	}

	testContent := []byte("test content")

	tests := []struct {
		name            string
		spokesOpts      []spokestest.ClientOption
		expectedContent []byte
		expectedError   string
	}{
		{
			name: "successful file retrieval - yml extension",
			spokesOpts: []spokestest.ClientOption{
				spokestest.ClientWithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", testContent),
			},
			expectedContent: testContent,
			expectedError:   "",
		},
		{
			name:            "file not found - both extensions fail",
			spokesOpts:      []spokestest.ClientOption{},
			expectedContent: nil,
			expectedError:   "failed to download setup steps workflow file",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			spokesClient := spokestest.NewClient(t, tt.spokesOpts...)

			launcher := &ActionsLauncher{
				obsv:   observability.NewNoopExporters(),
				spokes: spokesClient,
			}

			client := &github.NoopClient{}

			// Call the method under test
			result, err := launcher.downloadSetupStepsWorkflow(ctx, client, opts)

			// Verify the results
			if tt.expectedError != "" {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tt.expectedError)
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.NotNil(t, result)
				assert.Equal(t, tt.expectedContent, result)
			}
		})
	}
}

func TestActionsLauncher_processSetupStepsWorkflow_YAMLFormatting(t *testing.T) {
	yamlContent := `on:
  workflow_dispatch:
jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    steps:
      - name: Authenticate to Azure Artifacts
        env:
          AZURE_DEVOPS_TOKEN: ${{ secrets.AZURE_DEVOPS_TOKEN }}
        run: |

          # Create .npmrc with proper Azure DevOps authentication
          echo "@myorg:registry=https://pkgs.dev.azure.com/MyOrg/MyProject/_packaging/my_feed/npm/registry/" > ~/.npmrc
          echo "//pkgs.dev.azure.com/MyOrg/MyProject/_packaging/my_feed/npm/registry/:username=VssSessionToken" >> ~/.npmrc
          echo "//pkgs.dev.azure.com/MyOrg/MyProject/_packaging/my_feed/npm/registry/:_password=${AZURE_DEVOPS_TOKEN}" >> ~/.npmrc


      - name: Install dependencies
        run: npm ci`

	multilineYamlContent := `jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    steps:
      - name: Script with indentation
        run: |
          #!/bin/bash
          set -e
          echo "Starting script"
              # This line is indented
          echo "Done"`

	runTest := func(t *testing.T, content string) {
		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		customization := &map[string]template.HTML{}
		opts := LaunchAgentOpts{
			GitHubRepo:  "test/repo",
			BranchName:  "main",
			CommitCount: 1,
			ActorID:     123,
		}

		result, err := launcher.processSetupStepsWorkflow(context.Background(), content, customization, opts)

		require.NoError(t, err)
		require.NotNil(t, result)

		stepsHTML, exists := (*result)["steps"]
		require.True(t, exists, "steps should exist in result")

		stepsStr := string(stepsHTML)

		// Core assertion: should not contain problematic YAML block indicators
		assert.NotContains(t, stepsStr, "|4", "should not contain |4 which causes GitHub Actions syntax error")
		assert.NotContains(t, stepsStr, "|6", "should not contain |6 which causes GitHub Actions syntax error")
		assert.NotContains(t, stepsStr, "|8", "should not contain |8 which causes GitHub Actions syntax error")

		// Verify generated YAML is valid and parseable
		var parsedSteps []any
		err = yaml.Unmarshal([]byte(stepsStr), &parsedSteps)
		assert.NoError(t, err, "generated YAML should be valid and parseable")
	}

	t.Run("avoid explicit YAML indentation", func(t *testing.T) {
		runTest(t, yamlContent)
	})

	t.Run("multiline script with indentation", func(t *testing.T) {
		runTest(t, multilineYamlContent)
	})
}
