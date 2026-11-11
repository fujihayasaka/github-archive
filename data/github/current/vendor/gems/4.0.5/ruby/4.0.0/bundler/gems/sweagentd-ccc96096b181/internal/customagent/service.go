package customagent

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
)

var (
	// ErrRepoNotFound is returned when a repository is not found.
	ErrRepoNotFound = errors.New("repository not found")

	// ErrAuthorizationFailed is returned when authorization fails for a repository.
	ErrAuthorizationFailed = errors.New("authorization failed for repository")
)

const (
	orgRepoName = ".github"

	forceDotGitHubAgentsDirPrefix = ".gh:"
)

const (
	// TargetIsVSCodeMessage is returned when the target field is set to a value that should not be picked up by CCA or the CLI.
	TargetIsVSCodeMessage = "Config is for VS Code only"
	// TargetIsGitHubMessage is returned when the target field is set to a value that should not be picked up by VS Code agent mode.
	TargetIsGitHubMessage = "Config is for Copilot coding agent or CLI only"
	// TargetIsUnknownMessage is returned when the target field is set to an unknown value.
	TargetIsUnknownMessage = "Config has unknown target"
)

const (
	// SourceTypeRepo indicates agents from the repository itself.
	SourceTypeRepo = "repo"
	// SourceTypeOrg indicates agents from organization repositories (.github, .github-private).
	SourceTypeOrg = "org"
	// SourceTypeEnterprise indicates agents from the enterprise repository.
	SourceTypeEnterprise = "enterprise"
)

// Service provides methods to interact with custom configurations in GitHub repositories.
// It uses a Twirp-based repository provider to interact with specific repositories.
type Service struct {
	obsv    observability.Exporters
	spokes  sweagentd.Spokes
	trp     *twirpRepoProvider
	ghtwirp githubtwirp.ClientInterface
	ff      featureflags.Client
}

// NewService creates a new Service instance with the provided GitHub client factory.
func NewService(obsv observability.Exporters, spokes sweagentd.Spokes, ghtwirp githubtwirp.ClientInterface, ffClient featureflags.Client) *Service {
	return &Service{
		obsv:    obsv,
		spokes:  spokes,
		trp:     newTwirpRepoProvider(ghtwirp),
		ghtwirp: ghtwirp,
		ff:      ffClient,
	}
}

// IsEnabledForRepoByName retrieves the repository ID and owner ID for a given repository and then checks if the custom agents
// feature is enabled for that repository. In the future this can grow to encompass other policy related checks.
func (s *Service) IsEnabledForRepoByName(ctx context.Context, userID int64, repoOwner, repoName string) (bool, error) {
	twirpRepo, err := s.trp.getRepository(ctx, repoOwner, repoName)
	if err != nil {
		return false, goerrors.Errorf("failed to get repo: %w", err)
	}

	enabled := s.IsEnabledForRepo(ctx, userID, twirpRepo.GetOwnerID(), twirpRepo.GetID())
	s.obsv.Logger.Info("found repo for custom agents, feature flag status", kvp.Bool("enabled", enabled))

	return enabled, nil
}

type ffActors struct {
	userID  int64
	ownerID int64
	repoID  int64
}

func (a *ffActors) GetActorID() int64 {
	return a.userID
}

func (a *ffActors) GetOwnerID() int64 {
	return a.ownerID
}

func (a *ffActors) GetRepositoryID() int64 {
	return a.repoID
}

// IsEnabledForRepo encapsulates any feature flags or other checks that should be performed before enabling the
// custom agents feature for a repository. In the future this can grow to encompass other policy related checks.
func (s *Service) IsEnabledForRepo(ctx context.Context, userID, ownerID, repoID int64) bool {
	actors := ffActors{
		userID:  userID,
		ownerID: ownerID,
		repoID:  repoID,
	}

	return !s.ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentsDisallow, &actors)
}

