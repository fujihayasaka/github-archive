package customagent

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
)

// ErrRepoNotFound is returned when a repository is not found.
var ErrRepoNotFound = errors.New("repository not found")

const orgRepoName = ".github"

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
		return false, fmt.Errorf("failed to get repo: %w", err)
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

	return s.ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentUseCustomAgents, &actors) &&
		!s.ff.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentsDisallow, &actors)
}

// ResolveByName resolves a custom agent by name and returns it as a sweagentd.CustomAgent interface.
// If the agent is not found at the repository level, it checks the org/enterprise level (".github" repository).
// If found at the org/enterprise level, it wraps the agent in a PrivilegedAgent (pointer to struct).
// If not found at any level, it returns an error.
// But, if errorOnInvalidConfig is false, it will return an agent with parsing errors instead of an error.
func (s *Service) ResolveByName(
	ctx context.Context, userID uint64, repoOwner, repoName, agentName string, version string, errorOnInvalidConfig bool,
) (sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.ResolveByName")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "resolve_by_name",
	})
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	sourceReposLoaders, err := s.getLazySourceRepoLoaders(ctx, userID, repoOwner, repoName)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "list_agents_failed")
		return nil, fmt.Errorf("failed to get source repositories: %w", err)
	}

	var currAgentTags stats.Tags
	var agentWithParsingErrors sweagentd.CustomAgent
	for _, lazy := range sourceReposLoaders {
		// The two other OR conditions are to account for the case where the user's current context (i.e. `repoName`) is actually an org repo.
		repo, privileged, err := lazy()
		if err != nil {
			return nil, fmt.Errorf("failed to get repository: %w", err)
		}
		if repo == nil {
			continue // Repo not found and no error, skip
		}
		currAgentTags = baseTags.Merge(stats.Tags{
			"is_privileged": strconv.FormatBool(privileged),
		})

		// Intentionally return an invalid agent if there's a parsing error so we can deal with it upstream
		agent, err := s.getAgent(ctx, userID, repo, agentName, version, false)
		if err != nil {
			if errors.Is(err, ErrRepoNotFound) || errors.Is(err, ErrRequestedAgentNotFound) || errors.Is(err, ErrMalformedConfig) {
				continue // Agent not found, skip to next
			}

			s.recordServiceError(ctx, currAgentTags, "get_agent_failed")
			return nil, fmt.Errorf("failed to get agent from repo: %w", err) // Will already have repo owner and name in underlying error
		}
		if agent.ConfigError() != "" {
			agentWithParsingErrors = agent
			continue // Keep looking for a match without errors
		}

		s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", currAgentTags, time.Since(start))
		s.obsv.Increment(ctx, "customagent.Service.success", currAgentTags)

		if privileged {
			return &PrivilegedAgent{agent}, nil // happy path, found a matching org/enterprise agent
		}

		return agent, nil // happy path, found a matching agent
	}

	// If we got a parsing error along the way, either return the object or the error based on the flag
	if agentWithParsingErrors != nil {
		s.obsv.Increment(ctx, "customagent.Service.parsing-error", baseTags)
		if errorOnInvalidConfig {
			return nil, fmt.Errorf("failed to get agent: %s", agentWithParsingErrors.ConfigError())
		}
		return agentWithParsingErrors, nil
	}

	s.recordServiceError(ctx, baseTags, "agent_not_found")
	return nil, ErrRequestedAgentNotFound
}

// indexedAgents filters out duplicate agents based on their names using the provided index map.
// It updates the index map with the names of the agents it includes in the returned slice.
func indexedAgents(index map[string]struct{}, agents []sweagentd.CustomAgent) []sweagentd.CustomAgent {
	var unique []sweagentd.CustomAgent
	for _, a := range agents {
		if _, exists := index[a.Name()]; exists {
			continue
		}

		index[a.Name()] = struct{}{}
		unique = append(unique, a)
	}

	return unique
}

