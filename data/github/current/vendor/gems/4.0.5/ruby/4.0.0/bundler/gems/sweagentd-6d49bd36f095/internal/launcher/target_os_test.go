package launcher

import (
	"testing"

	"github.com/github/sweagentd/internal/runnerlabels"
	"github.com/stretchr/testify/assert"
)

func TestResolveTargetOS(t *testing.T) {
	tests := []struct {
		name   string
		runsOn string
		want   targetOS
	}{
		// Linux
		{"ubuntu-latest", runnerlabels.UbuntuLatestLabel, targetOSLinux},
		{"ubuntu-22.04", "ubuntu-22.04", targetOSLinux},
		{"ubuntu-20.04", "ubuntu-20.04", targetOSLinux},
		{"bare ubuntu", "ubuntu", targetOSLinux},
		{"upper-case ubuntu", "Ubuntu-Latest", targetOSLinux},

		// Windows
		{"windows-latest", runnerlabels.WindowsLatestLabel, targetOSWindows},
		{"windows-2022", "windows-2022", targetOSWindows},
		{"windows-2019", "windows-2019", targetOSWindows},
		{"bare windows", "windows", targetOSWindows},
		{"upper-case windows", "Windows-Latest", targetOSWindows},

		// macOS — currently treated as unknown until macOS step bodies exist.
		{"macos-latest stays unknown today", runnerlabels.MacOSLatestLabel, targetOSUnknown},
		{"macos-13 stays unknown today", "macos-13", targetOSUnknown},

		// Anything we cannot statically determine.
		{"empty string", "", targetOSUnknown},
		{"whitespace-only", "   ", targetOSUnknown},
		{
			"runtime expression (default org-default form)",
			"${{ vars.COPILOT_AGENT_RUNS_ON_LABELS || 'ubuntu-latest' }}",
			targetOSUnknown,
		},
		{"array form", "[self-hosted, linux]", targetOSUnknown},
		{"object form (multiline)", "\nlabels: [self-hosted]\n", targetOSUnknown},
		{"comma list", "self-hosted,linux", targetOSUnknown},
		{"self-hosted bare", runnerlabels.SelfHostedLabel, targetOSUnknown},
		{"self-hosted upper-case", "Self-Hosted", targetOSUnknown},
		{"custom-image label", runnerlabels.CustomImageLabel, targetOSUnknown},
		{"unknown custom label", "my-custom-runner-pool", targetOSUnknown},
		{"two-word label is treated as a list", "self-hosted linux", targetOSUnknown},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := resolveTargetOS(tt.runsOn)
			assert.Equal(t, tt.want, got, "resolveTargetOS(%q)", tt.runsOn)
		})
	}
}

func TestTargetOS_ExpectedRunnerOS(t *testing.T) {
	tests := []struct {
		os   targetOS
		want string
	}{
		{targetOSLinux, "Linux"},
		{targetOSWindows, "Windows"},
		{targetOSMacOS, "macOS"},
		{targetOSUnknown, ""},
		{targetOS("nonsense"), ""},
	}
	for _, tt := range tests {
		t.Run(string(tt.os), func(t *testing.T) {
			assert.Equal(t, tt.want, tt.os.expectedRunnerOS())
		})
	}
}
