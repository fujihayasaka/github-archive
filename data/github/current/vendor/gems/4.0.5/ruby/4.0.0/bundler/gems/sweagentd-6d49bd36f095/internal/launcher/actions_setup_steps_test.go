package launcher

import (
	"context"
	"html/template"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/environmentfeatures"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/runnerlabels"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
)

func TestActionsLauncher_addActionsLogging(t *testing.T) {
	tests := []struct {
		name             string
		copilotAPIURL    string
		tenantSlug       string
		sessionID        string
		stepsYaml        any
		expectError      bool
		expectedError    string
		expectedURL      string
		expectedStepName string
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
			expectError:      false,
			expectedURL:      "https://my-tenant.api.github.com/agents/sessions/test-session-123/logs",
			expectedStepName: "Test Step",
		},
		{
			name:          "step with no name and no uses gets default name",
			copilotAPIURL: "https://api.github.com",
			tenantSlug:    "my-tenant",
			sessionID:     "test-session-456",
			stepsYaml: []any{
				map[string]any{
					"run": "echo 'no name step'",
				},
			},
			expectError:      false,
			expectedURL:      "https://api.github.com/agents/sessions/test-session-456/logs",
			expectedStepName: defaultSetupStepName,
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
				ffClient: featureflags.NewNoopClient(map[string]bool{}),
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
						if tt.expectedStepName != "" {
							assert.Contains(t, runCmd, tt.expectedStepName, "Session log step should contain expected step name")
						}
					}

					ifCondition, hasIf := stepMap["if"].(string)
					assert.True(t, hasIf, "Each step should have an if condition")
					// The condition should contain SHOULD_CONTINUE check (may also have OS check)
					assert.Contains(t, ifCondition, "env.SHOULD_CONTINUE == 'true'", "Step should have correct if condition")
				}

				// Verify that "before" log steps use simple conditions and "after" log steps
				// include the status-check function so they run even after a setup step failure.
				// Step ordering per original step: [0] Linux before, [1] Windows before, [2] original, [3] Linux after, [4] Windows after
				require.Equal(t, 0, len(resultSteps)%5, "Result steps should be a multiple of 5")
				for i := 0; i < len(resultSteps); i += 5 {
					linuxBefore := resultSteps[i].(map[string]any)
					windowsBefore := resultSteps[i+1].(map[string]any)
					linuxAfter := resultSteps[i+3].(map[string]any)
					windowsAfter := resultSteps[i+4].(map[string]any)

					// "Before" steps should NOT contain status-check functions
					assert.NotContains(t, linuxBefore["if"], "(success() || !cancelled())", "Linux before step should not contain status-check function")
					assert.NotContains(t, windowsBefore["if"], "(success() || !cancelled())", "Windows before step should not contain status-check function")

					// "After" steps SHOULD contain (success() || !cancelled()) so they run on failure
					assert.Contains(t, linuxAfter["if"], "(success() || !cancelled())", "Linux after step should contain status-check function")
					assert.Contains(t, windowsAfter["if"], "(success() || !cancelled())", "Windows after step should contain status-check function")
				}
			}
		})
	}
}

