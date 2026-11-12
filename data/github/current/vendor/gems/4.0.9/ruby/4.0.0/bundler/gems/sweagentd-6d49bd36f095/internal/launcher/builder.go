package launcher

import (
	"context"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sandbox"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/traceparent"
)

// Builder constructs an AgentLauncher on demand. Concrete launchers
// are cheap to instantiate, so each call returns a fresh instance.
//
// Callers that have per-job context (and therefore can route between
// launchers — for example, AgentJobExecutor) choose a Type and pass
// it to Build. Callers without per-job context can use
// EnvironmentDefault to pick the type appropriate for the current
// runtime environment.
type Builder interface {
	// Build returns a freshly constructed launcher of the given type.
	// Any configured launcher type can be built in any environment; the
	// caller is responsible for choosing a type that makes sense for
	// the request (typically by starting from EnvironmentDefault and
	// overriding based on per-job signals).
	Build(ctx context.Context, t Type) (AgentLauncher, error)
	// EnvironmentDefault returns the launcher type that should be used
	// by default in the current runtime environment: TypeActions in
	// production (always), TypeDocker in development (overridable to
	// TypeActions via AGENT_LAUNCHER=actions). This is only a default;
	// callers can still pass any other Type to Build.
	EnvironmentDefault() Type
}

// ConfigBuilder is the default Builder implementation. It pre-resolves the
// shared launcher options at construction time and constructs a fresh
// concrete launcher on each Build call.
type ConfigBuilder struct {
	isDevelopment      bool
	developmentDefault Type

	// dependencies shared by all launcher implementations
	obsv                observability.Exporters
	ffClient            featureflags.Client
	ghTwirp             githubtwirp.ClientInterface
	githubClientFactory github.ClientFactoryInterface
	spokes              sweagentd.Spokes
	appProvider         *agenticapp.Provider

	// per-type pre-resolved opts
	actionsOpts ActionsLauncherOpts
	dockerOpts  DockerLauncherOpts
	sandboxOpts SandboxLauncherOpts
	sandboxSvc  sandboxService
}

// NewBuilderFromConfig returns a *ConfigBuilder that can construct any
// of the configured launcher types on demand. The default Type is pinned by the
// runtime environment: production always defaults to Actions, while development
// defaults to Docker unless AGENT_LAUNCHER=actions is set.
//
// We return the concrete *ConfigBuilder rather than the Builder
// interface so callers that need configuration knobs (for example, the
// docker workflow-completion handler in development) can call them
// directly without a type assertion. Callers that only need to build
// launchers should accept the Builder interface.
func NewBuilderFromConfig(
	cfg *config.Config,
	obsv observability.Exporters,
	ghTwirp githubtwirp.ClientInterface,
	ffClient featureflags.Client,
	githubClientFactory github.ClientFactoryInterface,
	spokes sweagentd.Spokes,
	appProvider *agenticapp.Provider,
) (*ConfigBuilder, error) {
	runtimeSHA := cfg.Sha
	if cfg.IsDevelopment() {
		runtimeSHA = ""
	} else if runtimeSHA == "" {
		return nil, goerrors.New("APP_SHA must be set in non-development environments")
	}

	// TODO: Outbound calls need to support tenant awareness #3815
	traceParentPropagator, err := traceparent.NewPropagator([]byte(cfg.CapiHMACKey))
	if err != nil {
		return nil, goerrors.Errorf("failed to create trace context propagator: %w", err)
	}

	agentLauncherOpts := AgentLauncherOpts{
		CopilotAPIURL:                        cfg.CopilotAPIURL,
		UploadsURL:                           cfg.GitHubUploadsURL,
		RuntimeSHA:                           runtimeSHA,
		RuntimeSubmoduleSHA:                  runtimeSubmoduleSHA,
		DownloadsURL:                         cfg.GitHubDownloadsURL,
		SecretScanningURL:                    cfg.SecretScanningURL,
		AgentCallbackURL:                     cfg.AgentCallbackURL,
		ModelOverride:                        cfg.ModelOverride,
		AgentDebug:                           cfg.AgentDebug,
		AgentFirewallEnabledDefault:          cfg.AgentFirewallEnabledDefault,
		AgentFirewallRuleSetAllowListDefault: cfg.AgentFirewallRuleSetAllowListDefault,
		AgentFirewallRequiredAllowList:       cfg.AgentFirewallRequiredAllowList,
		Environment:                          cfg.EnvironmentName,
		IsDevelopmentEnvironment:             cfg.IsDevelopment(),
		IsStagingEnvironment:                 cfg.Environment == config.EnvironmentStaging,
		IsProximaEnvironment:                 cfg.Environment == config.EnvironmentProxima,
		MCPEnabled:                           cfg.MCPEnabled,
		AgentTimeoutMin:                      cfg.AgentTimeoutMin,
		TraceParentPropagator:                traceParentPropagator,
		GitHubMCPURLOverride:                 cfg.GitHubMCPURLOverride,

		// TODO(josebalius): App Specific
		GitHubCopilotAPIToken: cfg.GitHubCopilotAPIToken,
	}

	externalLauncherOpts := ExternalLauncherOpts{
		AgentLauncherOpts:    agentLauncherOpts,
		GitHubServerURL:      cfg.GitHubServerURL,
		CAPIHMACKey:          cfg.CapiHMACKey,
		CopilotIntegrationID: cfg.CopilotIntegrationID,
	}

	// In development we let AGENT_LAUNCHER pick the default so a
	// developer can run against the Actions launcher locally without
	// code changes. The env var is intentionally only consulted in
	// development; production always defaults to Actions regardless of
	// what is set so we cannot accidentally route prod traffic through
	// docker.
	developmentDefault := TypeDocker
	if cfg.IsDevelopment() && cfg.AgentLauncher == config.AgentLauncherActions {
		developmentDefault = TypeActions
	}

	return &ConfigBuilder{
		isDevelopment:       cfg.IsDevelopment(),
		developmentDefault:  developmentDefault,
		obsv:                obsv,
		ffClient:            ffClient,
		ghTwirp:             ghTwirp,
		githubClientFactory: githubClientFactory,
		spokes:              spokes,
		appProvider:         appProvider,
		actionsOpts: ActionsLauncherOpts{
			AgentLauncherOpts:          agentLauncherOpts,
			ActionsDefaultRunsOnLabels: cfg.ActionsDefaultRunsOnLabels,
		},
		dockerOpts: DockerLauncherOpts{
			ExternalLauncherOpts:    externalLauncherOpts,
			AnthropicKeyOpts:        AnthropicKeyOpts{AnthropicAPIKey: cfg.AnthropicAPIKey},
			ContainerImage:          cfg.DockerAgentContainerImage,
			DockerAIPProxy:          cfg.DockerAIPProxy,
			DockerUseHostNetworking: cfg.DockerUseHostNetworking,
			DockerMapPort:           cfg.DockerMapPort,
			EnginePath:              cfg.DockerEnginePath,
			EngineInferenceToken:    cfg.DockerEngineInferenceToken,
		},
		sandboxOpts: SandboxLauncherOpts{
			ExternalLauncherOpts: externalLauncherOpts,
		},
		sandboxSvc: sandbox.NewService(obsv, ffClient, ghTwirp, sandbox.ServiceOpts{
			LaunchTwirpBaseURL:        cfg.LaunchTwirpAPIURL,
			LaunchTwirpHMACKey:        cfg.LaunchTwirpHMACKey,
			MissionControlBaseURL:     cfg.SandboxMCBaseURL,
			UseDockerBackend:          cfg.SandboxUseDocker,
			GitHubServerURL:           cfg.GitHubServerURL,
			CopilotAPIURL:             cfg.CopilotAPIURL,
			RequiredFirewallAllowList: cfg.AgentFirewallRequiredAllowList,
		}),
	}, nil
}

