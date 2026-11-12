package skills

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// Helper function to create spokes with skills for a single repository
// Skills are stored as directories with SKILL.md files inside
func makeSpokesWithSkills(t *testing.T, skills map[string]string) *spokestest.Client {
	t.Helper()

	fileBlobs := []spokestest.ClientOption{}
	for name, content := range skills {
		// Skills are stored as: .github/skills/<skill-name>/SKILL.md
		blob := spokestest.WithBlob(filepath.Join(Directory, name, SkillFileName), []byte(content))
		fileBlobs = append(fileBlobs, blob)
	}

	return spokestest.NewClient(t, fileBlobs...)
}

// Helper function to create spokes with repo-specific skills for testing repo/org precedence
func makeSpokesWithRepoSpecificSkills(t *testing.T, repoSkills, orgSkills map[string]string, repoID, orgRepoID uint64) *spokestest.Client {
	t.Helper()

	options := []spokestest.ClientOption{}

	// Add repository-specific skills (.github/skills/<name>/SKILL.md)
	for name, content := range repoSkills {
		option := spokestest.WithRepoBlob(repoID, filepath.Join(Directory, name, SkillFileName), []byte(content))
		options = append(options, option)
	}

	// Add organization-specific skills (skills/<name>/SKILL.md in .github repo)
	for name, content := range orgSkills {
		option := spokestest.WithRepoBlob(orgRepoID, filepath.Join(OrgDirectory, name, SkillFileName), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

// Helper function to create spokes with skills across repo, org public, and org private repos
func makeSpokesWithMultipleOrgRepos(t *testing.T, repoSkills, publicOrgSkills, privateOrgSkills map[string]string, repoID, publicOrgRepoID, privateOrgRepoID uint64) *spokestest.Client {
	t.Helper()

	options := []spokestest.ClientOption{}

	// Add repository-specific skills
	for name, content := range repoSkills {
		option := spokestest.WithRepoBlob(repoID, filepath.Join(Directory, name, SkillFileName), []byte(content))
		options = append(options, option)
	}

	// Add public organization-specific skills (.github)
	for name, content := range publicOrgSkills {
		option := spokestest.WithRepoBlob(publicOrgRepoID, filepath.Join(OrgDirectory, name, SkillFileName), []byte(content))
		options = append(options, option)
	}

	// Add private organization-specific skills (.github-private)
	for name, content := range privateOrgSkills {
		option := spokestest.WithRepoBlob(privateOrgRepoID, filepath.Join(OrgDirectory, name, SkillFileName), []byte(content))
		options = append(options, option)
	}

	return spokestest.NewClient(t, options...)
}

// Helper to setup mock for FindRepositoriesByName
func setupRepositoryMocks(t *testing.T, ghtwirp *githubtwirp.NoopClient, repoName, ownerLogin string, repoID, orgRepoID, privateOrgRepoID, repoOwnerID uint64, orgReposExist bool) {
	t.Helper()
	ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		parts := strings.Split(req.Nwos[0], "/")
		id := repoID
		switch parts[1] {
		case ".github":
			id = orgRepoID
		case ".github-private":
			id = privateOrgRepoID
		default:
			// Do nothing - here for linting purposes
		}
		if (id == orgRepoID || id == privateOrgRepoID) && !orgReposExist {
			return nil, twirp.NewError(twirp.NotFound, fmt.Sprintf("repository %s/%s not found", parts[0], parts[1]))
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         int64(id),
					Name:       parts[1],
					OwnerId:    int64(repoOwnerID),
					OwnerLogin: parts[0],
				},
			},
		}, nil
	}
	ghtwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		name := repoName
		switch uint64(req.Ids[0]) {
		case orgRepoID:
			name = ".github"
		case privateOrgRepoID:
			name = ".github-private"
		default:
			// Do nothing - here for linting purposes
		}
		if (name == ".github" || name == ".github-private") && !orgReposExist {
			return nil, twirp.NewError(twirp.NotFound, fmt.Sprintf("repository %d not found", req.Ids[0]))
		}
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         req.Ids[0],
					Name:       name,
					OwnerId:    int64(repoOwnerID),
					OwnerLogin: ownerLogin,
				},
			},
		}, nil
	}

	// Default: no enterprise skills
	ghtwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
	}
}