// FromDB converts a DBRecord representation to an Agent instance. NOTE: Converting with ToDB() and then FromDB() will lose the Prompt and Permissions fields
// if the agent is not a job-scoped agent created via the Twirp API. We intentionally don't save the prompt to the database due to its size.
// If your use case requires the prompt, you should fetch it using the CustomAgentSvc for non-job-scoped scenarios.
//
//nolint:gocritic // hugeParam: db is a large struct but passed by value intentionally for DB record conversion
func (s *Service) FromDB(ctx context.Context, db customagent.DBRecord) (sweagentd.CustomAgent, error) {
	// TODO (belaltaher8): remove "copilot" portion after this lands in prod to not break jobs currently enqueued when this merges. Going forward db.Name for default agent will be "".
	if db.Name == "" || db.Name == DefaultAgentName {
		return Copilot(db.RepoOwnerID, db.RepoID, db.RepoOwner, db.RepoName), nil
	}
	if db.Tools == nil {
		// We see nil tools in the DB despite the fact that the field is non-nullable
		// likely because it was nullable at one point, so handle that.
		db.Tools = []string{"*"}
	}

	// Determine scope - default to repo for backward compatibility
	scope := db.Scope
	if scope == "" {
		scope = customagent.ScopeRepo
	}

	// If this is a job-scoped agent, load prompt and permissions from the record
	if scope == customagent.ScopeJob {
		m := Metadata{
			Name:        db.Name,
			RepoOwnerID: db.RepoOwnerID,
			RepoOwner:   db.RepoOwner,
			RepoID:      db.RepoID,
			RepoName:    db.RepoName,
			Version:     db.Version,
			ConfigError: db.ConfigError,
			Scope:       scope,
		}
		attrs := ConfigAttributes{
			DisplayName:      db.DisplayName,
			Description:      db.Description,
			Tools:            db.Tools,
			MCPConfig:        mcpFromDB(db.MCPServers),
			Target:           db.Target,
			Metadata:         db.Metadata,
			InferenceEnabled: db.InferenceEnabled,
			Prompt:           db.Prompt,
			Permissions:      db.Permissions,
		}
		return NewJobScopedAgent(m, NewConfigWithAttributes(attrs)), nil
	}

	// Otherwise, go get the agent details from the repository
	return s.GetAgentByRepoID(ctx, uint64(db.RepoID), db.Name, db.Version, GetAgentOpts{SkipAuthCheck: true})
}

// ResolveByNameOpts holds options for resolving a custom agent by name.
type ResolveByNameOpts struct {
	ErrorOnInvalidConfig bool
	IncludeSources       []string
	UserID               uint64 // UserID is optional if SkipAuthCheck is true. Otherwise it is used for authorization and feature flags.
	SkipAuthCheck        bool
}

// ResolveByNameAndRepoID resolves a custom agent by name using repository ID and returns it as a sweagentd.CustomAgent interface.
// If the agent is not found at the repository level, it checks the org/enterprise level (".github" repository).
// If found at the org/enterprise level, it wraps the agent in a PrivilegedAgent (pointer to struct).
// If not found at any level, it returns an error.
// But, if errorOnInvalidConfig is false, it will return an agent with parsing errors instead of an error.
func (s *Service) ResolveByNameAndRepoID(
	ctx context.Context, repoID uint64, agentName, version string, opts ResolveByNameOpts,
) (sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.ResolveByNameAndRepoID")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "resolve_by_name_and_repo_id",
	})
	defer func() {
		s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", baseTags, time.Since(start))
	}()
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	// Trim the .gh: prefix if present since we do not need it here. It's only needed for GetAgent to determine directory.
	agentName = strings.TrimPrefix(agentName, forceDotGitHubAgentsDirPrefix)

	_, sourceReposLoaders, err := s.getLazySourceRepoLoadersByID(ctx, opts.UserID, repoID, opts.IncludeSources)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "get_source_loaders_failed")
		return nil, goerrors.Errorf("failed to get source repositories: %w", err)
	}

	agent, err := s.resolveAgentFromLoaders(ctx, opts.UserID, agentName, version, sourceReposLoaders, baseTags, opts)
	if err != nil {
		if errors.Is(err, ErrRequestedAgentNotFound) {
			s.recordServiceWarning(ctx, baseTags, "requested_agent_not_found")
		} else {
			s.recordServiceError(ctx, baseTags, "resolve_by_name_and_repo_id_failed")
		}
		return nil, err
	}

	s.obsv.Increment(ctx, "customagent.Service.success", baseTags)
	return agent, nil
}

// indexedAgents filters out duplicate agents based on their names using the provided index map.
// It updates the index map with the names of the agents it includes in the returned slice.
func indexedAgents(index map[string]struct{}, agents []sweagentd.CustomAgent) []sweagentd.CustomAgent {
	var unique []sweagentd.CustomAgent
	for _, a := range agents {
		if _, exists := index[strings.TrimPrefix(a.Name(), forceDotGitHubAgentsDirPrefix)]; exists {
			continue
		}

		index[a.Name()] = struct{}{}
		unique = append(unique, a)
	}

	return unique
}

// ListAgentsOpts holds options for listing custom agents.
type ListAgentsOpts struct {
	ExcludeInvalidConfig bool
	DedupeNames          bool
	Target               string
	IncludeSources       []string
	UserID               uint64 // UserID is optional if skip auth check is false. It is only used for feature flags otherwise.
	SkipAuthCheck        bool
}

