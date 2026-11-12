package skills

import (
	"context"
	"errors"
	"slices"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/gitrepo"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
)

var (
	// ErrRepoNotFound is returned when a repository is not found.
	ErrRepoNotFound = gitrepo.ErrRepoNotFound

	// ErrAuthorizationFailed is returned when authorization check fails.
	ErrAuthorizationFailed = goerrors.New("authorization check failed")
)

const (
	// SourceTypeRepo indicates skills from the repository itself.
	SourceTypeRepo = "repo"
	// SourceTypeOrg indicates skills from organization repositories (.github, .github-private).
	SourceTypeOrg = "org"
	// SourceTypeEnterprise indicates skills from the enterprise repository.
	SourceTypeEnterprise = "enterprise"

	// orgRepoName is the name of the organization-level repository that may contain shared skills.
	orgRepoName = ".github"
)

// ListSkillsOpts contains options for listing skills.
type ListSkillsOpts struct {
	UserID          uint64   // UserID is required when SkipAccessCheck is false. Used for org/enterprise access verification.
	SkipAccessCheck bool     // Skip access check for trusted contexts (e.g., job execution where access already verified).
	DedupeNames     bool     // Dedupe skills by name, closest scope wins (repo > org > enterprise).
	IncludeSources  []string // Level filter: repo, org, enterprise. Defaults to all if empty.
}

// GetSkillOpts contains options for getting a single skill.
type GetSkillOpts struct {
	UserID          uint64 // UserID is required when SkipAccessCheck is false. Used for org/enterprise access verification.
	SkipAccessCheck bool   // Skip access check for trusted contexts (e.g., job execution where access already verified).
}

// Service provides operations for listing and fetching skills.
type Service struct {
	obsv    observability.Exporters
	spokes  sweagentd.Spokes
	rp      gitrepo.RepoProvider
	ghtwirp githubtwirp.ClientInterface
}

// NewService creates a new skills service.
func NewService(obsv observability.Exporters, spokes sweagentd.Spokes, ghtwirp githubtwirp.ClientInterface) *Service {
	return &Service{
		obsv:    obsv,
		spokes:  spokes,
		rp:      gitrepo.NewTwirpRepoProvider(ghtwirp),
		ghtwirp: ghtwirp,
	}
}

// lazySourceRepoLoader defines a function that lazily loads a Repository.
// Returns the repository, whether it's a privileged repo (org/enterprise), and any error.
type lazySourceRepoLoader func() (*Repository, bool, error)

// ListSkills lists all skills available for a repository.
// It checks the specified repository first, followed by org-level repos (.github, .github-private),
// and finally enterprise-level repos. When DedupeNames is true, skills from closer scopes
// take precedence (repo > org > enterprise).
func (s *Service) ListSkills(ctx context.Context, repoOwner, repoName string, opts ListSkillsOpts) ([]*Skill, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "skills.Service.ListSkills")
	defer span.End()

	baseTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"operation": "list_skills",
	})
	s.obsv.Increment(ctx, "skills.Service.requests", baseTags)

	loaders, err := s.getLazySourceRepoLoaders(ctx, repoOwner, repoName, opts.IncludeSources)
	if err != nil {
		s.recordServiceError(ctx, baseTags, "get_source_loaders_failed")
		return nil, goerrors.Errorf("failed to get source repositories: %w", err)
	}

	skills, err := s.listSkillsFromLoaders(ctx, loaders, opts)
	if err != nil {
		if !errors.Is(err, ErrNoSkillsFound) {
			s.recordServiceError(ctx, baseTags, "list_skills_failed")
		}
		return nil, err
	}

	s.obsv.Increment(ctx, "skills.Service.success", baseTags)
	return skills, nil
}

// GetSkill retrieves a single skill by name.
// It searches all sources in precedence order: repo (.github/skills, .claude/skills) > org > enterprise.
// The first matching skill found is returned.
func (s *Service) GetSkill(ctx context.Context, repoOwner, repoName, skillName, version string, opts GetSkillOpts) (*Skill, error) {
	// Get all source loaders (repo, org, enterprise) in precedence order
	loaders, err := s.getLazySourceRepoLoaders(ctx, repoOwner, repoName, nil) // nil = all sources
	if err != nil {
		return nil, goerrors.Errorf("failed to get source repositories: %w", err)
	}

	return s.resolveSkillFromLoaders(ctx, skillName, version, loaders, opts)
}