// Helper to extract skill names from results
func extractSkillNames(skills []*Skill) []string {
	names := make([]string, len(skills))
	for i, skill := range skills {
		names[i] = skill.DisplayName()
	}
	return names
}

// Helper to verify repo IDs in skill results
func verifySkillRepoIDs(t *testing.T, skills []*Skill, expectedIDs ...int64) {
	t.Helper()
	skillRepoIDs := make(map[int64]bool)
	for _, skill := range skills {
		skillRepoIDs[skill.RepoID()] = true
	}
	require.Len(t, skillRepoIDs, len(expectedIDs))
	for _, id := range expectedIDs {
		require.True(t, skillRepoIDs[id])
	}
}

func TestService_ListSkills(t *testing.T) {
	ctx := context.Background()
	repoOwner := "test-owner"
	repoName := "test-repo"

	// Setup different repository IDs to distinguish between repo and org
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	t.Run("returns only repo skills when no org skills exist", func(t *testing.T) {
		repoSkills := map[string]string{
			"repo-skill1": `---
name: Repo Skill 1
description: First repository skill
---

You are a repository-level skill.`,
			"repo-skill2": `---
name: Repo Skill 2
description: Second repository skill
---

Another repository skill.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 2)
		skillNames := extractSkillNames(result)
		require.Contains(t, skillNames, "Repo Skill 1")
		require.Contains(t, skillNames, "Repo Skill 2")
		verifySkillRepoIDs(t, result, int64(repoID))
	})

	t.Run("returns both repo and org skills when org skills exist", func(t *testing.T) {
		repoSkills := map[string]string{
			"repo-skill": `---
name: Repo Skill
description: Repository skill
---

A repository skill.`,
		}

		orgSkills := map[string]string{
			"org-skill1": `---
name: Org Skill 1
description: First organization skill
---

You are an organization-level skill.`,
			"org-skill2": `---
name: Org Skill 2
description: Second organization skill
---

Another organization skill.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, orgSkills, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 3) // 1 repo + 2 org skills

		skillNames := extractSkillNames(result)
		require.Contains(t, skillNames, "Repo Skill")
		require.Contains(t, skillNames, "Org Skill 1")
		require.Contains(t, skillNames, "Org Skill 2")

		// Verify skills come from different repos
		skillRepoIDs := make(map[int64]bool)
		for _, skill := range result {
			skillRepoIDs[skill.RepoID()] = true
		}
		require.Len(t, skillRepoIDs, 2)
		require.True(t, skillRepoIDs[int64(repoID)])
		require.True(t, skillRepoIDs[int64(orgRepoID)])
	})

	t.Run("combines repo and org skills with repo skills taking precedence", func(t *testing.T) {
		repoSkills := map[string]string{
			"shared-skill": `---
name: Shared Skill
description: Repository version of shared skill
---

This is the repo version and should take precedence.`,
			"repo-only": `---
name: Repo Only Skill
description: Only exists in repository
---

This skill only exists in the repository.`,
		}

		orgSkills := map[string]string{
			"shared-skill": `---
name: Shared Skill
description: Organization version of shared skill
---

This is the org version and should NOT be returned.`,
			"org-only": `---
name: Org Only Skill
description: Only exists in organization
---

This skill only exists in the organization.`,
		}

		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, orgSkills, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 3)

		skillNames := extractSkillNames(result)
		skillDescriptions := make(map[string]string)
		for _, skill := range result {
			skillDescriptions[skill.DisplayName()] = skill.Description()
		}

		require.Contains(t, skillNames, "Shared Skill")
		require.Contains(t, skillNames, "Repo Only Skill")
		require.Contains(t, skillNames, "Org Only Skill")

		// Verify shared-skill is the repo version (first encountered)
		require.Equal(t, "Repository version of shared skill", skillDescriptions["Shared Skill"])
		require.Equal(t, "Only exists in repository", skillDescriptions["Repo Only Skill"])
		require.Equal(t, "Only exists in organization", skillDescriptions["Org Only Skill"])
	})

	t.Run("returns ErrRepoNotFound when repository not found", func(t *testing.T) {
		spokes := makeSpokesWithSkills(t, map[string]string{})

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
			return &repositoriesTwirp.FindRepositoriesResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{},
			}, nil
		}
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{},
			}, nil
		}

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, "org", "repo", ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.True(t, errors.Is(err, ErrRepoNotFound))
		require.Nil(t, result)
	})

	t.Run("returns ErrNoSkillsFound when no skills exist in any source", func(t *testing.T) {
		// Empty spokes - no skills configured
		spokes := makeSpokesWithSkills(t, map[string]string{})

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.True(t, errors.Is(err, ErrNoSkillsFound))
		require.Len(t, result, 0)
	})
}

