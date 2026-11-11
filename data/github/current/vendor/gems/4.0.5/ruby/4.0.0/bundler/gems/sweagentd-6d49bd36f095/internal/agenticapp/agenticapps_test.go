package agenticapp

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func newTestConfig(t *testing.T) *config.Config {
	t.Helper()
	return &config.Config{}
}

func TestAgenticApps(t *testing.T) {
	ctx := context.Background()

	t.Run("successfully returns copilot and additional apps", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:       2,
						AppLogin:    "openai-code-agent",
						AppBotId:    20,
						BotLogin:    "openai-code-agent[bot]",
						CommitLogin: "codex-commit",
						CommitEmail: "codex@github.com",
					},
					{
						AppId:       3,
						AppLogin:    "anthropic-code-agent",
						AppBotId:    30,
						BotLogin:    "anthropic-code-agent[bot]",
						CommitLogin: "claude-commit",
						CommitEmail: "claude@github.com",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Len(t, apps, 2)

		// Verify copilot
		require.Equal(t, int64(1), copilot.AppID())
		require.Equal(t, int64(10), copilot.BotID())
		require.Equal(t, "copilot-swe-agent[bot]", copilot.BotLogin())

		// Verify codex (first additional app)
		require.Equal(t, int64(2), apps[0].AppID())
		require.Equal(t, int64(20), apps[0].BotID())

		// Verify claude (second additional app)
		require.Equal(t, int64(3), apps[1].AppID())
		require.Equal(t, int64(30), apps[1].BotID())
	})

	t.Run("returns copilot only when no additional apps", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Empty(t, apps)
		require.Equal(t, int64(1), copilot.AppID())
	})

	t.Run("returns codex only when copilot not present", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       2,
						AppLogin:    "openai-code-agent",
						AppBotId:    20,
						BotLogin:    "openai-code-agent[bot]",
						CommitLogin: "codex-commit",
						CommitEmail: "codex@github.com",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.Nil(t, copilot)
		require.Len(t, apps, 1)
		require.Equal(t, int64(2), apps[0].AppID())
	})

	t.Run("returns error when API call fails", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return nil, errors.New("API error")
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.Error(t, err)
		require.Nil(t, copilot)
		require.Nil(t, apps)
		require.Contains(t, err.Error(), "failed to get agentic apps")
		require.Contains(t, err.Error(), "API error")
	})

	t.Run("skips unknown app login", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:       999,
						AppLogin:    "unknown-agent",
						AppBotId:    999,
						BotLogin:    "unknown-agent[bot]",
						CommitLogin: "unknown-commit",
						CommitEmail: "unknown@github.com",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Empty(t, apps)
		require.Equal(t, int64(1), copilot.AppID())
	})

	t.Run("returns empty when no apps returned", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.Nil(t, copilot)
		require.Empty(t, apps)
	})

	t.Run("returns claude only when codex not present", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       3,
						AppLogin:    "anthropic-code-agent",
						AppBotId:    30,
						BotLogin:    "anthropic-code-agent[bot]",
						CommitLogin: "claude-commit",
						CommitEmail: "claude@github.com",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.Nil(t, copilot)
		require.Len(t, apps, 1)
		require.Equal(t, int64(3), apps[0].AppID())
		require.Equal(t, "anthropic-code-agent[bot]", apps[0].BotLogin())
	})

	t.Run("third party app receives model_vendors from proto", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:        42,
						AppLogin:     "devin-engine",
						AppBotId:     420,
						BotLogin:     "devin-engine[bot]",
						CommitLogin:  "devin-commit",
						CommitEmail:  "devin@cognition.ai",
						HasSource:    true,
						SourceUrl:    "https://github.com/cognition-ai/devin-engine",
						ModelVendors: []string{"Anthropic"},
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Len(t, apps, 1)

		thirdParty, ok := apps[0].(*ThirdParty)
		require.True(t, ok, "expected ThirdParty app")
		require.Equal(t, int64(42), thirdParty.AppID())
		require.Equal(t, []string{"Anthropic"}, thirdParty.ModelVendors())
		require.True(t, thirdParty.HasSource())
		require.Equal(t, "https://github.com/cognition-ai/devin-engine", thirdParty.SourceURL())
	})

	t.Run("third party app with empty model_vendors", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:       43,
						AppLogin:    "some-engine",
						AppBotId:    430,
						BotLogin:    "some-engine[bot]",
						CommitLogin: "some-commit",
						CommitEmail: "some@engine.com",
						HasSource:   true,
						SourceUrl:   "https://github.com/example/some-engine",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Len(t, apps, 1)

		thirdParty, ok := apps[0].(*ThirdParty)
		require.True(t, ok, "expected ThirdParty app")
		require.Empty(t, thirdParty.ModelVendors(), "empty vendors should pass through as empty slice")
	})

	t.Run("third party app uses app_slug for mentionable slug", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:       44,
						AppLogin:    "My App With Spaces",
						AppSlug:     "my-app-with-spaces",
						AppBotId:    440,
						BotLogin:    "my-app-with-spaces[bot]",
						CommitLogin: "myapp-commit",
						CommitEmail: "myapp@example.com",
						HasSource:   true,
						SourceUrl:   "https://github.com/example/my-app",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Len(t, apps, 1)

		thirdParty, ok := apps[0].(*ThirdParty)
		require.True(t, ok, "expected ThirdParty app")
		require.Equal(t, "my-app-with-spaces[agent]", thirdParty.MentionableSlug(), "should use slug, not display name with spaces")
	})

	t.Run("third party app falls back to app_login when app_slug is empty", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:       45,
						AppLogin:    "legacy-agent",
						AppBotId:    450,
						BotLogin:    "legacy-agent[bot]",
						CommitLogin: "legacy-commit",
						CommitEmail: "legacy@example.com",
						HasSource:   true,
						SourceUrl:   "https://github.com/example/legacy-agent",
					},
				},
			}, nil
		}

		copilot, apps, err := AgenticApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Len(t, apps, 1)

		thirdParty, ok := apps[0].(*ThirdParty)
		require.True(t, ok, "expected ThirdParty app")
		require.Equal(t, "legacy-agent[agent]", thirdParty.MentionableSlug(), "should fall back to app_login when slug is empty")
	})
}