// ListAgents retrieves the list of custom agent configurations for a given repository by name and owner.
// It checks the specified repository first, followed by the ".github" and ".github-private" repositories at the organization level.
// It ensures that the user has access to the specified repository by creating a GitHub client using the user's token.
// Duplicate agents (by name) across repositories are filtered out, with priority given to agents in the specified repository.
// Loading agents from org and enterprise repos DOES NOT require that the user has access to those repos.
// The opts.IncludeSources field specifies which sources to include (repo, org, enterprise). Defaults to all if nil or empty.
func (s *Service) ListAgents(ctx context.Context, repoOwner, repoName string, opts ListAgentsOpts) ([]sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.ListAgents")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "list_agents",
	})
	defer func() {
		s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", baseTags, time.Since(start))
	}()
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	initialRepo, sourceReposLoaders, err := s.getLazySourceRepoLoaders(ctx, opts.UserID, repoOwner, repoName, opts.IncludeSources)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "get_source_loaders_failed")
		return nil, goerrors.Errorf("failed to get source repositories: %w", err)
	}

	// Add repo for telemetry
	_ = requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      int64(initialRepo.id),
		OwnerID: int64(initialRepo.ownerID),
	})

	agents, err := s.listAgentsFromLoaders(ctx, initialRepo, sourceReposLoaders, opts)
	if err != nil {
		// Don't register a service error if we just didn't find any agents
		if !errors.Is(err, ErrNoAgentsFound) {
			s.recordServiceError(ctx, baseTags, "list_agents_failed")
		}
		return nil, err
	}

	s.obsv.Increment(ctx, "customagent.Service.success", baseTags)
	return agents, nil
}

// ListAgentsByRepoID retrieves the list of custom agent configurations for a given repository by repository ID. It behaves the same as ListAgents otherwise.
func (s *Service) ListAgentsByRepoID(ctx context.Context, repoID uint64, opts ListAgentsOpts) ([]sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.ListAgentsByRepoID")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "list_agents_by_repo_id",
	})
	defer func() {
		s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", baseTags, time.Since(start))
	}()
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	initialRepo, sourceReposLoaders, err := s.getLazySourceRepoLoadersByID(ctx, opts.UserID, repoID, opts.IncludeSources)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "get_source_loaders_failed")
		return nil, goerrors.Errorf("failed to get source repositories: %w", err)
	}

	// Add repo for telemetry
	_ = requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      int64(initialRepo.id),
		OwnerID: int64(initialRepo.ownerID),
	})

	agents, err := s.listAgentsFromLoaders(ctx, initialRepo, sourceReposLoaders, opts)
	if err != nil {
		// Don't register a service error if we just didn't find any agents
		if !errors.Is(err, ErrNoAgentsFound) {
			s.recordServiceError(ctx, baseTags, "list_agents_by_repo_id_failed")
		}
		return nil, err
	}

	s.obsv.Increment(ctx, "customagent.Service.success", baseTags)
	return agents, nil
}

// GetAgentOpts holds options for getting a custom agent.
type GetAgentOpts struct {
	UserID        uint64 // UserID is optional if skip auth check is true. It is only used for authorization and feature flags otherwise.
	SkipAuthCheck bool
}

// GetAgent retrieves the details of custom agent configuration in a given repository.
// The version can be an object ID / SHA, branch name, tag name, or "latest" (empty string).
func (s *Service) GetAgent(ctx context.Context, repoOwner, repoName, agentName, version string, opts GetAgentOpts) (sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.GetAgent")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "get_agent",
	})
	defer func() {
		s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", baseTags, time.Since(start))
	}()
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	repo, err := NewRepository(ctx, s.trp, s.spokes, s.obsv, repoOwner, repoName, Directory)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "new_repository_failed")
		return nil, goerrors.Errorf("failed to initialize agent repository: %w", err)
	}

	// Add repo for telemetry
	_ = requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      int64(repo.id),
		OwnerID: int64(repo.ownerID),
	})

	agent, err := s.getAgentFromRepo(ctx, repo, agentName, version, baseTags, opts)
	if err != nil {
		if errors.Is(err, ErrRequestedAgentNotFound) {
			s.recordServiceWarning(ctx, baseTags, "requested_agent_not_found")
		} else {
			s.recordServiceError(ctx, baseTags, "get_agent_failed")
		}
		return nil, err
	}

	s.obsv.Increment(ctx, "customagent.Service.success", baseTags)
	return agent, nil
}