func TestService_ListSkillsDedupeNames(t *testing.T) {
	ctx := context.Background()
	repoOwner := "test-owner"
	repoName := "test-repo"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	setupMocks := func(t *testing.T, repoSkills, orgSkills map[string]string) *Service {
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, orgSkills, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		return NewService(observability.NewNoopExporters(), spokes, ghtwirp)
	}

	// Setup skills with duplicates across repo and org
	repoSkills := map[string]string{
		"skill1": `---
name: Skill 1
description: First skill from repository
---
Content.`,
		"skill2": `---
name: Skill 2
description: Second skill from repository
---
Content.`,
	}
	orgSkills := map[string]string{
		"skill1": `---
name: Skill 1
description: First skill from organization
---
Content.`,
		"skill3": `---
name: Skill 3
description: Third skill from organization
---
Content.`,
	}
	service := setupMocks(t, repoSkills, orgSkills)

	t.Run("dedupeNames=true removes duplicate skill names across repos", func(t *testing.T) {
		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 3, "should return 3 unique skills when dedupeNames=true")

		skillNames := make([]string, len(result))
		skillDescriptions := make(map[string]string)
		for i, skill := range result {
			skillNames[i] = skill.DisplayName()
			skillDescriptions[skill.DisplayName()] = skill.Description()
		}

		require.Contains(t, skillNames, "Skill 1")
		require.Contains(t, skillNames, "Skill 2")
		require.Contains(t, skillNames, "Skill 3")

		// skill1 should be the repo version (first encountered)
		require.Equal(t, "First skill from repository", skillDescriptions["Skill 1"])
		require.Equal(t, "Second skill from repository", skillDescriptions["Skill 2"])
		require.Equal(t, "Third skill from organization", skillDescriptions["Skill 3"])
	})

	t.Run("dedupeNames=false keeps duplicate skill names across repos", func(t *testing.T) {
		// Only include repo and org sources
		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true,
			DedupeNames:    false,
			IncludeSources: []string{SourceTypeRepo, SourceTypeOrg},
		})
		require.NoError(t, err)
		require.GreaterOrEqual(t, len(result), 4, "should return at least 4 skills when dedupeNames=false")

		// Should have Skill 1 from both repo and org
		skill1Count := 0
		skill1Descriptions := make([]string, 0)
		allSkillNames := make(map[string]bool)

		for _, skill := range result {
			allSkillNames[skill.DisplayName()] = true
			if skill.DisplayName() == "Skill 1" {
				skill1Count++
				skill1Descriptions = append(skill1Descriptions, skill.Description())
			}
		}

		require.GreaterOrEqual(t, skill1Count, 2, "should have at least 2 instances of Skill 1")
		require.Contains(t, skill1Descriptions, "First skill from repository")
		require.Contains(t, skill1Descriptions, "First skill from organization")

		// Should also have Skill 2 and Skill 3
		require.True(t, allSkillNames["Skill 2"], "should have Skill 2")
		require.True(t, allSkillNames["Skill 3"], "should have Skill 3")
	})

	t.Run("dedupeNames=true keeps skills with same dirname but different display names", func(t *testing.T) {
		// Test case: same directory name but different frontmatter names
		// These should NOT be deduped since they have different display names
		repoSkillsDiffNames := map[string]string{
			"shared-skill": `---
name: Repo Version
description: Skill from repository
---
Content.`,
		}
		orgSkillsDiffNames := map[string]string{
			"shared-skill": `---
name: Org Version
description: Skill from organization
---
Content.`,
		}
		svc := setupMocks(t, repoSkillsDiffNames, orgSkillsDiffNames)

		result, err := svc.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{
			SkipAccessCheck: true,
			DedupeNames:     true,
			IncludeSources:  []string{SourceTypeRepo, SourceTypeOrg},
		})
		require.NoError(t, err)
		require.Len(t, result, 2, "should return 2 skills with different display names even if dirname is same")

		displayNames := make([]string, len(result))
		for i, skill := range result {
			displayNames[i] = skill.DisplayName()
		}
		require.Contains(t, displayNames, "Repo Version")
		require.Contains(t, displayNames, "Org Version")
	})
}