func TestNewApps(t *testing.T) {
	ctx := context.Background()

	t.Run("returns apps from monolith when copilot and additional apps are present", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:       2,
						AppLogin:    "openai-code-agent",
						AppBotId:    20,
						BotLogin:    "openai-code-agent[bot]",
						CommitLogin: "codex-commit",
						CommitEmail: "codex@github.com",
					},
				},
			}, nil
		}

		copilot, apps, err := NewApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Len(t, apps, 1)
		require.Equal(t, int64(1), copilot.AppID())
		require.Equal(t, int64(2), apps[0].AppID())
	})

	t.Run("returns error when monolith returns error", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return nil, errors.New("monolith error")
		}

		copilot, apps, err := NewApps(ctx, cfg, ghtwirp, obsv)
		require.Error(t, err)
		require.Nil(t, copilot)
		require.Nil(t, apps)
		require.Contains(t, err.Error(), "failed to load agentic apps from monolith")
	})

	t.Run("returns apps from monolith with all three agentic apps", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		cfg := newTestConfig(t)
		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopSweagentdAPI.MockGetAgenticApps = func(ctx context.Context, req *sweagentdv1.GetAgenticAppsRequest) (*sweagentdv1.GetAgenticAppsResponse, error) {
			return &sweagentdv1.GetAgenticAppsResponse{
				AgenticApps: []*sweagentdv1.AgenticApp{
					{
						AppId:       1,
						AppLogin:    "copilot-swe-agent",
						AppBotId:    10,
						BotLogin:    "copilot-swe-agent[bot]",
						CommitLogin: "copilot-commit",
						CommitEmail: "copilot@github.com",
					},
					{
						AppId:       2,
						AppLogin:    "openai-code-agent",
						AppBotId:    20,
						BotLogin:    "openai-code-agent[bot]",
						CommitLogin: "codex-commit",
						CommitEmail: "codex@github.com",
					},
					{
						AppId:       3,
						AppLogin:    "anthropic-code-agent",
						AppBotId:    30,
						BotLogin:    "anthropic-code-agent[bot]",
						CommitLogin: "claude-commit",
						CommitEmail: "claude@github.com",
					},
				},
			}, nil
		}

		copilot, apps, err := NewApps(ctx, cfg, ghtwirp, obsv)
		require.NoError(t, err)
		require.NotNil(t, copilot)
		require.Len(t, apps, 2)
		require.Equal(t, int64(1), copilot.AppID())
		require.Equal(t, int64(2), apps[0].AppID())
		require.Equal(t, int64(3), apps[1].AppID())
	})
}