func TestActionsLauncher_addActionsLogging_DefaultStepName(t *testing.T) {
	ctx := t.Context()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		TenantSlug: "my-tenant",
	})

	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL: "https://api.github.com",
			},
		},
		ffClient: featureflags.NewNoopClient(map[string]bool{}),
	}

	opts := LaunchAgentOpts{
		SessionID: "test-session",
	}

	stepsYaml := []any{
		map[string]any{
			"run": "echo 'no name step'",
		},
	}

	result, err := launcher.addActionsLogging(ctx, stepsYaml, &opts, "https://api.github.com")
	require.NoError(t, err)

	resultSteps, ok := result.([]any)
	require.True(t, ok)

	// Verify session log steps use the default step name
	for _, step := range resultSteps {
		stepMap, ok := step.(map[string]any)
		if !ok {
			continue
		}
		runCmd, hasRun := stepMap["run"].(string)
		if hasRun && (strings.Contains(runCmd, "session-log.sh") || strings.Contains(runCmd, "session-log.ps1")) {
			assert.Contains(t, runCmd, defaultSetupStepName, "Session log step should use default name when step has no name or uses")
		}
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
		assert.Equal(t, runnerlabels.UbuntuLatestLabel, runsOn, "ubuntu-latest should be tracked")

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
			expectedRunsOn: runnerlabels.UbuntuLatestLabel,
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
			expectedRunsOn: runnerlabels.SelfHostedLabel,
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
			expectedRunsOn: runnerlabels.WindowsLatestLabel,
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
			expectedRunsOn: runnerlabels.MacOSLatestLabel,
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
			expectedRunsOn:          runnerlabels.UbuntuLatestLabel,
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
			expectedRunsOn:          runnerlabels.SelfHostedLabel,
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
				obsv:     observability.NewNoopExporters(),
				spokes:   spokesClient,
				ffClient: featureflags.NewNoopClient(map[string]bool{}),
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
					"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
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
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs 'Install deps' 'Finished successfully'`,
		},
		{
			name:       "empty output string",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Test Step",
			output:     "",
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs 'Test Step' ''`,
		},
		{
			name:       "step name with special characters",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Install \"quoted\" deps",
			output:     "Done",
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs 'Install "quoted" deps' 'Done'`,
		},
		{
			name:       "output with newlines",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Build",
			output:     "Line1\nLine2",
			expected:   "\"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh\" https://api.github.com/agents/sessions/test-session/logs 'Build' 'Line1\nLine2'",
		},
		{
			name:       "output with backslashes",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Path test",
			output:     `C:\Users\test`,
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs 'Path test' 'C:\Users\test'`,
		},
		{
			name:       "single quotes are safely escaped",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "it's a step",
			output:     "don't expand",
			expected:   `"$RUNNER_TEMP/copilot-developer-action-main/script/session-log.sh" https://api.github.com/agents/sessions/test-session/logs 'it'"'"'s a step' 'don'"'"'t expand'`,
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
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs 'Install deps' 'Finished successfully'`,
		},
		{
			name:       "empty output string",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Test Step",
			output:     "",
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs 'Test Step' ''`,
		},
		{
			name:       "step name with special characters",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Install \"quoted\" deps",
			output:     "Done",
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs 'Install "quoted" deps' 'Done'`,
		},
		{
			name:       "output with newlines",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Build",
			output:     "Line1\nLine2",
			expected:   "& \"$env:RUNNER_TEMP\\copilot-developer-action-main\\script\\session-log.ps1\" https://api.github.com/agents/sessions/test-session/logs 'Build' 'Line1\nLine2'",
		},
		{
			name:       "output with backslashes",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "Path test",
			output:     `C:\Users\test`,
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs 'Path test' 'C:\Users\test'`,
		},
		{
			name:       "single quotes are safely escaped",
			sessionURL: "https://api.github.com/agents/sessions/test-session/logs",
			stepName:   "it's a step",
			output:     "don't expand",
			expected:   `& "$env:RUNNER_TEMP\copilot-developer-action-main\script\session-log.ps1" https://api.github.com/agents/sessions/test-session/logs 'it''s a step' 'don''t expand'`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := generateSessionLogCommandWindows(tt.sessionURL, tt.stepName, tt.output)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestIsEligibleForOutputCapture(t *testing.T) {
	tests := []struct {
		name     string
		step     map[string]any
		expected bool
	}{
		{
			name:     "run step with no shell (eligible)",
			step:     map[string]any{"run": "echo hello"},
			expected: true,
		},
		{
			name:     "run step with shell: bash (eligible)",
			step:     map[string]any{"run": "echo hello", "shell": "bash"},
			expected: true,
		},
		{
			name:     "run step with shell: sh (not eligible)",
			step:     map[string]any{"run": "echo hello", "shell": "sh"},
			expected: false,
		},
		{
			name:     "run step with shell: pwsh (not eligible)",
			step:     map[string]any{"run": "echo hello", "shell": "pwsh"},
			expected: false,
		},
		{
			name:     "run step with shell: python (not eligible)",
			step:     map[string]any{"run": "print('hello')", "shell": "python"},
			expected: false,
		},
		{
			name:     "uses step (not eligible)",
			step:     map[string]any{"uses": "actions/checkout@v4"},
			expected: false,
		},
		{
			name:     "uses step with run (not eligible)",
			step:     map[string]any{"uses": "actions/checkout@v4", "run": "echo hello"},
			expected: false,
		},
		{
			name:     "step with neither run nor uses (not eligible)",
			step:     map[string]any{"name": "empty step"},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := isEligibleForOutputCapture(tt.step)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestWrapRunCommandForCapture(t *testing.T) {
	tests := []struct {
		name                   string
		run                    string
		outputFileName         string
		useProcessSubstitution bool
		expected               string
	}{
		{
			name:                   "simple command with pipe",
			run:                    "echo hello",
			outputFileName:         "copilot-setup-output-abc.txt",
			useProcessSubstitution: false,
			expected:               "{\necho hello\n} 2>&1 | tee \"$RUNNER_TEMP/copilot-setup-output-abc.txt\"",
		},
		{
			name:                   "multiline command with pipe",
			run:                    "echo line1\necho line2",
			outputFileName:         "copilot-setup-output-xyz.txt",
			useProcessSubstitution: false,
			expected:               "{\necho line1\necho line2\n} 2>&1 | tee \"$RUNNER_TEMP/copilot-setup-output-xyz.txt\"",
		},
		{
			name:                   "simple command with process substitution",
			run:                    "echo hello",
			outputFileName:         "copilot-setup-output-abc.txt",
			useProcessSubstitution: true,
			expected:               "{\necho hello\n} > >(tee \"$RUNNER_TEMP/copilot-setup-output-abc.txt\") 2>&1",
		},
		{
			name:                   "multiline command with process substitution",
			run:                    "echo line1\necho line2",
			outputFileName:         "copilot-setup-output-xyz.txt",
			useProcessSubstitution: true,
			expected:               "{\necho line1\necho line2\n} > >(tee \"$RUNNER_TEMP/copilot-setup-output-xyz.txt\") 2>&1",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := wrapRunCommandForCapture(tt.run, tt.outputFileName, tt.useProcessSubstitution)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestAddActionsLogging_OutputCapture(t *testing.T) {
	ctx := t.Context()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		TenantSlug: "my-tenant",
	})

	launcher := &ActionsLauncher{
		opts: ActionsLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				CopilotAPIURL: "https://my-tenant.api.github.com",
			},
		},
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSetupStepOutputCapture: true,
		}),
	}

	opts := LaunchAgentOpts{
		SessionID: "test-session",
	}

	t.Run("bash run step gets output capture wrapping", func(t *testing.T) {
		stepsYaml := []any{
			map[string]any{
				"name":  "Install deps",
				"run":   "npm install",
				"shell": "bash",
			},
		}

		result, err := launcher.addActionsLogging(ctx, stepsYaml, &opts, "https://my-tenant.api.github.com")
		require.NoError(t, err)

		resultSteps, ok := result.([]any)
		require.True(t, ok)
		assert.Len(t, resultSteps, 5)

		// The user step (index 2) should be wrapped
		userStep := resultSteps[2].(map[string]any)
		runCmd := userStep["run"].(string)
		assert.Contains(t, runCmd, "} 2>&1 | tee \"$RUNNER_TEMP/copilot-setup-output-")
		assert.Contains(t, runCmd, "npm install")

		// The Linux after-step (index 3) should read from the output file
		linuxAfterStep := resultSteps[3].(map[string]any)
		linuxRun := linuxAfterStep["run"].(string)
		assert.Contains(t, linuxRun, "jq -Rs")
		assert.Contains(t, linuxRun, "copilot-setup-output-")
		assert.Contains(t, linuxRun, "head -c 4000")

		// The Windows after-step (index 4) should use existing static messages (no output capture on Windows)
		windowsAfterStep := resultSteps[4].(map[string]any)
		windowsRun := windowsAfterStep["run"].(string)
		assert.NotContains(t, windowsRun, "Get-Content")
		assert.Contains(t, windowsRun, "Finished successfully")
	})

	t.Run("run step with no shell gets output capture and shell set to bash", func(t *testing.T) {
		stepsYaml := []any{
			map[string]any{
				"name": "Install deps",
				"run":  "npm install",
			},
		}

		result, err := launcher.addActionsLogging(ctx, stepsYaml, &opts, "https://my-tenant.api.github.com")
		require.NoError(t, err)

		resultSteps, ok := result.([]any)
		require.True(t, ok)

		// The user step should have shell: bash added
		userStep := resultSteps[2].(map[string]any)
		assert.Equal(t, "bash", userStep["shell"])
		runCmd := userStep["run"].(string)
		assert.Contains(t, runCmd, "} 2>&1 | tee")
	})

	t.Run("pwsh step does NOT get output capture", func(t *testing.T) {
		stepsYaml := []any{
			map[string]any{
				"name":  "Install deps",
				"run":   "Write-Host 'hello'",
				"shell": "pwsh",
			},
		}

		result, err := launcher.addActionsLogging(ctx, stepsYaml, &opts, "https://my-tenant.api.github.com")
		require.NoError(t, err)

		resultSteps, ok := result.([]any)
		require.True(t, ok)

		// The user step should NOT be wrapped
		userStep := resultSteps[2].(map[string]any)
		runCmd := userStep["run"].(string)
		assert.Equal(t, "Write-Host 'hello'", runCmd)

		// The Linux after-step should use static messages
		linuxAfterStep := resultSteps[3].(map[string]any)
		linuxRun := linuxAfterStep["run"].(string)
		assert.NotContains(t, linuxRun, "jq -Rs")
		assert.Contains(t, linuxRun, "Finished successfully")
	})

	t.Run("uses step does NOT get output capture", func(t *testing.T) {
		stepsYaml := []any{
			map[string]any{
				"uses": "actions/checkout@v4",
			},
		}

		result, err := launcher.addActionsLogging(ctx, stepsYaml, &opts, "https://my-tenant.api.github.com")
		require.NoError(t, err)

		resultSteps, ok := result.([]any)
		require.True(t, ok)

		// The Linux after-step should use static messages
		linuxAfterStep := resultSteps[3].(map[string]any)
		linuxRun := linuxAfterStep["run"].(string)
		assert.NotContains(t, linuxRun, "jq -Rs")
		assert.Contains(t, linuxRun, "Finished successfully")
	})

	t.Run("feature flag disabled prevents output capture", func(t *testing.T) {
		disabledLauncher := &ActionsLauncher{
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL: "https://my-tenant.api.github.com",
				},
			},
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		stepsYaml := []any{
			map[string]any{
				"name":  "Install deps",
				"run":   "npm install",
				"shell": "bash",
			},
		}

		result, err := disabledLauncher.addActionsLogging(ctx, stepsYaml, &opts, "https://my-tenant.api.github.com")
		require.NoError(t, err)

		resultSteps, ok := result.([]any)
		require.True(t, ok)

		// The user step should NOT be wrapped
		userStep := resultSteps[2].(map[string]any)
		runCmd := userStep["run"].(string)
		assert.Equal(t, "npm install", runCmd)

		// The Linux after-step should use static messages
		linuxAfterStep := resultSteps[3].(map[string]any)
		linuxRun := linuxAfterStep["run"].(string)
		assert.NotContains(t, linuxRun, "jq -Rs")
		assert.Contains(t, linuxRun, "Finished successfully")
	})

	t.Run("process substitution flag uses process substitution for output capture", func(t *testing.T) {
		processSubLauncher := &ActionsLauncher{
			opts: ActionsLauncherOpts{
				AgentLauncherOpts: AgentLauncherOpts{
					CopilotAPIURL: "https://my-tenant.api.github.com",
				},
			},
			ffClient: featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSetupStepOutputCapture:                    true,
				featureflags.CopilotSWEAgentSetupStepOutputCaptureProcessSubstitution: true,
			}),
		}

		stepsYaml := []any{
			map[string]any{
				"name":  "Install deps",
				"run":   "npm install",
				"shell": "bash",
			},
		}

		result, err := processSubLauncher.addActionsLogging(ctx, stepsYaml, &opts, "https://my-tenant.api.github.com")
		require.NoError(t, err)

		resultSteps, ok := result.([]any)
		require.True(t, ok)
		assert.Len(t, resultSteps, 5)

		// The user step (index 2) should be wrapped with process substitution
		userStep := resultSteps[2].(map[string]any)
		runCmd := userStep["run"].(string)
		assert.Contains(t, runCmd, "} > >(tee \"$RUNNER_TEMP/copilot-setup-output-")
		assert.Contains(t, runCmd, "npm install")
		// Should NOT use pipe-based tee
		assert.NotContains(t, runCmd, "| tee")
	})
}