func TestService_ListSkillsIncludeSources(t *testing.T) {
	ctx := context.Background()
	repoOwner := "test-owner"
	repoName := "test-repo"
	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	repoSkills := map[string]string{
		"repo-skill": `---
name: Repo Skill
description: Skill from repository
---
Content.`,
	}
	orgSkills := map[string]string{
		"org-skill": `---
name: Org Skill
description: Skill from organization
---
Content.`,
	}

	spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, orgSkills, repoID, orgRepoID)

	ghtwirp := githubtwirp.NewNoopClient()
	setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

	service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

	t.Run("include only repo source returns only repo skills", func(t *testing.T) {
		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo},
		})
		require.NoError(t, err)
		require.Len(t, result, 1, "should return only 1 repo skill")

		skillNames := extractSkillNames(result)
		require.Contains(t, skillNames, "Repo Skill")
		require.NotContains(t, skillNames, "Org Skill")
	})

	t.Run("include only org source returns only org skills", func(t *testing.T) {
		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeOrg},
		})
		require.NoError(t, err)
		require.GreaterOrEqual(t, len(result), 1, "should return at least 1 org skill")

		skillNames := extractSkillNames(result)
		require.Contains(t, skillNames, "Org Skill")
		require.NotContains(t, skillNames, "Repo Skill")
	})

	t.Run("include repo and org returns both", func(t *testing.T) {
		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeRepo, SourceTypeOrg},
		})
		require.NoError(t, err)
		require.Len(t, result, 2)

		skillNames := extractSkillNames(result)
		require.Contains(t, skillNames, "Repo Skill")
		require.Contains(t, skillNames, "Org Skill")
	})

	t.Run("empty IncludeSources defaults to all sources", func(t *testing.T) {
		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true,
			DedupeNames:    true,
			IncludeSources: []string{}, // empty
		})
		require.NoError(t, err)
		require.Len(t, result, 2)

		skillNames := extractSkillNames(result)
		require.Contains(t, skillNames, "Repo Skill")
		require.Contains(t, skillNames, "Org Skill")
	})
}

