// Package agenticapp provides App, Provider and other types to manage
// GitHub Agentic Apps.
package agenticapp

import (
	"slices"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
)

// NewAppsFromConfig creates a Copilot app and additional agentic apps from the provided configuration.
func NewAppsFromConfig(cfg *config.Config, ght githubtwirp.ClientInterface) (*Copilot, []sweagentd.AgenticApp, error) {
	copilot, err := NewCopilotFromConfig(cfg)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to create Copilot app: %w", err)
	}

	var apps []sweagentd.AgenticApp
	if cfg.CodexGitHubAppID != 0 {
		// Only create Codex if is configured
		codex, err := NewCodexFromConfig(cfg, ght)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to create Codex app: %w", err)
		}

		apps = append(apps, codex)
	}

	if cfg.ClaudeGitHubAppID != 0 {
		// Only create Claude if is configured
		claude, err := NewClaudeFromConfig(cfg, ght)
		if err != nil {
			return nil, nil, goerrors.Errorf("failed to create Claude app: %w", err)
		}

		apps = append(apps, claude)
	}

	return copilot, apps, nil
}

// CopilotCodeReviewAppSlug is the slug for the CCR GitHub App - some APIs return this string rather than `Copilot`
const CopilotCodeReviewAppSlug = "copilot-pull-request-reviewer"

var allowlistedBotLogins = []string{
	CopilotCodeReviewAppSlug,
	CopilotCodeReviewAppSlug + "[bot]",
}

type botChecker interface {
	IsBot() bool
	GetLogin() string
}

// IsAllowlistedBot checks if the given actor is a bot and is in the allowlist.
func IsAllowlistedBot(actor botChecker) bool {
	if !actor.IsBot() {
		return false
	}

	return slices.Contains(allowlistedBotLogins, actor.GetLogin())
}