func TestGenerateCapturedOutputAfterCommandLinux(t *testing.T) {
	result := generateCapturedOutputAfterCommandLinux(
		"https://api.example.com/sessions/123/logs",
		"Install deps",
		"copilot-setup-output-abc.txt",
		"GITHUB_COPILOT_SETUP_ERROR_REPORTED",
	)

	// Should read from the output file
	assert.Contains(t, result, `__output_file="$RUNNER_TEMP/copilot-setup-output-abc.txt"`)
	// Should use jq for JSON escaping
	assert.Contains(t, result, "jq -Rs")
	// Should truncate with head
	assert.Contains(t, result, "head -c 4000")
	// Should have truncation message
	assert.Contains(t, result, "truncated, see verbose logs for full output")
	// Should fallback when jq not available or file missing
	assert.Contains(t, result, "Setup step completed successfully")
	// Should handle failure case
	assert.Contains(t, result, `<error>`)
	assert.Contains(t, result, "GITHUB_COPILOT_SETUP_ERROR_REPORTED")
	// Should call session-log.sh with variable
	assert.Contains(t, result, `"$__output"`)
	assert.Contains(t, result, "session-log.sh")
}

func TestActionsLauncher_applySetupSteps_ExcludeProperties(t *testing.T) {
	setupStepsContent := []byte(`jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - name: Install deps
        run: npm install`)

	t.Run("excludes runs-on when specified", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		originalSteps := template.HTML("- name: original\n  run: echo hi")
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Exclude: []string{"runs-on"},
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   originalSteps,
			},
		}

		result, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.NoError(t, err)
		require.NotNil(t, result)
		assert.True(t, result.WasApplied)
		// runs-on was excluded, so RunsOn should be empty (not customized)
		assert.Empty(t, result.RunsOn)
		// The original runs-on from data.Customization should remain unchanged
		assert.Equal(t, template.HTML(runnerlabels.UbuntuLatestLabel), result.Customization["runs-on"])
	})

	t.Run("excludes steps when specified", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		originalSteps := template.HTML("- name: original\n  run: echo hi")
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Exclude: []string{"steps"},
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   originalSteps,
			},
		}

		result, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.NoError(t, err)
		require.NotNil(t, result)
		assert.True(t, result.WasApplied)
		// Steps were excluded, so the original steps should not be overwritten
		assert.Equal(t, originalSteps, result.Customization["steps"])
		// runs-on was not excluded, so it should be customized
		assert.Equal(t, runnerlabels.UbuntuLatestLabel, result.RunsOn)
	})

	t.Run("no exclusions applies all properties", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		originalSteps := template.HTML("- name: original\n  run: echo hi")
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   originalSteps,
			},
		}

		result, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.NoError(t, err)
		require.NotNil(t, result)
		assert.True(t, result.WasApplied)
		// runs-on should be present in customization
		assert.Equal(t, runnerlabels.UbuntuLatestLabel, result.RunsOn)
		_, hasRunsOn := result.Customization["runs-on"]
		assert.True(t, hasRunsOn, "runs-on should be present in customization")
		// steps should be overwritten with logging (not the original placeholder)
		assert.NotEqual(t, originalSteps, result.Customization["steps"])
		assert.Contains(t, string(result.Customization["steps"]), "Install deps", "steps from setup YAML should be applied")
	})

	t.Run("rejects unrecognized exclude property", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Exclude: []string{"step"},
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   template.HTML("- name: original\n  run: echo hi"),
			},
		}

		_, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unrecognized copilot-setup-steps 'exclude' properties")
		assert.Contains(t, err.Error(), "step")
	})
}