func TestService_GetSkill(t *testing.T) {
	ctx := context.Background()
	repoOwner := "test-owner"
	repoName := "test-repo"

	repoID := uint64(1)
	orgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	t.Run("returns skill from repo when it exists", func(t *testing.T) {
		repoSkills := map[string]string{
			"my-skill": `---
name: My Skill
description: A skill in the repo
---

Skill content.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		skill, err := service.GetSkill(ctx, repoOwner, repoName, "my-skill", "", GetSkillOpts{SkipAccessCheck: true})
		require.NoError(t, err)
		require.NotNil(t, skill)
		require.Equal(t, "My Skill", skill.DisplayName())
		require.Equal(t, "A skill in the repo", skill.Description())
		require.Equal(t, int64(repoID), skill.RepoID())
	})

	t.Run("returns skill from org when not in repo", func(t *testing.T) {
		repoSkills := map[string]string{
			"repo-skill": `---
name: Repo Skill
description: A skill in the repo
---

Content.`,
		}
		orgSkills := map[string]string{
			"org-skill": `---
name: Org Skill
description: A skill in the org
---

Org content.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, orgSkills, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		skill, err := service.GetSkill(ctx, repoOwner, repoName, "org-skill", "", GetSkillOpts{SkipAccessCheck: true})
		require.NoError(t, err)
		require.NotNil(t, skill)
		require.Equal(t, "Org Skill", skill.DisplayName())
		require.Equal(t, "A skill in the org", skill.Description())
		require.Equal(t, int64(orgRepoID), skill.RepoID())
	})

	t.Run("prefers repo skill over org skill with same name", func(t *testing.T) {
		repoSkills := map[string]string{
			"shared-skill": `---
name: Shared Skill
description: Repo version
---

Repo content.`,
		}
		orgSkills := map[string]string{
			"shared-skill": `---
name: Shared Skill
description: Org version
---

Org content.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, orgSkills, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, true)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		skill, err := service.GetSkill(ctx, repoOwner, repoName, "shared-skill", "", GetSkillOpts{SkipAccessCheck: true})
		require.NoError(t, err)
		require.NotNil(t, skill)
		require.Equal(t, "Shared Skill", skill.DisplayName())
		require.Equal(t, "Repo version", skill.Description())
		require.Equal(t, int64(repoID), skill.RepoID())
	})

	t.Run("returns ErrRequestedSkillNotFound when skill does not exist", func(t *testing.T) {
		repoSkills := map[string]string{
			"some-skill": `---
name: Some Skill
description: A skill
---

Content.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, map[string]string{}, repoID, orgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, orgRepoID, privateOrgRepoID, repoOwnerID, false)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		skill, err := service.GetSkill(ctx, repoOwner, repoName, "nonexistent-skill", "", GetSkillOpts{SkipAccessCheck: true})
		require.True(t, errors.Is(err, ErrRequestedSkillNotFound))
		require.Nil(t, skill)
	})

	t.Run("returns ErrRepoNotFound when repository does not exist", func(t *testing.T) {
		spokes := makeSpokesWithSkills(t, map[string]string{})

		ghtwirp := githubtwirp.NewNoopClient()
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{},
			}, nil
		}

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		skill, err := service.GetSkill(ctx, "nonexistent-owner", "nonexistent-repo", "any-skill", "", GetSkillOpts{SkipAccessCheck: true})
		require.True(t, errors.Is(err, ErrRepoNotFound))
		require.Nil(t, skill)
	})
}