// Build returns a freshly constructed launcher of the given type. Any
// configured launcher type can be built in any environment; callers
// (typically AgentJobExecutor) decide which type they actually want
// using EnvironmentDefault as a starting point and overriding from
// there. Build itself stays permissive so that, for example, a
// developer can run against the Actions launcher without flipping any
// process-wide flag.
func (b *ConfigBuilder) Build(_ context.Context, t Type) (AgentLauncher, error) {
	switch t {
	case TypeDocker:
		al, err := NewDockerLauncher(b.obsv, b.ffClient, b.ghTwirp, b.appProvider, &b.dockerOpts)
		if err != nil {
			return nil, goerrors.Errorf("failed to create Docker launcher: %w", err)
		}
		return al, nil
	case TypeActions:
		al, err := NewActionsLauncher(b.obsv, b.ffClient, b.githubClientFactory, b.ghTwirp, b.spokes, b.actionsOpts, b.appProvider)
		if err != nil {
			return nil, goerrors.Errorf("failed to create Actions launcher: %w", err)
		}
		return al, nil
	case TypeSandbox:
		return NewSandboxLauncher(b.obsv, b.ffClient, b.sandboxSvc, b.ghTwirp.SweagentdAPI(), b.sandboxOpts), nil
	default:
		return nil, goerrors.Errorf("unknown launcher type %q", t)
	}
}

// EnvironmentDefault returns the launcher type that should be used by
// default in the current runtime environment. Production always
// returns TypeActions. Development returns TypeDocker by default but
// honors AGENT_LAUNCHER=actions so a developer can run against the
// Actions launcher locally without code changes. This is only a
// default; callers can still pass any other Type to Build.
func (b *ConfigBuilder) EnvironmentDefault() Type {
	if b.isDevelopment {
		return b.developmentDefault
	}
	return TypeActions
}

// SetWorkflowCompletedHandler configures the workflow completion
// handler that will be threaded into every DockerLauncher built by this
// builder. This is used in development to wire docker container exits
// into the same finalization flow as GitHub Actions workflow_run events.
func (b *ConfigBuilder) SetWorkflowCompletedHandler(handler WorkflowRunCompletedHandler) {
	b.dockerOpts.WorkflowCompletedHandler = handler
}

// staticBuilder is a Builder that always returns the same launcher.
// Useful for tests and for cases where the launcher is predetermined.
type staticBuilder struct {
	launcher AgentLauncher
}

// NewStaticBuilder returns a Builder that always returns the provided
// AgentLauncher.
func NewStaticBuilder(al AgentLauncher) Builder {
	return &staticBuilder{launcher: al}
}

// Build returns the wrapped launcher.
func (b *staticBuilder) Build(_ context.Context, _ Type) (AgentLauncher, error) {
	return b.launcher, nil
}

// EnvironmentDefault returns the type of the wrapped launcher.
func (b *staticBuilder) EnvironmentDefault() Type {
	return b.launcher.LauncherType()
}
