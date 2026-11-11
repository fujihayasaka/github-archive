package agent

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

var (
	// ErrFailedToResolvePluginAgentForJob is returned when the service fails to resolve a plugin agent.
	ErrFailedToResolvePluginAgentForJob = goerrors.New("failed to resolve plugin agent for job")
	// ErrFailedToResolveAgentForExchange is returned when the service fails to resolve an agent for a token exchange.
	ErrFailedToResolveAgentForExchange = goerrors.New("failed to resolve agent for token exchange")
)

// ExecuteTokenExchangeParams encapsulates the parameters needed to execute an OIDC token exchange for a job.
type ExecuteTokenExchangeParams struct {
	Job            *jobs.Job
	UserInfo       *requestctx.UserInfo
	AgentName      string
	AgentVersion   string
	SecretNames    []string
	MCPServerNames []string
	App            sweagentd.AgenticApp
}

// ExecuteTokenExchange performs the OIDC token exchange for the given job and parameters, returning the exchange result or an error.
func (s *Service) ExecuteTokenExchange(ctx context.Context, params ExecuteTokenExchangeParams) (*oidc.ExchangeResult, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "agent.Service.ExecuteTokenExchange")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "execute_token_exchange",
	})
	defer func() {
		s.obsv.DistributionMs(ctx, "agent.Service.request_duration", baseTags, time.Since(start))
	}()
	s.obsv.Increment(ctx, "agent.Service.requests", baseTags)
	span.SetAttributes(
		attribute.Int("agent.oidc.secret_name_count", len(params.SecretNames)),
		attribute.Int("agent.oidc.mcp_server_name_count", len(params.MCPServerNames)),
	)

	var err error
	if s.oidcSvc == nil || s.pluginSvc == nil || s.customAgentSvc == nil {
		err = goerrors.New("prerequisites are nil, cannot execute token exchange")
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, "prerequisites_missing", err)
		return nil, err
	}

	// Load repo plugins (if enabled)
	loadRepoPluginsStart := time.Now()
	repoPlugins, err := s.loadRepoPlugins(ctx, params.Job)
	s.obsv.DistributionMs(ctx, "agent.Service.load_repo_plugins_duration", baseTags, time.Since(loadRepoPluginsStart))
	if err != nil {
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, "load_repo_plugins_failed", err)
		return nil, goerrors.Errorf("failed to load repo plugins for agent resolution: %w", err)
	}

	// Determine config resolution parameters
	p := oidc.ResolveConfigurationParams{
		App:            params.App,
		RepoID:         params.Job.RepoID,
		ActorID:        params.Job.ActorID,
		SecretNames:    params.SecretNames,
		MCPServerNames: params.MCPServerNames,
	}

	// Determine which agent applies to the exchange and resolve the app plugin if one exists
	appPlugin, errorReason, err := s.resolveAgentForExchange(ctx, baseTags, params, repoPlugins, &p)
	if err != nil {
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, errorReason, err)
		return nil, err
	}

	// Resolve plugin MCP configs for OIDC when MCP server names are requested
	if len(params.MCPServerNames) > 0 {
		if appPlugin != nil && len(params.MCPServerNames) > 0 {
			p.AppMCPConfigs = append(p.AppMCPConfigs, mcpconfig.JSON{Servers: appPlugin.Info.MCPServers})
		}
		if s.ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentPluginsEnabled, params.Job) {
			for _, plugin := range repoPlugins {
				if len(params.MCPServerNames) > 0 {
					p.AdditionalMCPConfigs = append(p.AdditionalMCPConfigs, mcpconfig.JSON{Servers: plugin.Info.MCPServers})
				}
			}
		}
	}

	// Resolve (and if needed discover) the full agent configuration
	resolved, err := s.oidcSvc.ResolveConfiguration(ctx, p)
	if err != nil {
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, "resolve_oidc_configuration_failed", err)
		return nil, goerrors.Errorf("failed to resolve OIDC configuration: %w", err)
	}

	// Don't rely on the names of the owner/repo or even the owner ID on the job since it may be stale.
	// Use the twirp API to get fresh repo installation info including the owner type.
	repoInfo, err := s.ghtwirp.GetInstallationInfo(ctx, params.App.AppID(), params.Job.RepoID)
	if err != nil {
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, "get_installation_info_failed", err)
		return nil, err
	}

	// Want to be sure this is zero so we don't accidentally use a global installation ID for a global agent
	installationID := repoInfo.AppInstallationID
	if repoInfo.AppIsGlobal {
		installationID = 0
	}

	// Resolve the platform (CCA) client ID, cached across executions since it
	// does not change for a given copilot-swe-agent app.
	if s.appProvider == nil {
		err = goerrors.New("app provider is nil, cannot resolve platform client ID")
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, "app_provider_missing", err)
		return nil, err
	}
	platformClientID, err := s.resolvePlatformClientID(ctx, params.Job.RepoID)
	if err != nil {
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, "resolve_platform_client_id_failed", err)
		return nil, err
	}

	// agent_client_id is set only when the running app differs from CCA.
	var agentClientID string
	if !s.appProvider.IsCopilotCodingAgentApp(params.App.AppID()) {
		agentClientID = repoInfo.AppClientID
	}

	// Resolve agent name and version from the resolved agent if available
	agentName := params.AgentName
	agentVersion := params.AgentVersion
	if agentName == "" && p.Agent != nil {
		agentName = p.Agent.Name()
		agentVersion = p.Agent.Version()
	}

	// Do the exchange
	result, err := s.oidcSvc.ExchangeTokens(ctx, resolved, oidc.TokenParams{
		Actor:              params.Job.ActorLogin,
		ActorID:            params.Job.ActorID,
		ActorType:          params.Job.ActorType,
		RepoID:             repoInfo.ID,
		Repo:               repoInfo.Name,
		OwnerID:            repoInfo.OwnerID,
		Owner:              repoInfo.OwnerLogin,
		OwnerType:          repoInfo.OwnerType,
		AppID:              params.App.AppID(),
		AppClientID:        agentClientID,
		PlatformClientID:   platformClientID,
		AppInstallationID:  installationID,
		SessionID:          params.Job.SessionID,
		CustomAgentName:    agentName,
		CustomAgentVersion: agentVersion,
	})
	if err != nil {
		if errors.Is(err, oidc.ErrPartialSuccess) {
			span.SetAttributes(attribute.String("agent.oidc.result", "partial_success"))
			s.obsv.Increment(ctx, "agent.Service.success_with_errors", baseTags.Merge(stats.Tags{
				"success":      "true",
				"error_reason": "exchange_tokens_partial_success",
			}))
			return result, err
		}
		s.recordExecuteTokenExchangeError(ctx, span, baseTags, "exchange_tokens_failed", err)
		return nil, goerrors.Errorf("failed to exchange OIDC tokens: %w", err)
	}

	span.SetAttributes(attribute.String("agent.oidc.result", "success"))
	s.obsv.Increment(ctx, "agent.Service.success", baseTags.Merge(stats.Tags{
		"success": "true",
	}))

	return result, nil
}