func TestService_OrgPrecedence(t *testing.T) {
	ctx := context.Background()
	repoOwner := "test-owner"
	repoName := "test-repo"
	repoID := uint64(1)
	publicOrgRepoID := uint64(2)
	privateOrgRepoID := uint64(3)
	repoOwnerID := uint64(4)

	t.Run(".github takes precedence over .github-private for skills with same name", func(t *testing.T) {
		repoSkills := map[string]string{}
		publicOrgSkills := map[string]string{
			"shared-org-skill": `---
name: Shared Org Skill
description: From .github (public)
---

Public org content.`,
		}
		privateOrgSkills := map[string]string{
			"shared-org-skill": `---
name: Shared Org Skill
description: From .github-private
---

Private org content.`,
		}

		spokes := makeSpokesWithMultipleOrgRepos(t, repoSkills, publicOrgSkills, privateOrgSkills, repoID, publicOrgRepoID, privateOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		// Override to handle both org repos
		ghtwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			parts := strings.Split(req.Nwos[0], "/")
			id := repoID
			switch parts[1] {
			case ".github":
				id = publicOrgRepoID
			case ".github-private":
				id = privateOrgRepoID
			default:
				// keep default repoID
			}
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         int64(id),
						Name:       parts[1],
						OwnerId:    int64(repoOwnerID),
						OwnerLogin: parts[0],
					},
				},
			}, nil
		}
		ghtwirp.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
			name := repoName
			switch uint64(req.Ids[0]) {
			case publicOrgRepoID:
				name = ".github"
			case privateOrgRepoID:
				name = ".github-private"
			default:
				// keep default repoName
			}
			return &repositoriesTwirp.FindRepositoriesResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         req.Ids[0],
						Name:       name,
						OwnerId:    int64(repoOwnerID),
						OwnerLogin: repoOwner,
					},
				},
			}, nil
		}
		ghtwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("enterprise agents not configured")
		}

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true,
			DedupeNames:    true,
			IncludeSources: []string{SourceTypeOrg},
		})
		require.NoError(t, err)
		require.Len(t, result, 1)

		// Should be from .github (public), not .github-private
		require.Equal(t, "Shared Org Skill", result[0].DisplayName())
		require.Equal(t, "From .github (public)", result[0].Description())
		require.Equal(t, int64(publicOrgRepoID), result[0].RepoID())
	})

	t.Run("skips invalid skill configs and continues loading valid ones", func(t *testing.T) {
		// Mix of valid and invalid skills - invalid ones should be skipped, valid ones loaded
		repoSkills := map[string]string{
			"valid-skill": `---
name: Valid Skill
description: This skill has valid configuration
---

You are a valid skill.`,
			"invalid-name-too-long": `---
name: ` + strings.Repeat("x", 100) + `
description: This skill has a name that exceeds the max length
---

This skill should be skipped.`,
			"another-valid-skill": `---
name: Another Valid Skill
description: Another skill with valid configuration
---

You are another valid skill.`,
			"invalid-description-too-long": `---
name: Invalid Description
description: ` + strings.Repeat("y", 1100) + `
---

This skill should also be skipped.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, map[string]string{}, repoID, publicOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, publicOrgRepoID, privateOrgRepoID, repoOwnerID, false)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 2) // Only 2 valid skills should be returned

		skillNames := extractSkillNames(result)
		require.Contains(t, skillNames, "Valid Skill")
		require.Contains(t, skillNames, "Another Valid Skill")
		// Invalid skills should not be present
		require.NotContains(t, skillNames, "invalid-name-too-long")
		require.NotContains(t, skillNames, "invalid-description-too-long")
	})

	t.Run("skips skills with invalid YAML and continues loading valid ones", func(t *testing.T) {
		repoSkills := map[string]string{
			"valid-skill": `---
name: Valid Skill
description: This skill has valid configuration
---

You are a valid skill.`,
			"invalid-yaml": `---
name: Invalid YAML Skill
description: This skill has
  invalid: yaml: syntax: here
---

This skill should be skipped due to YAML parse error.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, map[string]string{}, repoID, publicOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, publicOrgRepoID, privateOrgRepoID, repoOwnerID, false)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 1)

		require.Equal(t, "Valid Skill", result[0].DisplayName())
	})

	t.Run("uses directory name when frontmatter name is missing", func(t *testing.T) {
		repoSkills := map[string]string{
			"skill-from-directory": `---
description: This skill has no name in frontmatter
---

You are a skill whose name comes from the directory.`,
		}
		spokes := makeSpokesWithRepoSpecificSkills(t, repoSkills, map[string]string{}, repoID, publicOrgRepoID)

		ghtwirp := githubtwirp.NewNoopClient()
		setupRepositoryMocks(t, ghtwirp, repoName, repoOwner, repoID, publicOrgRepoID, privateOrgRepoID, repoOwnerID, false)

		service := NewService(observability.NewNoopExporters(), spokes, ghtwirp)

		result, err := service.ListSkills(ctx, repoOwner, repoName, ListSkillsOpts{SkipAccessCheck: true, DedupeNames: true})
		require.NoError(t, err)
		require.Len(t, result, 1)

		// Name should fall back to directory name since frontmatter doesn't have name
		require.Equal(t, "skill-from-directory", result[0].Name())
		require.Equal(t, "This skill has no name in frontmatter", result[0].Description())
	})
}