// ListAgents retrieves the list of custom agent configurations for a given repository.
// It checks the specified repository first, followed by the ".github" and ".github-private" repositories at the organization level.
// It ensures that the user has access to the specified repository by creating a GitHub client using the user's token.
// Duplicate agents (by name) across repositories are filtered out, with priority given to agents in the specified repository.
// Loading agents from org and enterprise repos DOES NOT require that the user has access to those repos.
func (s *Service) ListAgents(ctx context.Context, userID uint64, repoOwner, repoName string, excludeInvalidConfig bool) ([]sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.ListAgents")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "list_agents",
	})
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	var (
		agents     = make([]sweagentd.CustomAgent, 0)
		agentIndex = make(map[string]struct{})
	)

	sourceReposLoaders, err := s.getLazySourceRepoLoaders(ctx, userID, repoOwner, repoName)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "list_agents_failed")
		return nil, fmt.Errorf("failed to get source repositories: %w", err)
	}
	for _, lazy := range sourceReposLoaders {
		repoAgents, err := s.listRepoAgents(ctx, userID, lazy, excludeInvalidConfig)
		if err != nil {
			if errors.Is(err, ErrRepoNotFound) || errors.Is(err, ErrNoAgentsFound) {
				continue // Permissive mode, skip if repo not found or no agents found
			}
			s.recordServiceError(ctx, baseTags, "list_agents_failed")
			return nil, fmt.Errorf("failed to list agents: %w", err) // Will already have repo owner and name in underlying error
		}

		agents = append(agents, indexedAgents(agentIndex, repoAgents)...)
	}

	s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", baseTags, time.Since(start))
	s.obsv.Increment(ctx, "customagent.Service.success", baseTags)

	if len(agents) == 0 {
		return nil, ErrNoAgentsFound
	}

	return agents, nil
}

// GetAgent retrieves the details of custom agent configuration in a given repository.
func (s *Service) GetAgent(ctx context.Context, userID uint64, repoOwner, repoName, agentName, version string) (sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "customagent.Service.GetAgent")
	defer span.End()

	start := time.Now()
	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "get_agent",
	})
	s.obsv.Increment(ctx, "customagent.Service.requests", baseTags)

	repo, err := NewRepository(ctx, s.trp, s.spokes, s.obsv, repoOwner, repoName, Directory)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "get_agent_failed")
		return nil, fmt.Errorf("failed to initialize agent repository: %w", err)
	}

	// Check if we should be returning a privileged agent
	isPrivileged := isOrgRepoName(repoName)
	if !isPrivileged {
		// Check if there's an enterprise repo if we haven't already determined that this is a privileged agent
		enterpriseRepoID, err := s.getEnterpriseRepoID(ctx, userID, repo.id)
		if err != nil && !errors.Is(err, ErrRepoNotFound) {
			s.recordServiceError(ctx, baseTags, "get_enterprise_repo_failed")
			return nil, fmt.Errorf("failed to get enterprise source repo: %w", err)
		}

		isPrivileged = enterpriseRepoID == repo.id
	}
	if isPrivileged {
		repo.directory = OrgDirectory
	}

	// GetAgent will still return a config where validation fails if applicable. This allows clients like VS Code
	// to ignore errors and still get the contents and present it to the user for correction or partial execution.
	agent, err := s.getAgent(ctx, userID, repo, agentName, version, false)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "get_agent_failed")
		return nil, fmt.Errorf("failed to get agent from repo: %w", err)
	}

	s.obsv.DistributionMs(ctx, "customagent.Service.request_duration", baseTags, time.Since(start))
	s.obsv.Increment(ctx, "customagent.Service.success", baseTags)

	if isPrivileged {
		return &PrivilegedAgent{agent}, nil
	}

	return agent, nil
}

// lazySourceRepoLoader defines a function that can be called for the lazy returns of a Repository, whether the repository is privileged, and an error if any.
type lazySourceRepoLoader func() (*Repository, bool, error)

// The order of this list establishes precedence for name conflicts across repos (first repo wins).
func (s *Service) getLazySourceRepoLoaders(ctx context.Context, userID uint64, repoOwner, repoName string) ([]lazySourceRepoLoader, error) {
	dir := Directory
	if isOrgRepoName(repoName) {
		dir = OrgDirectory
	}
	initialRepo, err := NewRepository(ctx, s.trp, s.spokes, s.obsv, repoOwner, repoName, dir)
	if err != nil {
		return nil, fmt.Errorf("failed to get repo %s/%s: %w", repoOwner, repoName, err)
	}
	return []lazySourceRepoLoader{
		// Initial repo always first
		func() (*Repository, bool, error) {
			return initialRepo, isOrgRepoName(initialRepo.name), nil
		},
		// .github org repo
		func() (*Repository, bool, error) {
			return s.getOrgRepository(ctx, initialRepo.owner, orgRepoName)
		},
		// .github-private org repo
		func() (*Repository, bool, error) {
			return s.getOrgRepository(ctx, initialRepo.owner, orgRepoName+"-private")
		},
		// Enterprise repo
		func() (*Repository, bool, error) {
			enterpriseRepo, err := s.getEnterpriseRepo(ctx, userID, initialRepo.id)
			if err != nil {
				if errors.Is(err, ErrRepoNotFound) {
					return nil, false, nil // No enterprise repo, skip
				}
				return nil, false, fmt.Errorf("failed to get enterprise source repo: %w", err)
			}
			return enterpriseRepo, true, nil
		},
	}, nil
}

