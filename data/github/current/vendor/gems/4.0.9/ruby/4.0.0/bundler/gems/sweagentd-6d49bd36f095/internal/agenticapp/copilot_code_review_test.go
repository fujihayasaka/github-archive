package agenticapp

import (
	"testing"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

// testCCRAppID is the app ID used for CCR in tests.
// In production (dotcom) the value is 946600. In development it is 836.
const testCCRAppID = int64(946600)

func TestNewCopilotCodeReview(t *testing.T) {
	appLogin := CopilotCodeReviewComputeSlug
	botLogin := CopilotCodeReviewComputeSlug + "[bot]"

	ccr := NewCopilotCodeReview(testCCRAppID, appLogin, 456, botLogin, "commit-login", "commit@email.com")
	require.NotNil(t, ccr)
	require.NotNil(t, ccr.logins)
	require.NotNil(t, ccr.mentionRegexp)
	require.Equal(t, testCCRAppID, ccr.AppID())
	require.Equal(t, CopilotCodeReviewAppName, ccr.AppName())

	expectedLogins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}
	require.Equal(t, expectedLogins, ccr.logins)
	require.Equal(t, "copilot-pull-request-reviewer", ccr.MentionableSlug())
}

func TestCopilotCodeReview_Getters(t *testing.T) {
	botID := int64(33333)
	commitLogin := "commit-user"
	commitEmail := "commit@example.com"

	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, botID, CopilotCodeReviewComputeSlug+"[bot]", commitLogin, commitEmail)

	require.Equal(t, testCCRAppID, ccr.AppID())
	require.Equal(t, botID, ccr.BotID())
	require.Equal(t, CopilotCodeReviewComputeSlug+"[bot]", ccr.BotLogin())
	require.Equal(t, commitLogin, ccr.CommitLogin())
	require.Equal(t, commitEmail, ccr.CommitEmail())
	require.Equal(t, CopilotCodeReviewAppName, ccr.AppName())
	require.Equal(t, CopilotCodeReviewBranchPrefix, ccr.BranchPrefix())
	require.Equal(t, CopilotCodeReviewComputeSlug, ccr.ComputeSlug())
	require.Equal(t, CopilotCodeReviewComputeSlug, ccr.MentionableSlug())
	require.Equal(t, map[string]string{sweagentd.MetadataCAPIIntegrationID: CopilotCodeReviewCAPIIntegrationID}, ccr.Metadata())
	require.Equal(t, "Running Copilot Code Review", ccr.WorkflowRunName(0))
}

func TestCopilotCodeReview_hasLogin(t *testing.T) {
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 2, CopilotCodeReviewComputeSlug+"[bot]", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "exact app login match",
			login:    CopilotCodeReviewComputeSlug,
			expected: true,
		},
		{
			name:     "app login with [bot] suffix",
			login:    CopilotCodeReviewComputeSlug + "[bot]",
			expected: true,
		},
		{
			name:     "bot login match",
			login:    CopilotCodeReviewComputeSlug + "[bot]",
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
			login:    "CCR-APP",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ccr.hasLogin(tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestCopilotCodeReview_isMentioned(t *testing.T) {
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 1, CopilotCodeReviewComputeSlug+"[bot]", "commit-login", "commit@email.com")

	tests := []struct {
		name string
		body string
	}{
		{name: "mention with slug", body: "@copilot-pull-request-reviewer please review"},
		{name: "mention with copilot", body: "@copilot please review"},
		{name: "mention with app login", body: "@ccr-app please review"},
		{name: "normal comment", body: "This is a normal comment"},
		{name: "empty body", body: ""},
		{name: "mention with newline", body: "First line\n@copilot-pull-request-reviewer second line"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ccr.isMentioned(tt.body)
			require.False(t, result, "isMentioned should always return false for CopilotCodeReview")
		})
	}
}

func TestCopilotCodeReview_EdgeCases(t *testing.T) {
	t.Run("empty bot login", func(t *testing.T) {
		ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 1, "", "commit-login", "commit@email.com")
		require.NotNil(t, ccr)

		require.True(t, ccr.hasLogin(CopilotCodeReviewComputeSlug))
		require.True(t, ccr.hasLogin(""))
	})
}