// GetAgentByRepoID retrieves the details of custom agent configuration in a given repository by repository ID.
func (s *Service) GetAgentByRepoID(ctx context.Context, repoID uint64, agentName, version string, opts GetAgentOpts) (sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.GetAgentByRepoID")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "get_agent_by_repo_id",
	})
	defer func() {
		s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", baseTags, time.Since(start))
	}()
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	repo, err := NewRepositoryByID(ctx, s.trp, s.spokes, s.obsv, repoID, Directory)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "new_repository_by_id_failed")
		return nil, goerrors.Errorf("failed to initialize agent repository: %w", err)
	}

	// Add repo for telemetry
	_ = requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      int64(repo.id),
		OwnerID: int64(repo.ownerID),
	})

	agent, err := s.getAgentFromRepo(ctx, repo, agentName, version, baseTags, opts)
	if err != nil {
		if errors.Is(err, ErrRequestedAgentNotFound) {
			s.recordServiceWarning(ctx, baseTags, "requested_agent_not_found")
		} else {
			s.recordServiceError(ctx, baseTags, "get_agent_by_repo_id_failed")
		}
		return nil, err
	}

	s.obsv.Increment(ctx, "customagent.Service.success", baseTags)
	return agent, nil
}

// getAgentFromRepo contains the shared logic for retrieving an agent from a repository.
func (s *Service) getAgentFromRepo(ctx context.Context, repo *Repository, agentName, version string, baseTags stats.Tags, opts GetAgentOpts) (sweagentd.CustomAgent, error) {
	// Check if we should be returning a privileged agent
	scope := customagent.ScopeRepo
	isOrgRepo := isOrgRepoName(repo.name)
	if !isOrgRepo {
		// Check if there's an enterprise repo if we haven't already determined that this is a privileged agent
		enterpriseRepoID, err := s.getEnterpriseRepoID(ctx, getEnterpriseRepoOpts{RepositoryID: repo.id})
		if err != nil && !errors.Is(err, ErrRepoNotFound) {
			s.recordServiceError(ctx, baseTags, "get_enterprise_repo_failed")
			return nil, goerrors.Errorf("failed to get enterprise source repo: %w", err)
		}

		if enterpriseRepoID == repo.id {
			scope = customagent.ScopeEnterprise
		}
	} else {
		scope = customagent.ScopeOrg
	}
	// Update directory if org repo unless name indicates it is from .github/agents folder
	switch {
	case strings.HasPrefix(agentName, forceDotGitHubAgentsDirPrefix):
		agentName = strings.TrimPrefix(agentName, forceDotGitHubAgentsDirPrefix)
	case scope != customagent.ScopeRepo:
		repo.directory = OrgDirectory
	default:
		// Do nothing - make linting happy
	}

	// GetAgent will still return a config where validation fails if applicable. This allows clients like VS Code
	// to ignore errors and still get the contents and present it to the user for correction or partial execution.
	agent, err := s.fetchAgent(ctx, repo, agentName, version, fetchAgentOpts{
		UserID:               opts.UserID,
		SkipAuthCheck:        opts.SkipAuthCheck,
		ErrorOnInvalidConfig: false,
	})
	if err != nil {
		// Let upstream do any statistics based on the kind of error here
		return nil, goerrors.Errorf("failed to get agent from repo: %w", err)
	}
	agent.metadata.Scope = scope

	// Org/enterprise repos always return privileged agents, and repo-level agents may be privileged
	if scope != customagent.ScopeRepo || s.isPrivilegedRepo(ctx, opts.UserID, repo.ownerID, repo.id) {
		return &PrivilegedAgent{agent}, nil
	}

	return agent, nil
}

// resolveAgentFromLoaders contains the shared logic for resolving an agent from a list of source repository loaders.
func (s *Service) resolveAgentFromLoaders(
	ctx context.Context, userID uint64, agentName, version string, sourceReposLoaders []lazySourceRepoLoader, baseTags stats.Tags, opts ResolveByNameOpts,
) (sweagentd.CustomAgent, error) {
	// TODO (chuxel): Populate "scope" for list - need to have lazySourceRepoLoaders return this
	var agentWithParsingErrors sweagentd.CustomAgent
	for _, lazy := range sourceReposLoaders {
		repo, privileged, err := lazy()
		if err != nil {
			return nil, goerrors.Errorf("failed to get repository: %w", err)
		}
		if repo == nil {
			continue // Repo not found and no error, skip
		}

		agent, err := s.fetchAgent(ctx, repo, agentName, version, fetchAgentOpts{
			UserID:               userID,
			SkipAuthCheck:        opts.SkipAuthCheck,
			ErrorOnInvalidConfig: opts.ErrorOnInvalidConfig,
		})
		if err != nil {
			if errors.Is(err, ErrRepoNotFound) || errors.Is(err, ErrRequestedAgentNotFound) || errors.Is(err, ErrMalformedConfig) || errors.Is(err, ErrAuthorizationFailed) {
				continue // Agent not found, skip to next
			}

			// Let upstream do any statistics based on the kind of error here
			return nil, goerrors.Errorf("failed to get agent from repo: %w", err) // Will already have repo owner and name in underlying error
		}
		// Keep a copy of an invalid agent if there's a parsing error if opts.ErrorOnInvalidConfig is false for later use.
		if agent.ConfigError() != "" {
			agentWithParsingErrors = agent
			continue // Keep looking for a match without errors
		}

		if privileged {
			return &PrivilegedAgent{agent}, nil // happy path, found a matching org/enterprise agent
		}

		return agent, nil // happy path, found a matching agent
	}

	// If we got a parsing error along the way, either return the object or the error based on the flag
	if agentWithParsingErrors != nil {
		s.recordServiceWarning(ctx, baseTags, "parsing_error")
		if opts.ErrorOnInvalidConfig {
			return nil, goerrors.Errorf("failed to get agent: %s", agentWithParsingErrors.ConfigError())
		}
		return agentWithParsingErrors, nil
	}

	return nil, ErrRequestedAgentNotFound
}

