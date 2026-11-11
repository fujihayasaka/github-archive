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
			result, err := launcher.addActionsLogging(ctx, tt.stepsYaml, &opts, tt.copilotAPIURL)

			// Assert results
			if tt.expectError {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.expectedError)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.NotNil(t, result)

				// Verify the result is a slice
				resultSteps, ok := result.([]any)
				assert.True(t, ok, "Result should be a slice")

				// Verify we have the right number of steps
				// Each original step becomes 5: 2 before log (Linux + Windows), original, 2 after log (Linux + Windows)
				originalSteps := tt.stepsYaml.([]any)
				expectedStepCount := len(originalSteps) * 5
				assert.Len(t, resultSteps, expectedStepCount, "Should have 5 steps for each original step (2 before + 1 original + 2 after)")

				// Verify session log steps contain the expected URL
				for _, step := range resultSteps {
					stepMap, ok := step.(map[string]any)
					if !ok {
						continue
					}

					// Check if this is a session log step (contains session-log script in run command)
					runCmd, hasRun := stepMap["run"].(string)
					if hasRun && (strings.Contains(runCmd, "session-log.sh") || strings.Contains(runCmd, "session-log.ps1")) {
						assert.Contains(t, runCmd, tt.expectedURL, "Session log step should contain expected URL")
					}

					ifCondition, hasIf := stepMap["if"].(string)
					assert.True(t, hasIf, "Each step should have an if condition")
					// The condition should contain SHOULD_CONTINUE check (may also have OS check)
					assert.Contains(t, ifCondition, "env.SHOULD_CONTINUE == 'true'", "Step should have correct if condition")
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
				spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", testContent),
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

			// Call the method under test
			result, err := launcher.downloadSetupStepsWorkflow(ctx, &opts)

			// Verify the results
			if tt.expectedError != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.expectedError)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
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
        if: inputs.run_tests == true
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
        if: ${{ inputs.run_tests == true }}
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

		customization := map[string]template.HTML{}
		opts := LaunchAgentOpts{
			GitHubRepo:  "test/repo",
			BranchName:  "main",
			CommitCount: 1,
			ActorID:     123,
		}

		result, runsOn, err := launcher.processSetupStepsWorkflow(context.Background(), content, customization, &opts, "https://api.githubcopilot.com")

		require.NoError(t, err)
		require.NotNil(t, result)
		assert.Equal(t, "ubuntu-latest", runsOn, "ubuntu-latest should be tracked")

		stepsHTML, exists := result["steps"]
		require.True(t, exists, "steps should exist in result")

		stepsStr := string(stepsHTML)

		// Core assertion: should not contain problematic YAML block indicators
		assert.NotContains(t, stepsStr, "|4", "should not contain |4 which causes GitHub Actions syntax error")
		assert.NotContains(t, stepsStr, "|6", "should not contain |6 which causes GitHub Actions syntax error")
		assert.NotContains(t, stepsStr, "|8", "should not contain |8 which causes GitHub Actions syntax error")

		// Verify generated YAML is valid and parseable
		var parsedSteps []any
		err = yaml.Unmarshal([]byte(stepsStr), &parsedSteps)
		require.NoError(t, err, "generated YAML should be valid and parseable")

		assert.Contains(t, stepsStr, "if: ${{ env.SHOULD_CONTINUE == 'true' && inputs.run_tests == true }}", "should contain combined if condition")
	}

	t.Run("avoid explicit YAML indentation", func(t *testing.T) {
		runTest(t, yamlContent)
	})

	t.Run("multiline script with indentation", func(t *testing.T) {
		runTest(t, multilineYamlContent)
	})
}

func TestActionsLauncher_processSetupStepsWorkflow_RunsOnTracking(t *testing.T) {
	launcher := &ActionsLauncher{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(map[string]bool{}),
	}

	customization := map[string]template.HTML{}
	opts := LaunchAgentOpts{
		GitHubRepo:  "test/repo",
		BranchName:  "main",
		CommitCount: 1,
		ActorID:     123,
	}

	tests := []struct {
		name           string
		yamlContent    string
		expectedRunsOn string
		expectError    bool
	}{
		{
			name: "ubuntu-latest should be tracked",
			yamlContent: `jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    steps:
      - name: Test
        run: echo "test"`,
			expectedRunsOn: "ubuntu-latest",
			expectError:    false,
		},
		{
			name: "custom string runs-on should be tracked",
			yamlContent: `jobs:
  copilot-setup-steps:
    runs-on: self-hosted
    steps:
      - name: Test
        run: echo "test"`,
			expectedRunsOn: "self-hosted",
			expectError:    false,
		},
		{
			name: "array runs-on should be tracked as custom",
			yamlContent: `jobs:
  copilot-setup-steps:
    runs-on: [self-hosted, linux]
    steps:
      - name: Test
        run: echo "test"`,
			expectedRunsOn: "custom",
			expectError:    false,
		},
		{
			name: "object runs-on should be tracked as custom",
			yamlContent: `jobs:
  copilot-setup-steps:
    runs-on:
      group: my-group
    steps:
      - name: Test
        run: echo "test"`,
			expectedRunsOn: "custom",
			expectError:    false,
		},
		{
			name: "windows runner should be tracked",
			yamlContent: `jobs:
  copilot-setup-steps:
    runs-on: windows-latest
    steps:
      - name: Test
        run: echo "test"`,
			expectedRunsOn: "windows-latest",
			expectError:    false,
		},
		{
			name: "macos runner should be tracked",
			yamlContent: `jobs:
  copilot-setup-steps:
    runs-on: macos-latest
    steps:
      - name: Test
        run: echo "test"`,
			expectedRunsOn: "macos-latest",
			expectError:    false,
		},
		{
			name: "no runs-on specified should be empty string",
			yamlContent: `jobs:
  copilot-setup-steps:
    steps:
      - name: Test
        run: echo "test"`,
			expectedRunsOn: "",
			expectError:    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, runsOn, err := launcher.processSetupStepsWorkflow(context.Background(), tt.yamlContent, customization, &opts, "https://api.githubcopilot.com")

			if tt.expectError {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)
			require.NotNil(t, result)
			assert.Equal(t, tt.expectedRunsOn, runsOn, "runsOn value should match expected value")
		})
	}
}

