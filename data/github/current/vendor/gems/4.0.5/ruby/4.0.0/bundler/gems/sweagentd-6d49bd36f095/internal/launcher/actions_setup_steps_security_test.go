// REGRESSION TEST — EXPECTED TO FAIL on current HEAD.
// Passes once generateSessionLogCommand{Linux,Windows,LinuxWithVar} quote the
// user-supplied step name so that bash / pwsh treat it as a fully literal
// argument (e.g. POSIX / PowerShell single-quoting, or routing the value
// through the step `env:` map) instead of Go's %q, which emits a Go-style
// double-quoted string and leaves $, `, and $( ) live for the shell.
//
// ASAP finding fingerprint:
//   78d97f00b6e976dc63bfc7c6f1fbb1daa4debcf2a6da15edc03f704657580559
// CWE-78: command injection via step `name` (or `uses`) from
// .github/workflows/copilot-setup-steps.yml into the privileged session-log
// wrapper step that exports GITHUB_COPILOT_API_TOKEN.

package launcher

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// asapCopilotTokenSentinel is placed into the wrapper step's environment as
// GITHUB_COPILOT_API_TOKEN. The regression invariant is that this value never
// appears in the argv that session-log.sh receives — i.e. an attacker-chosen
// step name cannot cause the privileged wrapper to read and forward the token.
const asapCopilotTokenSentinel = "ASAP-COPILOT-TOKEN-SENTINEL-3f3c5b5e"

func TestAddActionsLogging_StepNameMustNotExpandInPrivilegedSessionLogStep(t *testing.T) {
	bashPath, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("bash not available on this platform; Linux session-log injection test skipped")
	}

	// Attacker-controlled `name:` values that a repository author can place in
	// .github/workflows/copilot-setup-steps.yml on the default branch. Each one
	// reads GITHUB_COPILOT_API_TOKEN from the wrapper step's env if bash is
	// allowed to expand the argument that carries the step name.
	payloads := []struct {
		name     string
		stepName string
	}{
		{
			name:     "command substitution $()",
			stepName: "$(printenv GITHUB_COPILOT_API_TOKEN)",
		},
		{
			name:     "backtick command substitution",
			stepName: "`printenv GITHUB_COPILOT_API_TOKEN`",
		},
		{
			name:     "parameter expansion ${VAR}",
			stepName: "${GITHUB_COPILOT_API_TOKEN}",
		},
		{
			name:     "embedded substitution inside benign text",
			stepName: "Install deps $(printenv GITHUB_COPILOT_API_TOKEN) done",
		},
	}

	for _, tc := range payloads {
		t.Run(tc.name, func(t *testing.T) {
			launcher := &ActionsLauncher{
				ffClient: featureflags.NewNoopClient(map[string]bool{}),
			}
			opts := LaunchAgentOpts{SessionID: "asap-session"}

			stepsYaml := []any{
				map[string]any{
					"name": tc.stepName,
					"run":  "echo user-step",
				},
			}

			result, err := launcher.addActionsLogging(context.Background(), stepsYaml, &opts, "https://api.githubcopilot.com")
			require.NoError(t, err)

			resultSteps, ok := result.([]any)
			require.True(t, ok, "result must be a []any of steps")
			// Layout per original step: [0] Linux before, [1] Windows before,
			// [2] original, [3] Linux after, [4] Windows after.
			require.Len(t, resultSteps, 5)

			linuxBefore, ok := resultSteps[0].(map[string]any)
			require.True(t, ok)
			require.Equal(t, "bash", linuxBefore["shell"], "must target the bash wrapper step")

			// Confirm this is the privileged step: it binds the Copilot API
			// token into the step env, which is exactly the secret the
			// attacker-controlled step name is reaching for.
			envMap, ok := linuxBefore["env"].(map[string]any)
			require.True(t, ok, "Linux session-log wrapper must have an env map")
			require.Equal(t, "${{ secrets.GITHUB_COPILOT_API_TOKEN }}", envMap["GITHUB_COPILOT_API_TOKEN"],
				"wrapper step must be the one that exports GITHUB_COPILOT_API_TOKEN")

			runCmd, ok := linuxBefore["run"].(string)
			require.True(t, ok)
			require.Contains(t, runCmd, "session-log.sh", "must be the session-log invocation")

			// Execute the generated `run:` exactly as the Actions runner would
			// for `shell: bash` (simplified to `bash -c`), with a stub
			// session-log.sh that prints the argv it receives and with the
			// step's `env:` map materialised — including the resolved
			// GITHUB_COPILOT_API_TOKEN secret. If the step name reaches the
			// stub as a literal the sentinel never appears; if bash expanded
			// it, the sentinel shows up in argv.
			argv := asapRunBashSessionLog(t, bashPath, runCmd, envMap)

			assert.NotContains(t, argv, asapCopilotTokenSentinel,
				"attacker-controlled step name %q must reach session-log.sh as a literal; "+
					"the privileged GITHUB_COPILOT_API_TOKEN leaked into the wrapper step's argv:\n%s",
				tc.stepName, argv)
		})
	}
}