func (s *Service) listAgentsFromLoaders(ctx context.Context, initialRepo *Repository, sourceReposLoaders []lazySourceRepoLoader, opts ListAgentsOpts) ([]sweagentd.CustomAgent, error) {
	var (
		agents              = make([]sweagentd.CustomAgent, 0)
		agentIndex          = make(map[string]struct{})
		prefixApplied       bool
		loadedFromDirectory bool
	)

	for _, lazy := range sourceReposLoaders {
		repoAgents, repo, err := s.listRepoAgents(ctx, lazy, opts)
		if err != nil {
			if errors.Is(err, ErrRepoNotFound) || errors.Is(err, ErrNoAgentsFound) {
				continue // Permissive mode, skip if repo not found or no agents found
			}
			return nil, goerrors.Errorf("failed to list agents: %w", err) // Will already have repo owner and name in underlying error
		}

		// If we're listing agents directly for an org/enterprise agent repo, in the worst case, the initial repo, org repo,
		// and enterprise repo could all be the same repository. We then want to initially load content from the .github/agents
		// folder and then the agents folder. However, an agent with the same name can exist in both folders. But that means
		// the GetAgents method (and endpoint) does not have the needed context to understand where the agent came from in this
		// exception case (only) since it expects the repo that contains the agent rather than the initial repo to improve perf.
		// To disambiguate, we'll prefix the agent names from the .github/agents folder ".gh:" so GetAgent can handle it properly.
		// We only prefix when we've previously loaded from Directory and are now loading from OrgDirectory for the same repo.
		if !prefixApplied && repo.id == initialRepo.id && repo.directory == OrgDirectory && loadedFromDirectory {
			for _, a := range agents {
				if a.RepoID() == int64(repo.id) && !strings.HasPrefix(a.Name(), forceDotGitHubAgentsDirPrefix) {
					prefixedName := fmt.Sprintf("%s%s", forceDotGitHubAgentsDirPrefix, a.Name())
					agent, ok := a.(*PrivilegedAgent)
					if !ok {
						return nil, goerrors.New("unexpected type when prefixing agent name")
					}
					agent.metadata.Name = prefixedName
				}
			}
			prefixApplied = true
		}

		// Track if we've loaded from Directory for the initial repo
		if repo.id == initialRepo.id && repo.directory == Directory {
			loadedFromDirectory = true
		}

		if opts.DedupeNames {
			agents = append(agents, indexedAgents(agentIndex, repoAgents)...)
		} else {
			agents = append(agents, repoAgents...)
		}
	}

	if len(agents) == 0 {
		return nil, ErrNoAgentsFound
	}

	return agents, nil
}

// lazySourceRepoLoader defines a function that can be called for the lazy returns of a Repository, whether the repository is privileged, and an error if any.
type lazySourceRepoLoader func() (*Repository, bool, error)

// The order of this list establishes precedence for name conflicts across repos (first repo wins).
func (s *Service) getLazySourceRepoLoadersByID(ctx context.Context, userID, repoID uint64, includeSources []string) (*Repository, []lazySourceRepoLoader, error) {
	// Default to all sources if not specified
	if len(includeSources) == 0 {
		includeSources = []string{SourceTypeRepo, SourceTypeOrg, SourceTypeEnterprise}
	}

	// We always need to get the initial repo to determine owner and repo names for org repo lookup
	// We should also always check Directory even in .github / .github-private repos to enable testing
	initialRepo, err := NewRepositoryByID(ctx, s.trp, s.spokes, s.obsv, repoID, Directory)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get repo with ID %d: %w", repoID, err)
	}

	loaders, err := s.getSourceLoadersForOwner(ctx, initialRepo.ownerID, initialRepo.owner, includeSources)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get owner source loaders: %w", err)
	}
	if slices.Contains(includeSources, SourceTypeRepo) {
		// Prepend the initial repo loader to give it priority over org/enterprise
		initialRepoLoader := func() (*Repository, bool, error) {
			return initialRepo, isOrgRepoName(initialRepo.name) || s.isPrivilegedRepo(ctx, userID, initialRepo.ownerID, initialRepo.id), nil
		}
		loaders = append([]lazySourceRepoLoader{initialRepoLoader}, loaders...)
	}

	return initialRepo, loaders, nil
}