func TestActionsLauncher_applySetupSteps_Integration(t *testing.T) {
	tests := []struct {
		name                    string
		setupStepsContent       []byte
		expectedCustomSetupUsed bool
		expectedRunsOn          string
		expectError             bool
		spokesOpts              []spokestest.ClientOption
	}{
		{
			name: "setup steps with ubuntu-latest",
			setupStepsContent: []byte(`jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    steps:
      - name: Install deps
        run: npm install`),
			expectedCustomSetupUsed: true,
			expectedRunsOn:          "ubuntu-latest",
			expectError:             false,
		},
		{
			name: "setup steps with self-hosted runner",
			setupStepsContent: []byte(`jobs:
  copilot-setup-steps:
    runs-on: self-hosted
    steps:
      - name: Install deps
        run: npm install`),
			expectedCustomSetupUsed: true,
			expectedRunsOn:          "self-hosted",
			expectError:             false,
		},
		{
			name: "setup steps with runner group",
			setupStepsContent: []byte(`jobs:
  copilot-setup-steps:
    runs-on:
      group: my-runners
    steps:
      - name: Install deps
        run: npm install`),
			expectedCustomSetupUsed: true,
			expectedRunsOn:          "custom",
			expectError:             false,
		},
		{
			name:                    "no setup steps file",
			setupStepsContent:       nil,
			expectedCustomSetupUsed: false,
			expectedRunsOn:          "",
			expectError:             true, // applySetupSteps returns error when file not found
			spokesOpts:              []spokestest.ClientOption{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()

			spokesOpts := tt.spokesOpts
			if tt.setupStepsContent != nil {
				spokesOpts = []spokestest.ClientOption{
					spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", tt.setupStepsContent),
				}
			}
			spokesClient := spokestest.NewClient(t, spokesOpts...)

			launcher := &ActionsLauncher{
				obsv:   observability.NewNoopExporters(),
				spokes: spokesClient,
			}

			client := &github.NoopClient{}
			opts := LaunchAgentOpts{
				GitHubRepoID: 12345,
				GitHubRepo:   "test/repo",
				BranchName:   "main",
				CommitCount:  1,
				ActorID:      123,
			}

			data := workflowData{
				Customization: map[string]template.HTML{
					"runs-on": "ubuntu-latest",
				},
			}

			result, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")

			if tt.expectError {
				assert.Error(t, err)
				return
			}

			require.NoError(t, err)

			if tt.expectedCustomSetupUsed {
				require.NotNil(t, result, "result should not be nil when custom setup is used")
				assert.True(t, result.WasApplied, "WasApplied should be true")
				assert.Equal(t, tt.expectedRunsOn, result.RunsOn, "RunsOn should match expected value")
				assert.NotNil(t, result.Customization, "Customization should not be nil")
			} else {
				assert.Nil(t, result, "result should be nil when no custom setup is used")
			}
		})
	}
}

func TestGenerateSessionLogCommandLinux(t *testing.T) {
	tests := []struct {
		name       string
		sessionURL string
		stepName   string
		output     string
		expected   string
	}{
		{
			name:       "simple strings without special characters",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Install deps",
			output:     "Finished successfully",
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs "Install deps" "Finished successfully"`,
		},
		{
			name:       "empty output string",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Test Step",
			output:     "",
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs "Test Step" ""`,
		},
		{
			name:       "step name with special characters",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Install \"quoted\" deps",
			output:     "Done",
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs "Install \"quoted\" deps" "Done"`,
		},
		{
			name:       "output with newlines",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Build",
			output:     "Line1\nLine2",
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs "Build" "Line1\nLine2"`,
		},
		{
			name:       "output with backslashes",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Path test",
			output:     `C:\Users\test`,
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs "Path test" "C:\\Users\\test"`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := generateSessionLogCommandLinux(tt.sessionURL, tt.stepName, tt.output)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestGenerateSessionLogCommandWindows(t *testing.T) {
	tests := []struct {
		name       string
		sessionURL string
		stepName   string
		output     string
		expected   string
	}{
		{
			name:       "simple strings without special characters",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Install deps",
			output:     "Finished successfully",
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs "Install deps" "Finished successfully"`,
		},
		{
			name:       "empty output string",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Test Step",
			output:     "",
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs "Test Step" ""`,
		},
		{
			name:       "step name with special characters",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Install \"quoted\" deps",
			output:     "Done",
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs "Install \"quoted\" deps" "Done"`,
		},
		{
			name:       "output with newlines",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Build",
			output:     "Line1\nLine2",
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs "Build" "Line1\nLine2"`,
		},
		{
			name:       "output with backslashes",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Path test",
			output:     `C:\Users\test`,
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs "Path test" "C:\\Users\\test"`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := generateSessionLogCommandWindows(tt.sessionURL, tt.stepName, tt.output)
			assert.Equal(t, tt.expected, result)
		})
	}
}
