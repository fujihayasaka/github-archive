// Package agenticapp provides App, Provider and other types to manage
// GitHub Agentic Apps.
package agenticapp

import (
	"context"
	"slices"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
)

var allowlistedBotLogins = []string{
	CopilotCodeReviewComputeSlug,
	CopilotCodeReviewComputeSlug + "[bot]",
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

// AgenticApps is a collection of agentic apps, including Copilot and any number of additional apps.
// It loads agentic apps from monolith twirp endpoint GetAgenticApps and populates private keys
// and client secrets from the provided configuration.
// TODO (shaikhul): remove private keys and client secrets dependency once fully tested in prod with mint_server_to_server_token and revoke_tokens endpoints in monolith.
// See https://github.com/github/sweagentd/pull/9881
func AgenticApps(ctx context.Context, cfg *config.Config, ght githubtwirp.ClientInterface, obsv observability.Exporters) (*Copilot, []sweagentd.AgenticApp, error) {
	resp, err := ght.SweagentdAPI().GetAgenticApps(ctx, &sweagentdv1.GetAgenticAppsRequest{})
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get agentic apps: %w", err)
	}

	var apps []sweagentd.AgenticApp
	var copilot *Copilot
	for _, agenticApp := range resp.GetAgenticApps() {
		switch agenticApp.GetAppLogin() {
		case "copilot-swe-agent":
			copilot = NewCopilot(agenticApp.GetAppId(), agenticApp.GetAppLogin(), agenticApp.GetAppBotId(), agenticApp.GetBotLogin(), agenticApp.GetCommitLogin(), agenticApp.GetCommitEmail())
		case "openai-code-agent":
			codex := NewCodex(agenticApp.GetAppId(), agenticApp.GetAppLogin(), agenticApp.GetAppBotId(), agenticApp.GetBotLogin(), agenticApp.GetCommitLogin(), agenticApp.GetCommitEmail())
			apps = append(apps, codex)
		case "anthropic-code-agent":
			claude := NewClaude(agenticApp.GetAppId(), agenticApp.GetAppLogin(), agenticApp.GetAppBotId(), agenticApp.GetBotLogin(), agenticApp.GetCommitLogin(), agenticApp.GetCommitEmail())
			apps = append(apps, claude)
		case "copilot-pull-request-reviewer":
			copilotCodeReview := NewCopilotCodeReview(agenticApp.GetAppId(), agenticApp.GetAppLogin(), agenticApp.GetAppBotId(), agenticApp.GetBotLogin(), agenticApp.GetCommitLogin(), agenticApp.GetCommitEmail())
			apps = append(apps, copilotCodeReview)
		case "github-advanced-security":
			codeScanning := NewCodeScanning(agenticApp.GetAppId(), agenticApp.GetAppLogin(), agenticApp.GetAppBotId(), agenticApp.GetBotLogin(), agenticApp.GetCommitLogin(), agenticApp.GetCommitEmail())
			apps = append(apps, codeScanning)
		default:
			agentSrc := agenticApp.GetAgentSource()
			// look up agent source from twirp response, if not found and app has source, construct agent source from deprecated fields for backward compatibility
			if agentSrc == nil && agenticApp.GetHasSource() {
				agentSrc = &sweagentdv1.AgentSource{Url: agenticApp.GetSourceUrl()}
			}
			if agentSrc != nil && agentSrc.GetUrl() != "" {
				thirdParty := NewThirdParty(agenticApp.GetAppId(), agenticApp.GetAppLogin(), agenticApp.GetAppSlug(), agenticApp.GetAppBotId(), agenticApp.GetBotLogin(), agenticApp.GetCommitLogin(), agenticApp.GetCommitEmail(), &sweagentd.AgentSource{URL: agentSrc.GetUrl(), SHA: agentSrc.GetSha()}, agenticApp.GetModelVendors())
				apps = append(apps, thirdParty)
				continue
			}
			// skip, no agent source found for this app, and it's not a known app login
			obsv.Logger.WithContext(ctx).Warn("skipping unknown agentic app: " + agenticApp.GetAppLogin())
			continue
		}
	}

	return copilot, apps, nil
}

// NewApps attempts to load agentic apps from the monolith twirp endpoint, and falls back to loading from config if that fails
func NewApps(ctx context.Context, cfg *config.Config, ghTwirp githubtwirp.ClientInterface, obsv observability.Exporters) (*Copilot, []sweagentd.AgenticApp, error) {
	copilotAgenticApp, agenticApps, err := AgenticApps(ctx, cfg, ghTwirp, obsv)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to load agentic apps from monolith: %w", err)
	}

	return copilotAgenticApp, agenticApps, nil
}

// NewReloadFunc returns a ReloadFunc that fetches agentic apps from the
// monolith twirp endpoint. This is intended to be passed to
// Provider.WithReloadOnMiss during initialization.
func NewReloadFunc(cfg *config.Config, ghTwirp githubtwirp.ClientInterface, obsv observability.Exporters) ReloadFunc {
	return func(ctx context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		return AgenticApps(ctx, cfg, ghTwirp, obsv)
	}
}