// The order of this list establishes precedence for name conflicts across repos (first repo wins).
func (s *Service) getLazySourceRepoLoaders(ctx context.Context, userID uint64, repoOwner, repoName string, includeSources []string) (*Repository, []lazySourceRepoLoader, error) {
	// Default to all sources if not specified
	if len(includeSources) == 0 {
		includeSources = []string{SourceTypeRepo, SourceTypeOrg, SourceTypeEnterprise}
	}

	// We always need to get the initial repo to determine owner ID and repo ID for enterprise repo lookup
	// We should also always check Directory even in .github / .github-private repos to enable testing
	initialRepo, err := NewRepository(ctx, s.trp, s.spokes, s.obsv, repoOwner, repoName, Directory)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get repo %s/%s: %w", repoOwner, repoName, err)
	}

	loaders, err := s.getSourceLoadersForOwner(ctx, initialRepo.ownerID, initialRepo.owner, includeSources)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get source loaders: %w", err)
	}
	if slices.Contains(includeSources, SourceTypeRepo) {
		// Prepend the initial repo loader to give it priority over org/enterprise
		initialRepoLoader := func() (*Repository, bool, error) {
			return initialRepo, isOrgRepoName(initialRepo.name) || s.isPrivilegedRepo(ctx, userID, initialRepo.ownerID, initialRepo.id), nil
		}
		loaders = append([]lazySourceRepoLoader{initialRepoLoader}, loaders...)
	}

	return initialRepo, loaders, nil
}

func (s *Service) getSourceLoadersForOwner(ctx context.Context, ownerID uint64, ownerName string, includeSources []string) ([]lazySourceRepoLoader, error) {
	loaders := make([]lazySourceRepoLoader, 0, 3)
	if slices.Contains(includeSources, SourceTypeOrg) {
		loaders = append(loaders, s.getOrgLoader(ctx, ownerName, orgRepoName), s.getOrgLoader(ctx, ownerName, orgRepoName+"-private"))
	}
	if slices.Contains(includeSources, SourceTypeEnterprise) {
		loaders = append(loaders, s.getEnterpriseLoader(ctx, ownerID))
	}

	return loaders, nil
}

func (s *Service) getOrgLoader(ctx context.Context, repoOwner, repoName string) lazySourceRepoLoader {
	return func() (*Repository, bool, error) {
		repo, err := NewRepository(ctx, s.trp, s.spokes, s.obsv, repoOwner, repoName, OrgDirectory)
		if err != nil {
			if errors.Is(err, ErrRepoNotFound) {
				return nil, false, nil // No org repo, skip
			}
			return nil, false, goerrors.Errorf("failed to get org repo %s/%s: %w", repoOwner, repoName, err)
		}

		return repo, true, nil
	}
}

func (s *Service) getEnterpriseLoader(ctx context.Context, ownerID uint64) lazySourceRepoLoader {
	return func() (*Repository, bool, error) {
		enterpriseRepo, err := s.getEnterpriseRepo(ctx, getEnterpriseRepoOpts{OwnerID: ownerID})
		if err != nil {
			if errors.Is(err, ErrRepoNotFound) {
				return nil, false, nil // No enterprise repo, skip
			}
			return nil, false, goerrors.Errorf("failed to get enterprise source repo: %w", err)
		}
		return enterpriseRepo, true, nil
	}
}

type getEnterpriseRepoOpts struct {
	RepositoryID uint64
	OwnerID      uint64
	OwnerName    string
}