func (s *Service) getOrgRepository(ctx context.Context, repoOwner, repoName string) (*Repository, bool, error) {
	repo, err := NewRepository(ctx, s.trp, s.spokes, s.obsv, repoOwner, repoName, OrgDirectory)
	if err != nil {
		if errors.Is(err, ErrRepoNotFound) {
			return nil, false, nil // No org repo, skip
		}
		return nil, false, fmt.Errorf("failed to get org repo %s/%s: %w", repoOwner, repoName, err)
	}

	return repo, true, nil
}

// getEnterpriseRepoID retrieves the enterprise-level repository ID associated with the given initial repository ID.
func (s *Service) getEnterpriseRepoID(ctx context.Context, userID, initialRepoID uint64) (uint64, error) {
	req := &sweagentdv1.EnterpriseAgentsRequest{
		UserId:       userID,
		RepositoryId: initialRepoID,
	}
	enterpriseRepo, err := s.ghtwirp.SweagentdAPI().EnterpriseAgents(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) {
			if twirpErr.Code() == twirp.NotFound {
				return 0, ErrRepoNotFound
			}
		}

		return 0, fmt.Errorf("failed to get enterprise agents source repo id: %w", err)
	}
	if enterpriseRepo.GetRepositoryId() == 0 {
		return 0, ErrRepoNotFound
	}

	return enterpriseRepo.GetRepositoryId(), nil
}

// getEnterpriseRepo retrieves the enterprise-level repository associated with the given initial repository ID.
func (s *Service) getEnterpriseRepo(ctx context.Context, userID, initialRepoID uint64) (*Repository, error) {
	enterpriseRepoID, err := s.getEnterpriseRepoID(ctx, userID, initialRepoID)
	if err != nil {
		return nil, err
	}

	enterpriseRepoDetails, err := s.trp.getRepositoryByID(ctx, int64(enterpriseRepoID))
	if err != nil {
		return nil, fmt.Errorf("failed to get enterprise repo by id: %w", err)
	}

	return enterpriseRepoDetails.ToRepo(s.trp, s.spokes, s.obsv, OrgDirectory), nil
}

// getAgent is an internal method used by GetAgent and getAgentForSourceRepo to retrieve a specific agent from a repository.
// It gets the repository and verifies the user has access via a twirp endpoint call before attempting to fetch the agent.
func (s *Service) getAgent(ctx context.Context, userID uint64, repo *Repository, agentName, version string, errorOnInvalidConfig bool) (*Agent, error) {
	req := &sweagentdv1.AuthorizeCustomAgentRepoForUserRequest{
		UserId:       userID,
		RepositoryId: repo.id,
	}
	resp, err := s.ghtwirp.SweagentdAPI().AuthorizeCustomAgentRepoForUser(ctx, req)
	if err != nil {
		s.recordServiceError(ctx, s.obsv.TelemetryTags(ctx), "check_authorization_failed")
		return nil, fmt.Errorf("failed to authorize user for custom agents: %w", err)
	}

	if !resp.GetCanAccess() {
		s.obsv.Logger.WithContext(ctx).Info("user does not have access to get custom agents for repo")
		return nil, ErrRequestedAgentNotFound
	}

	m := Metadata{
		Name:        agentName,
		RepoOwnerID: int64(repo.ownerID),
		RepoOwner:   repo.owner,
		RepoID:      int64(repo.id),
		RepoName:    repo.name,
		Version:     version,
	}
	// If repo is privileged, check the privileged directory first

	// Partial agent contents may be returned on parsing errors, so directly return the output of FromRepo
	agent, err := FromRepo(ctx, m, repo, errorOnInvalidConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to get agent from repo %s/%s: %w", repo.owner, repo.name, err)
	}
	return agent, nil
}