// entryPointProbe is a lightweight ComputeEnv that captures the entry point
// and setup command an agent would configure, without modifying real workflow data.
type entryPointProbe struct {
	setupAgent string
	entryPoint string
}

func (p *entryPointProbe) SetupAgent(cmd string) { p.setupAgent = cmd }
func (p *entryPointProbe) EntryPoint(cmd string) { p.entryPoint = cmd }

var _ sweagentd.ComputeEnv = (*entryPointProbe)(nil)

func TestIsEntryPointForAutofind(t *testing.T) {
	tests := []struct {
		name     string
		cmd      string
		expected bool
	}{
		{
			name:     "exact autofind entry point",
			cmd:      "dist-autofind-ts/ts/autofind.js",
			expected: true,
		},
		{
			name:     "different entry point",
			cmd:      "dist/index.js",
			expected: false,
		},
		{
			name:     "empty string",
			cmd:      "",
			expected: false,
		},
		{
			name:     "prefix match is not enough",
			cmd:      "dist-autofind-ts/ts/autofind.js extra",
			expected: false,
		},
		{
			name:     "partial path",
			cmd:      "autofind.js",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.expected, IsEntryPointForAutofind(tt.cmd))
		})
	}
}

func TestSetupComputeForAutofind(t *testing.T) {
	var probe entryPointProbe
	SetupComputeForAutofind(&probe)

	require.Equal(t, "node copilot-developer-action-main/dist-autofind-ts/ts/autofind.js cca-setup", probe.setupAgent)
	require.Equal(t, "dist-autofind-ts/ts/autofind.js", probe.entryPoint)
	require.True(t, IsEntryPointForAutofind(probe.entryPoint), "entry point set by SetupComputeForAutofind must be recognized by IsEntryPointForAutofind")
}

func TestCopilotCodeReview_SetupCompute_UsesAutofind(t *testing.T) {
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 1, CopilotCodeReviewComputeSlug+"[bot]", "commit-login", "commit@email.com")

	var probe entryPointProbe
	ccr.SetupCompute(&probe)

	require.Equal(t, "dist-autofind-ts/ts/autofind.js", probe.entryPoint)
	require.True(t, IsEntryPointForAutofind(probe.entryPoint))
}

func TestCopilotCodeReview_SkipBranchAndPRCreation(t *testing.T) {
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 1, CopilotCodeReviewComputeSlug+"[bot]", "commit-login", "commit@email.com")

	bl, ok := sweagentd.AgenticApp(ccr).(sweagentd.AgenticAppBranchlessMode)
	require.True(t, ok, "CopilotCodeReview should implement AgenticAppBranchlessMode")
	require.True(t, bl.SkipBranchAndPRCreation())
}

func TestCopilotCodeReview_SkipPRCloseCancel(t *testing.T) {
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 1, CopilotCodeReviewComputeSlug+"[bot]", "commit-login", "commit@email.com")

	skipper, ok := sweagentd.AgenticApp(ccr).(sweagentd.AgenticAppSkipPRCloseCancel)
	require.True(t, ok, "CopilotCodeReview should implement AgenticAppSkipPRCloseCancel")
	require.True(t, skipper.SkipPRCloseCancel())
}

func TestCopilotCodeReview_NotifyOnSetupStepFailure(t *testing.T) {
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 1, CopilotCodeReviewComputeSlug+"[bot]", "commit-login", "commit@email.com")

	notifier, ok := sweagentd.AgenticApp(ccr).(sweagentd.AgenticAppSetupStepFailureNotifier)
	require.True(t, ok, "CopilotCodeReview should implement AgenticAppSetupStepFailureNotifier")
	require.True(t, notifier.NotifyOnSetupStepFailure())
}

func TestCopilotCodeReview_SkipAgentFirewall(t *testing.T) {
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 1, CopilotCodeReviewComputeSlug+"[bot]", "commit-login", "commit@email.com")

	fw, ok := sweagentd.AgenticApp(ccr).(sweagentd.AgenticAppFirewallExempt)
	require.True(t, ok, "CopilotCodeReview should implement AgenticAppFirewallExempt")
	require.True(t, fw.SkipAgentFirewall())
}