// getEnterpriseRepoID retrieves the enterprise-level repository ID associated with the given initial repository ID.
func (s *Service) getEnterpriseRepoID(ctx context.Context, opts getEnterpriseRepoOpts) (uint64, error) {
	var req *sweagentdv1.EnterpriseAgentsRequest

	switch {
	case opts.RepositoryID != 0:
		req = &sweagentdv1.EnterpriseAgentsRequest{
			FindAgentsBy: &sweagentdv1.EnterpriseAgentsRequest_RepositoryId{
				RepositoryId: opts.RepositoryID,
			},
		}
	case opts.OwnerID != 0:
		req = &sweagentdv1.EnterpriseAgentsRequest{
			FindAgentsBy: &sweagentdv1.EnterpriseAgentsRequest_OwnerId{
				OwnerId: opts.OwnerID,
			},
		}
	case opts.OwnerName != "":
		req = &sweagentdv1.EnterpriseAgentsRequest{
			FindAgentsBy: &sweagentdv1.EnterpriseAgentsRequest_OwnerName{
				OwnerName: opts.OwnerName,
			},
		}
	default:
		return 0, goerrors.New("getEnterpriseRepoID: missing repository and owner identifiers")
	}
	enterpriseRepo, err := s.ghtwirp.SweagentdAPI().EnterpriseAgents(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) {
			if twirpErr.Code() == twirp.NotFound {
				return 0, ErrRepoNotFound
			}
		}

		return 0, goerrors.Errorf("failed to get enterprise agents source repo id: %w", err)
	}
	if enterpriseRepo.GetRepositoryId() == 0 {
		return 0, ErrRepoNotFound
	}

	return enterpriseRepo.GetRepositoryId(), nil
}

// getEnterpriseRepo retrieves the enterprise-level repository associated with the given initial repository ID.
func (s *Service) getEnterpriseRepo(ctx context.Context, opts getEnterpriseRepoOpts) (*Repository, error) {
	enterpriseRepoID, err := s.getEnterpriseRepoID(ctx, opts)
	if err != nil {
		return nil, err
	}

	return NewRepositoryByID(ctx, s.trp, s.spokes, s.obsv, enterpriseRepoID, OrgDirectory)
}

// fetchAgentOpts holds internal options for fetching an agent.
type fetchAgentOpts struct {
	UserID               uint64
	SkipAuthCheck        bool
	ErrorOnInvalidConfig bool
}

// fetchAgent is an internal method used by getAgentFromRepo and ResolveByNameAndRepoID to retrieve a specific agent
// from a repository. If skipAuthCheck is false, it verifies the user has access via a twirp endpoint call before attempting to fetch the agent.
// If a version is specified, it resolves it to an object ID for a branch/tag before getting the agent.
func (s *Service) fetchAgent(ctx context.Context, repo *Repository, agentName, version string, opts fetchAgentOpts) (*Agent, error) {
	if !opts.SkipAuthCheck {
		// Validate that UserID is provided when authorization check is required
		if opts.UserID == 0 {
			return nil, goerrors.Errorf("UserID must be non-zero when SkipAuthCheck is false")
		}

		req := &sweagentdv1.AuthorizeCustomAgentRepoForUserRequest{
			UserId:       opts.UserID,
			RepositoryId: repo.id,
		}
		resp, err := s.ghtwirp.SweagentdAPI().AuthorizeCustomAgentRepoForUser(ctx, req)
		if err != nil {
			s.recordServiceWarning(ctx, s.obsv.TelemetryTags(ctx), "check_authorization_failed")
			return nil, goerrors.Errorf("failed to authorize user for custom agents in %s/%s: %w: %w", repo.owner, repo.name, ErrAuthorizationFailed, err)
		}

		if !resp.GetCanAccess() {
			s.obsv.Logger.WithContext(ctx).Info("user does not have access to get custom agents for repo")
			return nil, ErrRequestedAgentNotFound
		}
	}

	var err error
	// Resolve version if specified - could be a tag, branch, or object ID
	if version != "" {
		if version == "latest" {
			version = "" // Treat "latest" as empty for GetObjectID
		} else {
			version, err = s.spokes.GetObjectIDForRef(ctx, repo.id, version)
			if err != nil {
				s.recordServiceWarning(ctx, s.obsv.TelemetryTags(ctx), "resolve_agent_version_failed")
				return nil, goerrors.Errorf("failed to resolve agent version: %w", err)
			}
		}
	}

	m := Metadata{
		Name:        agentName,
		RepoOwnerID: int64(repo.ownerID),
		RepoOwner:   repo.owner,
		RepoID:      int64(repo.id),
		RepoName:    repo.name,
		Version:     version,
	}

	// Partial agent contents may be returned on parsing errors, so directly return the output of FromRepo
	agent, err := FromRepo(ctx, m, repo, opts.ErrorOnInvalidConfig)
	if err != nil {
		return nil, goerrors.Errorf("failed to get agent from repo %s/%s: %w", repo.owner, repo.name, err)
	}
	return agent, nil
}