func (s *Service) recordExecuteTokenExchangeError(ctx context.Context, span trace.Span, baseTags stats.Tags, errorReason string, err error) {
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
	span.SetAttributes(
		attribute.String("agent.oidc.result", "failure"),
		attribute.String("agent.oidc.error_reason", errorReason),
	)
	s.obsv.Increment(ctx, "agent.Service.errors", baseTags.Merge(stats.Tags{
		"success":      "false",
		"error_reason": errorReason,
	}))
}

func (s *Service) recordResolveAgentDuration(ctx context.Context, baseTags stats.Tags, start time.Time) {
	s.obsv.DistributionMs(ctx, "agent.Service.resolve_agent_duration", baseTags, time.Since(start))
}

func (s *Service) resolveAgentForExchange(ctx context.Context, baseTags stats.Tags, params ExecuteTokenExchangeParams, repoPlugins []*plugins.Plugin, p *oidc.ResolveConfigurationParams) (*plugins.Plugin, string, error) {
	resolveAgentStart := time.Now()
	defer s.recordResolveAgentDuration(ctx, baseTags, resolveAgentStart)

	if params.AgentName == "" || params.AgentName == params.Job.CustomAgent.Name {
		// Use custom agent on job if one exists and no agent is explicitly specified
		agent, appPlugin, agentFromApp, err := s.GetAgentForJob(ctx, params.Job, params.App)
		if err != nil {
			return nil, "get_agent_for_job_failed", goerrors.Errorf("failed to resolve agent for job: %w", err)
		}
		p.Agent = agent
		p.AgentFromApp = agentFromApp
		return appPlugin, "", nil
	}

	// If a custom agent is explicitly specified (dynamic scenario) - get it by name across all possible plugins
	appPlugin, err := s.pluginSvc.GetPluginForApp(ctx, params.App)
	if err != nil {
		return nil, "get_plugin_for_app_failed", goerrors.Errorf("failed to get plugin for app: %w", err)
	}
	agent, agentFromApp, err := s.resolveNamedAgent(ctx, appPlugin, repoPlugins, params)
	if err != nil {
		return nil, "resolve_named_agent_failed", goerrors.Errorf("failed to resolve agent for job: %w", err)
	}

	p.Agent = agent
	p.AgentFromApp = agentFromApp
	return appPlugin, "", nil
}

type platformClientResolutionState struct {
	mu        sync.Mutex
	cond      *sync.Cond
	resolving bool
	clientID  string
}

func newPlatformClientResolutionState() *platformClientResolutionState {
	state := &platformClientResolutionState{}
	state.cond = sync.NewCond(&state.mu)
	return state
}

var platformClientResolutionStates sync.Map