// listRepoAgents lists agents from a specific repository after verifying that the user has access to that repository.
// It gets the repository and verifies the user has access via a twirp endpoint call before attempting to fetch the agent.
func (s *Service) listRepoAgents(ctx context.Context, userID uint64, lazy lazySourceRepoLoader, excludeInvalidConfig bool) ([]sweagentd.CustomAgent, error) {
	repo, privileged, err := lazy()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize repository: %w", err)
	}
	if repo == nil {
		return nil, ErrRepoNotFound
	}

	req := &sweagentdv1.AuthorizeCustomAgentRepoForUserRequest{
		UserId:       userID,
		RepositoryId: repo.id,
	}
	resp, err := s.ghtwirp.SweagentdAPI().AuthorizeCustomAgentRepoForUser(ctx, req)
	if err != nil {
		s.recordServiceError(ctx, s.obsv.TelemetryTags(ctx), "check_authorization_failed")
		return nil, fmt.Errorf("failed to authorize user for custom agents in %s/%s: %w", repo.owner, repo.name, err)
	}

	if !resp.GetCanAccess() {
		s.obsv.Logger.WithContext(ctx).Info("user does not have access to list custom agents for repo")
		return nil, ErrNoAgentsFound
	}

	agents, err := repo.agents(ctx, excludeInvalidConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to list agents from repo %s/%s: %w", repo.owner, repo.name, err)
	}

	// Convert []*Agent to []sweagentd.CustomAgent and wrap in PrivilegedAgent if needed
	customAgents := make([]sweagentd.CustomAgent, len(agents))
	for i, a := range agents {
		if privileged {
			customAgents[i] = &PrivilegedAgent{a}
			continue
		}

		customAgents[i] = a
	}

	return customAgents, nil
}

type twirpRepoProvider struct {
	ghtwirp githubtwirp.ClientInterface
}

func newTwirpRepoProvider(ghtwirp githubtwirp.ClientInterface) *twirpRepoProvider {
	return &twirpRepoProvider{ghtwirp}
}

type twirpRepo struct {
	id      int64
	ownerID int64
	owner   string
	name    string
}

func newTwirpRepo(id, ownerID int64, owner, name string) *twirpRepo {
	return &twirpRepo{id: id, ownerID: ownerID, owner: owner, name: name}
}

func (r *twirpRepo) GetID() int64 {
	return r.id
}

func (r *twirpRepo) GetOwnerID() int64 {
	return r.ownerID
}

// ToRepo is a utility to take an existing twirpRepo and convert it to a Repository object.
func (r *twirpRepo) ToRepo(rp *twirpRepoProvider, spokes sweagentd.Spokes, obsv observability.Exporters, directory string) *Repository {
	return &Repository{
		id:        uint64(r.id),
		ownerID:   uint64(r.ownerID),
		owner:     r.owner,
		name:      r.name,
		rp:        rp,
		spokes:    spokes,
		obsv:      obsv,
		directory: directory,
	}
}

func (r *twirpRepoProvider) getRepository(ctx context.Context, owner, repo string) (repo, error) {
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{fmt.Sprintf("%s/%s", owner, repo)},
	}
	resp, err := r.ghtwirp.RepositoriesAPI().FindRepositoriesByName(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if ok := errors.As(err, &twirpErr); ok && twirpErr.Code() == twirp.NotFound {
			return nil, ErrRepoNotFound
		}
		return nil, err
	}

	repos := resp.GetRepositories()
	if len(repos) == 0 {
		return nil, ErrRepoNotFound
	}
	tr := repos[0]

	return newTwirpRepo(tr.GetId(), tr.GetOwnerId(), tr.GetOwnerLogin(), tr.GetName()), nil
}

func (r *twirpRepoProvider) getRepositoryByID(ctx context.Context, id int64) (*twirpRepo, error) {
	tr, err := r.ghtwirp.GetRepoById(ctx, id)
	if err != nil {
		return nil, err
	}
	return newTwirpRepo(tr.GetId(), tr.GetOwnerId(), tr.GetOwnerLogin(), tr.GetName()), nil
}

func (s *Service) recordServiceError(ctx context.Context, baseTags stats.Tags, errorReason string) {
	errorTags := baseTags.Merge(stats.Tags{
		"success":      "false",
		"error_reason": errorReason,
	})
	s.obsv.Increment(ctx, "customagent.Service.errors", errorTags)
}

func isOrgRepoName(name string) bool {
	return name == orgRepoName || name == orgRepoName+"-private"
}