func TestGenerateSessionLogCommandLinuxWithVar_StepNameMustNotExpand(t *testing.T) {
	bashPath, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("bash not available on this platform")
	}

	// Captured-output "after" variant: same %q-on-name sink, exercised
	// directly so the assertion does not depend on the output-capture
	// feature flag being enabled in addActionsLogging.
	const stepName = "$(printenv GITHUB_COPILOT_API_TOKEN)"
	runCmd := generateSessionLogCommandLinuxWithVar(
		"https://api.githubcopilot.com/agents/sessions/asap-session/logs",
		stepName,
		"__output",
	)
	require.Contains(t, runCmd, "session-log.sh")

	argv := asapRunBashSessionLog(t, bashPath, runCmd, map[string]any{
		"GITHUB_COPILOT_API_TOKEN": asapCopilotTokenSentinel,
		"__output":                 "captured-output-body",
	})

	assert.NotContains(t, argv, asapCopilotTokenSentinel,
		"attacker-controlled step name %q must reach session-log.sh as a literal in the "+
			"captured-output variant; the privileged GITHUB_COPILOT_API_TOKEN leaked:\n%s",
		stepName, argv)
}

func TestGenerateSessionLogCommandWindows_StepNameMustNotExpand(t *testing.T) {
	pwshPath, err := exec.LookPath("pwsh")
	if err != nil {
		t.Skip("pwsh not available on this platform; Windows session-log injection test skipped")
	}

	// PowerShell evaluates $( ) as a sub-expression inside double-quoted
	// strings, so Go's %q is equally unsafe under `shell: pwsh`.
	const stepName = "$([Environment]::GetEnvironmentVariable('GITHUB_COPILOT_API_TOKEN'))"
	runCmd := generateSessionLogCommandWindows(
		"https://api.githubcopilot.com/agents/sessions/asap-session/logs",
		stepName,
		"",
	)
	require.Contains(t, runCmd, "session-log.ps1")

	runnerTemp := t.TempDir()
	scriptDir := filepath.Join(runnerTemp, "copilot-developer-action-main", "script")
	require.NoError(t, os.MkdirAll(scriptDir, 0o755))
	stub := filepath.Join(scriptDir, "session-log.ps1")
	// Stub prints every positional argument so we can inspect what pwsh
	// actually passed after any sub-expression evaluation.
	require.NoError(t, os.WriteFile(stub, []byte("$args | ForEach-Object { Write-Output $_ }\n"), 0o644))

	cmd := exec.Command(pwshPath, "-NoProfile", "-NonInteractive", "-Command", runCmd) //nolint:gosec // pwshPath from LookPath, runCmd is the value under test
	cmd.Env = append(os.Environ(),
		"RUNNER_TEMP="+runnerTemp,
		"GITHUB_COPILOT_API_TOKEN="+asapCopilotTokenSentinel,
	)
	out, err := cmd.CombinedOutput()
	require.NoError(t, err, "stub session-log.ps1 must execute cleanly; output: %s", out)

	assert.NotContains(t, string(out), asapCopilotTokenSentinel,
		"attacker-controlled step name %q must reach session-log.ps1 as a literal; "+
			"the privileged GITHUB_COPILOT_API_TOKEN leaked into the wrapper step's argv:\n%s",
		stepName, string(out))
}

// asapRunBashSessionLog executes runCmd under bash with a stub session-log.sh
// that prints its argv, RUNNER_TEMP wired to the stub's directory, and the
// supplied step env materialised (with the `${{ secrets.GITHUB_COPILOT_API_TOKEN }}`
// Actions expression resolved to the sentinel). It returns the stub's combined
// stdout+stderr — i.e. the argv the real session-log.sh would have received.
func asapRunBashSessionLog(t *testing.T, bashPath, runCmd string, stepEnv map[string]any) string {
	t.Helper()

	runnerTemp := t.TempDir()
	scriptDir := filepath.Join(runnerTemp, "copilot-developer-action-main", "script")
	require.NoError(t, os.MkdirAll(scriptDir, 0o755))

	stub := filepath.Join(scriptDir, "session-log.sh")
	// Print one positional argument per line so the assertion can see exactly
	// what bash handed the script after performing (or not performing) any
	// expansion on the quoted step-name argument.
	stubBody := "#!/usr/bin/env bash\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done\n"
	require.NoError(t, os.WriteFile(stub, []byte(stubBody), 0o755)) //nolint:gosec // test stub must be executable

	env := append(os.Environ(), "RUNNER_TEMP="+runnerTemp)
	for k, v := range stepEnv {
		val := fmt.Sprintf("%v", v)
		// Resolve the one Actions secret expression the wrapper step uses so
		// the bash process sees the same environment the runner would build.
		val = strings.ReplaceAll(val, "${{ secrets.GITHUB_COPILOT_API_TOKEN }}", asapCopilotTokenSentinel)
		env = append(env, k+"="+val)
	}

	cmd := exec.Command(bashPath, "-c", runCmd) //nolint:gosec // bashPath from LookPath, runCmd is the value under test
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	require.NoError(t, err, "stub session-log.sh must execute cleanly; output: %s", out)

	return string(out)
}
