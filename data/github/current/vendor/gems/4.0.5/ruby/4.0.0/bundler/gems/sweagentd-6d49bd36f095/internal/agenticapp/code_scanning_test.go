package agenticapp

import (
	"testing"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

// testCodeScanningAppID is the app ID used for Code Scanning in tests.
const testCodeScanningAppID = int64(123456)

func TestNewCodeScanning(t *testing.T) {
	appLogin := CodeScanningComputeSlug
	botLogin := CodeScanningComputeSlug + "[bot]"

	cs := NewCodeScanning(testCodeScanningAppID, appLogin, 456, botLogin, "commit-login", "commit@email.com")
	require.NotNil(t, cs)
	require.NotNil(t, cs.logins)
	require.NotNil(t, cs.mentionRegexp)
	require.Equal(t, testCodeScanningAppID, cs.AppID())
	require.Equal(t, CodeScanningAppName, cs.AppName())

	expectedLogins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}
	require.Equal(t, expectedLogins, cs.logins)
	require.Equal(t, CodeScanningComputeSlug, cs.MentionableSlug())
}

func TestCodeScanning_Getters(t *testing.T) {
	botID := int64(33333)
	commitLogin := "commit-user"
	commitEmail := "commit@example.com"

	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, botID, CodeScanningComputeSlug+"[bot]", commitLogin, commitEmail)

	require.Equal(t, testCodeScanningAppID, cs.AppID())
	require.Equal(t, botID, cs.BotID())
	require.Equal(t, CodeScanningComputeSlug+"[bot]", cs.BotLogin())
	require.Equal(t, commitLogin, cs.CommitLogin())
	require.Equal(t, commitEmail, cs.CommitEmail())
	require.Equal(t, CodeScanningAppName, cs.AppName())
	require.Equal(t, CodeScanningBranchPrefix, cs.BranchPrefix())
	require.Equal(t, CodeScanningComputeSlug, cs.ComputeSlug())
	require.Equal(t, CopilotCodeReviewComputeSlug, cs.EngineSlug())
	require.Equal(t, CodeScanningComputeSlug, cs.MentionableSlug())
	require.Equal(t, "Code scanning AI findings", cs.WorkflowRunName(0))
}

func TestCodeScanningWorkflowRunName(t *testing.T) {
	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 2, CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")
	require.Equal(t, "Code scanning AI findings on PR #123", cs.WorkflowRunName(123))
	require.Equal(t, "Code scanning AI findings", cs.WorkflowRunName(0))
}

func TestCodeScanning_Metadata(t *testing.T) {
	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 2, CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")
	metadata := cs.Metadata()
	require.NotNil(t, metadata)
	require.Equal(t, CodeScanningCAPIIntegrationID, metadata[sweagentd.MetadataCAPIIntegrationID])
}

func TestCodeScanning_hasLogin(t *testing.T) {
	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 2, CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "exact app login match",
			login:    CodeScanningComputeSlug,
			expected: true,
		},
		{
			name:     "app login with [bot] suffix",
			login:    CodeScanningComputeSlug + "[bot]",
			expected: true,
		},
		{
			name:     "bot login match",
			login:    CodeScanningComputeSlug + "[bot]",
			expected: true,
		},
		{
			name:     "non-matching login",
			login:    "some-other-user",
			expected: false,
		},
		{
			name:     "empty login",
			login:    "",
			expected: false,
		},
		{
			name:     "case sensitive mismatch",
			login:    "GHAS-APP",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := cs.hasLogin(tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestCodeScanning_isMentioned(t *testing.T) {
	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 1, CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")

	tests := []struct {
		name string
		body string
	}{
		{name: "mention with slug", body: "@github-advanced-security please review"},
		{name: "mention with ghas", body: "@ghas please review"},
		{name: "mention with app login", body: "@cs-app please review"},
		{name: "normal comment", body: "This is a normal comment"},
		{name: "empty body", body: ""},
		{name: "mention with newline", body: "First line\n@github-advanced-security second line"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := cs.isMentioned(tt.body)
			require.False(t, result, "isMentioned should always return false for CodeScanning")
		})
	}
}

func TestCodeScanning_EdgeCases(t *testing.T) {
	t.Run("empty bot login", func(t *testing.T) {
		cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 1, "", "commit-login", "commit@email.com")
		require.NotNil(t, cs)

		require.True(t, cs.hasLogin(CodeScanningComputeSlug))
		require.True(t, cs.hasLogin(""))
	})
}

func TestCodeScanning_SetupCompute_UsesAutofind(t *testing.T) {
	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 1, CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")

	var probe entryPointProbe
	cs.SetupCompute(&probe)

	require.Equal(t, "dist-autofind-ts/ts/autofind.js", probe.entryPoint)
	require.True(t, IsEntryPointForAutofind(probe.entryPoint))
}

func TestCodeScanning_SkipEnablementCheck(t *testing.T) {
	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 1, CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")

	// Verify the interface is satisfied
	exempt, ok := any(cs).(sweagentd.AgenticAppEnablementExempt)
	require.True(t, ok, "CodeScanning must implement AgenticAppEnablementExempt")
	require.True(t, exempt.SkipEnablementCheck())
}

func TestCodeScanning_SkipAgentFirewall(t *testing.T) {
	cs := NewCodeScanning(testCodeScanningAppID, CodeScanningComputeSlug, 1, CodeScanningComputeSlug+"[bot]", "commit-login", "commit@email.com")

	fw, ok := sweagentd.AgenticApp(cs).(sweagentd.AgenticAppFirewallExempt)
	require.True(t, ok, "CodeScanning should implement AgenticAppFirewallExempt")
	require.True(t, fw.SkipAgentFirewall())
}