// resolvePlatformClientID returns the cached CCA client ID, fetching it on the
// first call via GetInstallationInfo. The value is constant for a given
// copilot-swe-agent app and is safe to cache for the lifetime of the service.
func (s *Service) resolvePlatformClientID(ctx context.Context, repoID int64) (string, error) {
	stateAny, _ := platformClientResolutionStates.LoadOrStore(s, newPlatformClientResolutionState())
	state, ok := stateAny.(*platformClientResolutionState)
	if !ok {
		return "", goerrors.New("failed to assert platform client resolution state type")
	}

	state.mu.Lock()
	for state.resolving {
		state.cond.Wait()
	}
	if state.clientID != "" {
		clientID := state.clientID
		state.mu.Unlock()
		return clientID, nil
	}
	state.resolving = true
	state.mu.Unlock()

	info, err := s.ghtwirp.GetInstallationInfo(ctx, s.appProvider.CopilotApp().AppID(), repoID)
	var resolveErr error
	var clientID string
	switch {
	case err != nil:
		resolveErr = goerrors.Errorf("failed to resolve platform client ID: %w", err)
	case info.AppClientID == "":
		resolveErr = goerrors.New("platform client ID is empty")
	default:
		clientID = info.AppClientID
	}

	state.mu.Lock()
	if resolveErr == nil {
		state.clientID = clientID
		s.platformClientID = clientID
	}
	state.resolving = false
	state.cond.Broadcast()
	cachedClientID := state.clientID
	state.mu.Unlock()

	if resolveErr != nil {
		return "", resolveErr
	}
	return cachedClientID, nil
}

// resolveNamedAgent resolves a dynamically-selected agent by name. It first tries the
// job's repository, then falls back to searching configured plugins and the app's plugin.
// Returns the agent and whether it was resolved from the app plugin (agentFromApp).
func (s *Service) resolveNamedAgent(ctx context.Context, appPlugin *plugins.Plugin, repoPlugins []*plugins.Plugin, params ExecuteTokenExchangeParams) (sweagentd.CustomAgent, bool, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "agent.Service.resolveNamedAgent")
	defer span.End()

	if appPlugin != nil {
		agent, err := s.pluginSvc.GetPluginAgent(ctx, appPlugin, params.AgentName)
		if err != nil && !errors.Is(err, plugins.ErrAgentNotFoundInPlugin) {
			return nil, false, goerrors.Errorf("%w: failed to get agent from app plugin: %w", ErrFailedToResolveAgentForExchange, err)
		}
		if agent != nil {
			return agent, true, nil
		}
	}

	for _, plugin := range repoPlugins {
		agent, err := s.pluginSvc.GetPluginAgent(ctx, plugin, params.AgentName)
		if err != nil && !errors.Is(err, plugins.ErrAgentNotFoundInPlugin) {
			return nil, false, goerrors.Errorf("%w: failed to get agent from plugin: %w", ErrFailedToResolveAgentForExchange, err)
		}
		if err == nil && agent != nil {
			return agent, false, nil
		}
	}

	// Attempt to resolve the agent using the custom agent service for repo / org / eneterprise agents
	agent, err := s.customAgentSvc.ResolveByNameAndRepoID(ctx, uint64(params.Job.RepoID), params.AgentName, params.AgentVersion, customagent.ResolveByNameOpts{UserID: params.UserInfo.ID, ErrorOnInvalidConfig: true})
	if err != nil {
		return nil, false, goerrors.Errorf("%w: failed to resolve agent for job: %w", ErrFailedToResolveAgentForExchange, err)
	}
	if agent != nil {
		return agent, false, nil
	}

	return nil, false, ErrFailedToResolveAgentForExchange
}

func (s *Service) loadRepoPlugins(ctx context.Context, job *jobs.Job) ([]*plugins.Plugin, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "agent.Service.loadRepoPlugins")
	defer span.End()

	if !s.ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentPluginsEnabled, job) {
		return []*plugins.Plugin{}, nil
	}

	// Unfortunately we need the repository owner name to get merged settings, but this lookup is now cached so it should happen once and be cheap.
	repo, err := s.ghtwirp.GetRepoById(ctx, job.RepoID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get repo by ID for plugin agent resolution: %w", err)
	}

	// Load merged settings - can be from repo, org, or enterprise levels
	settings, err := s.pluginSvc.LoadMergedSettings(ctx, uint64(job.RepoID), uint64(job.OwnerID), repo.GetOwnerLogin(), []string{})
	if err != nil {
		return nil, goerrors.Errorf("failed to load settings for plugin agent resolution: %w", err)
	}
	if settings == nil {
		return nil, nil
	}

	// Get metadata for plugins
	metadata, err := s.pluginSvc.ResolvePluginRepos(ctx, settings)
	if err != nil {
		return nil, goerrors.Errorf("failed to resolve plugin repos for agent resolution: %w", err)
	}

	// Get plugin details
	var pluginsList []*plugins.Plugin
	for _, meta := range metadata {
		plugin, err := s.pluginSvc.GetPlugin(ctx, meta)
		if err != nil {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to get plugin during agent resolution")
			continue
		}
		if plugin != nil {
			pluginsList = append(pluginsList, plugin)
		}
	}
	return pluginsList, nil
}