// listRepoAgents lists agents from a specific repository after verifying that the user has access to that repository.
// It gets the repository and verifies the user has access via a twirp endpoint call before attempting to fetch the agent.
func (s *Service) listRepoAgents(ctx context.Context, lazy lazySourceRepoLoader, opts ListAgentsOpts) ([]sweagentd.CustomAgent, *Repository, error) {
	// TODO (chuxel): Populate "scope" for list - need to have lazySourceRepoLoaders return this
	repo, privileged, err := lazy()
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to initialize repository: %w", err)
	}
	if repo == nil {
		return nil, nil, ErrRepoNotFound
	}

	if !opts.SkipAuthCheck {
		// Validate that UserID is provided when authorization check is required
		if opts.UserID == 0 {
			return nil, nil, goerrors.Errorf("UserID must be non-zero when SkipAuthCheck is false")
		}

		req := &sweagentdv1.AuthorizeCustomAgentRepoForUserRequest{
			UserId:       opts.UserID,
			RepositoryId: repo.id,
		}
		resp, err := s.ghtwirp.SweagentdAPI().AuthorizeCustomAgentRepoForUser(ctx, req)
		if err != nil {
			s.recordServiceWarning(ctx, s.obsv.TelemetryTags(ctx), "check_authorization_failed")
			return nil, nil, goerrors.Errorf("failed to authorize user for custom agents in %s/%s: %w: %w", repo.owner, repo.name, ErrAuthorizationFailed, err)
		}

		if !resp.GetCanAccess() {
			s.obsv.Logger.WithContext(ctx).Info("user does not have access to list custom agents for repo")
			return nil, nil, ErrNoAgentsFound
		}
	}

	agents, err := repo.agents(ctx, opts.ExcludeInvalidConfig)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to list agents from repo %s/%s: %w", repo.owner, repo.name, err)
	}

	// Convert []*Agent to []sweagentd.CustomAgent, possibly add and wrap in PrivilegedAgent if needed
	customAgents := []sweagentd.CustomAgent{}
	for _, a := range agents {
		// Filter out agents that do not match the target
		ok, msg := checkTarget(a.Target(), opts.Target)
		if !ok {
			if opts.ExcludeInvalidConfig {
				continue
			}
			a.metadata.ConfigError = msg
		}

		// Convert to privileged agent if applicable
		if privileged {
			customAgents = append(customAgents, &PrivilegedAgent{a})
			continue
		}

		customAgents = append(customAgents, a)
	}

	return customAgents, repo, nil
}

func (s *Service) recordServiceError(ctx context.Context, baseTags stats.Tags, errorReason string) {
	errorTags := baseTags.Merge(stats.Tags{
		"success":      "false",
		"error_reason": errorReason,
	})
	s.obsv.Increment(ctx, "customagent.Service.errors", errorTags)
}

func (s *Service) recordServiceWarning(ctx context.Context, baseTags stats.Tags, errorReason string) {
	errorTags := baseTags.Merge(stats.Tags{
		"success":      "false",
		"error_reason": errorReason,
	})
	s.obsv.Increment(ctx, "customagent.Service.warnings", errorTags)
}

func isOrgRepoName(name string) bool {
	return name == orgRepoName || name == orgRepoName+"-private"
}

// isPrivilegedRepo checks if the given (non-enterprise/org) repository is considered privileged for custom agents.
// Right now this is feature flag based, but we expect this to become settings/policy based in time.
func (s *Service) isPrivilegedRepo(ctx context.Context, userID, ownerID, id uint64) bool {
	return s.ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentPrivilegedRepo, &ffActors{
		userID:  int64(userID),
		ownerID: int64(ownerID),
		repoID:  int64(id),
	})
}

// checkTarget returns true if the target is empty, the value we are checking is
// empty (which means it works on all targets), or value==target. Otherwise,
// it returns false and an appropriate message indicating why the target check failed.
func checkTarget(value, target string) (bool, string) {
	if target == TargetEmpty || value == TargetEmpty || value == target {
		return true, ""
	}
	switch value {
	case TargetVSCode:
		return false, TargetIsVSCodeMessage
	case TargetGitHubCopilot:
		return false, TargetIsGitHubMessage
	default:
		return false, TargetIsUnknownMessage
	}
}

// ParseCustomAgentName parses a custom agent name that may include a version specification.
// The format is "agent-name@version" where version is a git SHA, tag, or branch reference.
// If no @ separator is found, the entire string is treated as the name and version is empty.
// Returns the agent name and version separately.
func ParseCustomAgentName(customAgent string) (name, version string) {
	if customAgent == "" {
		return "", ""
	}

	// Look for @ separator to split name and version
	parts := strings.SplitN(customAgent, "@", 2)
	if len(parts) == 2 {
		return parts[0], parts[1]
	}

	// No @ found, entire string is the name
	return customAgent, ""
}