func TestActionsLauncher_applySetupSteps_OnlyProperties(t *testing.T) {
	setupStepsContent := []byte(`permissions:
  contents: read
  pull-requests: read
jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      contents: read
    steps:
      - name: Install deps
        run: npm install`)

	t.Run("honors only runs-on when only=[runs-on]", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		originalSteps := template.HTML("- name: original\n  run: echo hi")
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Only: []string{"runs-on"},
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   originalSteps,
			},
		}

		result, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.NoError(t, err)
		require.NotNil(t, result)
		assert.True(t, result.WasApplied)
		// runs-on was in the only list, so it should be customized
		assert.Equal(t, "ubuntu-latest", result.RunsOn)
		// steps was not in the only list, so original placeholder steps should be preserved
		assert.Equal(t, originalSteps, result.Customization["steps"])
		// permissions was not in the only list, so neither the job-level nor the workflow-level
		// permissions should leak into the rendered customization
		_, hasPermissions := result.Customization["permissions"]
		assert.False(t, hasPermissions, "permissions should not leak when not in only list")
	})

	t.Run("honors runs-on and container when only=[runs-on,container]", func(t *testing.T) {
		ctx := context.Background()
		containerSetupSteps := []byte(`jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    container:
      image: node:20
    steps:
      - name: Install deps
        run: npm install`)
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", containerSetupSteps),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		originalSteps := template.HTML("- name: original\n  run: echo hi")
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Only: []string{"runs-on", "container"},
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   originalSteps,
			},
		}

		result, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.NoError(t, err)
		require.NotNil(t, result)
		assert.True(t, result.WasApplied)
		assert.Equal(t, "ubuntu-latest", result.RunsOn)
		// container should be honored
		_, hasContainer := result.Customization["container"]
		assert.True(t, hasContainer, "container should be applied when in only list")
		assert.Contains(t, string(result.Customization["container"]), "node:20")
		// steps should be preserved (not in only list)
		assert.Equal(t, originalSteps, result.Customization["steps"])
	})

	t.Run("empty only list treats all properties as allowed", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		originalSteps := template.HTML("- name: original\n  run: echo hi")
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Only: nil,
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   originalSteps,
			},
		}

		result, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.NoError(t, err)
		require.NotNil(t, result)
		assert.Equal(t, "ubuntu-latest", result.RunsOn)
		assert.NotEqual(t, originalSteps, result.Customization["steps"], "steps should be applied when only is empty")
	})

	t.Run("rejects when only and exclude are both set", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Only:    []string{"runs-on"},
					Exclude: []string{"steps"},
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   template.HTML("- name: original\n  run: echo hi"),
			},
		}

		_, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "cannot both be set")
	})

	t.Run("rejects unrecognized only property", func(t *testing.T) {
		ctx := context.Background()
		spokesClient := spokestest.NewClient(t,
			spokestest.WithRepoBlob(12345, ".github/workflows/copilot-setup-steps.yml", setupStepsContent),
		)

		launcher := &ActionsLauncher{
			obsv:     observability.NewNoopExporters(),
			spokes:   spokesClient,
			ffClient: featureflags.NewNoopClient(map[string]bool{}),
		}

		client := &github.NoopClient{}
		opts := LaunchAgentOpts{
			GitHubRepoID: 12345,
			GitHubRepo:   "test/repo",
			BranchName:   "main",
			CommitCount:  1,
			ActorID:      123,
			Features: environmentfeatures.Features{
				CopilotSetupSteps: &environmentfeatures.CopilotSetupSteps{
					Only: []string{"runs-on", "step"},
				},
			},
		}

		data := workflowData{
			Customization: map[string]template.HTML{
				"runs-on": template.HTML(runnerlabels.UbuntuLatestLabel),
				"steps":   template.HTML("- name: original\n  run: echo hi"),
			},
		}

		_, err := launcher.applySetupSteps(ctx, client, &opts, &data, "https://api.githubcopilot.com")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unrecognized copilot-setup-steps 'only' properties")
		assert.Contains(t, err.Error(), "step")
	})
}