// resolveSkillFromLoaders searches for a skill by name through a list of source repository loaders.
// Returns the first matching skill found, or ErrRequestedSkillNotFound if not found in any source.
func (s *Service) resolveSkillFromLoaders(ctx context.Context, skillName, version string, loaders []lazySourceRepoLoader, opts GetSkillOpts) (*Skill, error) {
	for _, loader := range loaders {
		repo, privileged, err := loader()
		if err != nil {
			return nil, goerrors.Errorf("failed to initialize repository for skill lookup: %w", err)
		}
		if repo == nil {
			continue // No repo at this source (e.g., org repo doesn't exist), skip
		}

		// For org/enterprise repos, verify user has access via dotcom
		if privileged && !opts.SkipAccessCheck {
			if opts.UserID == 0 {
				return nil, goerrors.Errorf("UserID must be non-zero when SkipAccessCheck is false for privileged repo")
			}

			hasAccess, err := s.verifyRepoAccess(ctx, opts.UserID, repo.id)
			if err != nil {
				return nil, goerrors.Errorf("failed to verify access to repo %s/%s for skill: %w: %w", repo.owner, repo.name, ErrAuthorizationFailed, err)
			}
			if !hasAccess {
				s.obsv.Logger.WithContext(ctx).Info("user does not have access to get skill from repo")
				continue
			}
		}

		me := Metadata{
			Name:        skillName,
			RepoID:      int64(repo.id),
			RepoOwner:   repo.owner,
			RepoOwnerID: int64(repo.ownerID),
			RepoName:    repo.name,
			Version:     version,
		}

		skill, err := repo.skill(ctx, me)
		if err != nil {
			if errors.Is(err, ErrRequestedSkillNotFound) || errors.Is(err, ErrRepoNotFound) {
				continue // Skill not found in this source, try next
			}
			if errors.Is(err, ErrMalformedConfig) {
				// Malformed config is non-fatal - log and try next source
				s.obsv.Logger.WithContext(ctx).WithError(err).Warn("skipping malformed skill config")
				continue
			}
			return nil, goerrors.Errorf("failed to fetch skill from repo %s/%s: %w", repo.owner, repo.name, err)
		}

		return skill, nil
	}

	return nil, ErrRequestedSkillNotFound
}

// listSkillsFromLoaders fetches skills from each loader in order.
func (s *Service) listSkillsFromLoaders(ctx context.Context, loaders []lazySourceRepoLoader, opts ListSkillsOpts) ([]*Skill, error) {
	var allSkills []*Skill
	seen := make(map[string]bool)

	for _, loader := range loaders {
		repo, privileged, err := loader()
		if err != nil {
			return nil, goerrors.Errorf("failed to initialize repository for skills: %w", err)
		}
		if repo == nil {
			continue // No repo at this source (e.g., org repo doesn't exist), skip
		}

		// For org/enterprise repos, verify user has access via dotcom
		if privileged && !opts.SkipAccessCheck {
			if opts.UserID == 0 {
				return nil, goerrors.Errorf("UserID must be non-zero when SkipAccessCheck is false for privileged repo")
			}

			hasAccess, err := s.verifyRepoAccess(ctx, opts.UserID, repo.id)
			if err != nil {
				return nil, goerrors.Errorf("failed to verify access to repo %s/%s for skills: %w: %w", repo.owner, repo.name, ErrAuthorizationFailed, err)
			}
			if !hasAccess {
				s.obsv.Logger.WithContext(ctx).Info("user does not have access to list skills from repo")
				continue
			}
		}

		repoSkills, err := repo.skills(ctx)
		if err != nil {
			if errors.Is(err, ErrNoSkillsFound) {
				continue // No skills in this repo, try next
			}
			return nil, goerrors.Errorf("failed to list skills from repo %s/%s: %w", repo.owner, repo.name, err)
		}

		if opts.DedupeNames {
			// Only add skills we haven't seen yet (first occurrence wins)
			// Dedupe on DisplayName since that's what gets registered to the model
			for _, skill := range repoSkills {
				dn := skill.DisplayName()
				if !seen[dn] {
					seen[dn] = true
					allSkills = append(allSkills, skill)
				}
			}
		} else {
			allSkills = append(allSkills, repoSkills...)
		}
	}

	if len(allSkills) == 0 {
		return nil, ErrNoSkillsFound
	}

	return allSkills, nil
}

// getLazySourceRepoLoaders returns lazy loaders for each skill source in precedence order.
// The order is: repo (.github/skills) > repo (.claude/skills) > org (.github, .github-private) > enterprise (first wins for deduping).
func (s *Service) getLazySourceRepoLoaders(ctx context.Context, repoOwner, repoName string, includeSources []string) ([]lazySourceRepoLoader, error) {
	// Default to all sources if not specified
	if len(includeSources) == 0 {
		includeSources = []string{SourceTypeRepo, SourceTypeOrg, SourceTypeEnterprise}
	}

	// We always need to get the initial repo to determine owner ID for enterprise lookup
	initialRepo, err := NewRepository(ctx, s.rp, s.spokes, s.obsv, repoOwner, repoName, Directory)
	if err != nil {
		return nil, goerrors.Errorf("failed to get repo %s/%s: %w", repoOwner, repoName, err)
	}

	loaders, err := s.getSourceLoadersForOwner(ctx, initialRepo.ownerID, initialRepo.owner, includeSources)
	if err != nil {
		return nil, goerrors.Errorf("failed to get source loaders: %w", err)
	}

	if slices.Contains(includeSources, SourceTypeRepo) {
		// Prepend repo-level loaders: .github/skills first, then .claude/skills
		// This gives .github/skills priority over .claude/skills for deduplication
		claudeRepoLoader := func() (*Repository, bool, error) {
			claudeRepo, err := NewRepository(ctx, s.rp, s.spokes, s.obsv, repoOwner, repoName, ClaudeDirectory)
			if err != nil {
				return nil, false, err
			}
			return claudeRepo, isOrgRepoName(claudeRepo.name), nil
		}
		initialRepoLoader := func() (*Repository, bool, error) {
			return initialRepo, isOrgRepoName(initialRepo.name), nil
		}
		// Order: .github/skills, .claude/skills, then org/enterprise
		loaders = append([]lazySourceRepoLoader{initialRepoLoader, claudeRepoLoader}, loaders...)
	}

	return loaders, nil
}