func TestAppKindClassification(t *testing.T) {
	tests := []struct {
		name           string
		app            func() sweagentd.AgenticApp
		isGlobal       bool
		isPartner      bool
		isThirdParty   bool
		hasSource      bool
		agentSourceNil bool
	}{
		{
			name: "Copilot is a global app",
			app: func() sweagentd.AgenticApp {
				return NewCopilot(1, "copilot-swe-agent", 10, "bot", "commit", "email")
			},
			isGlobal:       true,
			agentSourceNil: true,
		},
		{
			name: "CopilotCodeReview is a global app",
			app: func() sweagentd.AgenticApp {
				return NewCopilotCodeReview(2, "copilot-pull-request-reviewer", 20, "bot", "commit", "email")
			},
			isGlobal:       true,
			agentSourceNil: true,
		},
		{
			name: "CodeScanning is a global app",
			app: func() sweagentd.AgenticApp {
				return NewCodeScanning(3, "github-advanced-security", 30, "bot", "commit", "email")
			},
			isGlobal:       true,
			agentSourceNil: true,
		},
		{
			name: "Claude is a partner app",
			app: func() sweagentd.AgenticApp {
				return NewClaude(4, "anthropic-code-agent", 40, "bot", "commit", "email")
			},
			isPartner:      true,
			agentSourceNil: true,
		},
		{
			name: "Codex is a partner app",
			app: func() sweagentd.AgenticApp {
				return NewCodex(5, "openai-code-agent", 50, "bot", "commit", "email")
			},
			isPartner:      true,
			agentSourceNil: true,
		},
		{
			name: "ThirdParty is a third-party app with source",
			app: func() sweagentd.AgenticApp {
				return NewThirdParty(6, "my-agent", "", 60, "bot", "commit", "email", &sweagentd.AgentSource{URL: "https://github.com/org/repo", SHA: "abc123"}, nil)
			},
			isThirdParty: true,
			hasSource:    true,
		},
		{
			name: "ThirdParty with nil agent source",
			app: func() sweagentd.AgenticApp {
				return NewThirdParty(7, "my-agent", "", 70, "bot", "commit", "email", nil, nil)
			},
			isThirdParty:   true,
			agentSourceNil: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app := tt.app()

			require.Equal(t, tt.isGlobal, app.IsGlobalApp(), "IsGlobalApp")
			require.Equal(t, tt.isPartner, app.IsPartnerApp(), "IsPartnerApp")
			require.Equal(t, tt.isThirdParty, app.IsThirdPartyApp(), "IsThirdPartyApp")

			// Exactly one classification must be true
			count := 0
			if app.IsGlobalApp() {
				count++
			}
			if app.IsPartnerApp() {
				count++
			}
			if app.IsThirdPartyApp() {
				count++
			}
			require.Equal(t, 1, count, "exactly one of IsGlobalApp/IsPartnerApp/IsThirdPartyApp must be true")

			if tt.agentSourceNil {
				require.Nil(t, app.AgentSource())
			} else {
				require.NotNil(t, app.AgentSource())
			}

			require.Equal(t, tt.hasSource, app.HasSource())

			if tt.hasSource {
				require.NotEmpty(t, app.SourceURL())
				require.Equal(t, app.AgentSource().URL, app.SourceURL())
			}
		})
	}
}
