package launcher

import (
	"strings"

	"github.com/github/sweagentd/internal/runnerlabels"
)

// targetOS identifies the operating system that the dynamic workflow is being
// rendered for. It is computed late (after setup-steps, organization runner
// defaults, and custom-image selection have all finalized the runs-on value).
//
// The value is used by the workflow template to choose OS-specific step
// bodies. When the runs-on value is a runtime expression, an array, an object,
// a self-hosted label, or any other label we cannot statically map to a
// concrete OS, the value is targetOSUnknown and the template falls back to
// emitting steps for every supported OS guarded by `if: runner.os == 'X'`
// (the legacy multi-OS dispatch). Defaulting to a single OS in the unknown
// case would silently break runs that resolve to a different OS at runtime.
type targetOS string

const (
	// targetOSLinux indicates the workflow targets a Linux runner.
	targetOSLinux targetOS = "linux"
	// targetOSWindows indicates the workflow targets a Windows runner.
	targetOSWindows targetOS = "windows"
	// targetOSMacOS indicates the workflow targets a macOS runner.
	// macOS-specific step bodies are not yet implemented; until they are,
	// resolveTargetOS will not return this value.
	targetOSMacOS targetOS = "macos"
	// targetOSUnknown indicates the OS could not be statically determined
	// from the runs-on value (e.g. a `${{ vars.X || '...' }}` expression,
	// an array/object form, a self-hosted or custom label). Callers should
	// treat this as "render the legacy multi-OS workflow".
	targetOSUnknown targetOS = "unknown"
)

// expectedRunnerOS returns the value GitHub Actions exposes as `runner.os`
// for this targetOS, or empty string for targetOSUnknown.
func (t targetOS) expectedRunnerOS() string {
	switch t {
	case targetOSLinux:
		return "Linux"
	case targetOSWindows:
		return "Windows"
	case targetOSMacOS:
		return "macOS"
	}
	return ""
}

// resolveTargetOS maps a runs-on value to a concrete targetOS.
//
// Inputs that map to a concrete OS:
//   - "ubuntu-latest", "ubuntu-22.04", "ubuntu-..." => targetOSLinux
//   - "windows-latest", "windows-2022", "windows-..." => targetOSWindows
//
// Everything else returns targetOSUnknown, including (but not limited to):
//   - empty string
//   - runtime expressions like "${{ vars.X || 'ubuntu-latest' }}"
//   - the org-default expression produced by defaultRunsOnValue
//   - the custom-image label
//   - "self-hosted" and arbitrary self-hosted labels
//   - any value containing whitespace, brackets, or braces (array/object/expression syntax)
//
// macOS labels currently also return targetOSUnknown because macOS-specific
// step bodies are not yet implemented; once they are, callers can map
// "macos-*" here without changing any other code.
func resolveTargetOS(runsOn string) targetOS {
	v := strings.TrimSpace(runsOn)
	if v == "" {
		return targetOSUnknown
	}

	// Anything that looks like a runtime expression, an array, an object,
	// or a multi-label list is treated as unknown. We only match plain,
	// well-known single-label runner names.
	if strings.ContainsAny(v, "${}[]\n,") {
		return targetOSUnknown
	}
	if strings.ContainsAny(v, " \t") {
		return targetOSUnknown
	}

	// Lower-case match on the label prefix. GitHub-hosted runner labels
	// are case-insensitive.
	lower := strings.ToLower(v)

	// Special labels that we deliberately keep on the unknown path get
	// checked first, so that they win over generic prefix matches like
	// "ubuntu-*" (the custom-image label happens to start with "ubuntu-").
	if strings.EqualFold(v, runnerlabels.CustomImageLabel) {
		// The custom-image runner is Linux today, but it is provisioned
		// out of band and we do not want a single source of truth for
		// "what OS the custom image is" to live in this file. The
		// custom-image flow already sets UsePreinstalledRuntime and has
		// its own dedicated steps, so falling through to the legacy
		// multi-OS workflow is the safe default here.
		return targetOSUnknown
	}
	if strings.EqualFold(v, runnerlabels.SelfHostedLabel) {
		return targetOSUnknown
	}

	if strings.HasPrefix(lower, "ubuntu-") || lower == "ubuntu" {
		return targetOSLinux
	}
	if strings.HasPrefix(lower, "windows-") || lower == "windows" {
		return targetOSWindows
	}

	return targetOSUnknown
}