// getSourceLoadersForOwner returns loaders for org and enterprise sources.
func (s *Service) getSourceLoadersForOwner(ctx context.Context, ownerID uint64, ownerName string, includeSources []string) ([]lazySourceRepoLoader, error) {
	loaders := make([]lazySourceRepoLoader, 0, 3)

	if slices.Contains(includeSources, SourceTypeOrg) {
		loaders = append(loaders,
			s.getOrgLoader(ctx, ownerName, orgRepoName),
			s.getOrgLoader(ctx, ownerName, orgRepoName+"-private"),
		)
	}

	if slices.Contains(includeSources, SourceTypeEnterprise) {
		loaders = append(loaders, s.getEnterpriseLoader(ctx, ownerID))
	}

	return loaders, nil
}

// getOrgLoader returns a lazy loader for an org-level repository.
func (s *Service) getOrgLoader(ctx context.Context, repoOwner, repoName string) lazySourceRepoLoader {
	return func() (*Repository, bool, error) {
		repo, err := NewRepository(ctx, s.rp, s.spokes, s.obsv, repoOwner, repoName, OrgDirectory)
		if err != nil {
			if errors.Is(err, ErrRepoNotFound) {
				return nil, false, nil // No org repo, skip
			}
			return nil, false, goerrors.Errorf("failed to get org repo %s/%s: %w", repoOwner, repoName, err)
		}
		return repo, true, nil
	}
}

// getEnterpriseLoader returns a lazy loader for the enterprise-level repository.
func (s *Service) getEnterpriseLoader(ctx context.Context, ownerID uint64) lazySourceRepoLoader {
	return func() (*Repository, bool, error) {
		enterpriseRepo, err := s.getEnterpriseRepo(ctx, ownerID)
		if err != nil {
			if errors.Is(err, gitrepo.ErrRepoNotFound) {
				return nil, false, nil // No enterprise repo, skip
			}
			return nil, false, goerrors.Errorf("failed to get enterprise source repo: %w", err)
		}
		return enterpriseRepo, true, nil
	}
}

// getEnterpriseRepo retrieves the enterprise-level repository for the given owner.
func (s *Service) getEnterpriseRepo(ctx context.Context, ownerID uint64) (*Repository, error) {
	req := &sweagentdv1.EnterpriseAgentsRequest{
		FindAgentsBy: &sweagentdv1.EnterpriseAgentsRequest_OwnerId{
			OwnerId: ownerID,
		},
	}

	enterpriseResp, err := s.ghtwirp.SweagentdAPI().EnterpriseAgents(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) && twirpErr.Code() == twirp.NotFound {
			return nil, gitrepo.ErrRepoNotFound
		}
		return nil, goerrors.Errorf("failed to get enterprise repo: %w", err)
	}

	repoID := enterpriseResp.GetRepositoryId()
	if repoID == 0 {
		return nil, gitrepo.ErrRepoNotFound
	}

	return NewRepositoryByID(ctx, s.rp, s.spokes, s.obsv, repoID, OrgDirectory)
}

// verifyRepoAccess checks if the user has access to the given repository via dotcom.
// This is used for org/enterprise repositories to verify membership.
func (s *Service) verifyRepoAccess(ctx context.Context, userID, repoID uint64) (bool, error) {
	req := &sweagentdv1.AuthorizeCustomAgentRepoForUserRequest{
		UserId:       userID,
		RepositoryId: repoID,
	}

	resp, err := s.ghtwirp.SweagentdAPI().AuthorizeCustomAgentRepoForUser(ctx, req)
	if err != nil {
		return false, goerrors.Errorf("failed to verify access: %w: %w", ErrAuthorizationFailed, err)
	}

	return resp.GetCanAccess(), nil
}

func (s *Service) recordServiceError(ctx context.Context, baseTags stats.Tags, errorReason string) {
	errorTags := baseTags.Merge(stats.Tags{"error_reason": errorReason})
	s.obsv.Increment(ctx, "skills.Service.error", errorTags)
}
