package skills

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/gitrepo"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/sweagentd"
)

var (
	// ErrRequestedSkillNotFound is returned when a specific skill configuration file is not found in the repository.
	ErrRequestedSkillNotFound = goerrors.New("requested skill not found in repository")

	// ErrNoSkillsFound is returned when no skills are found in the repository.
	ErrNoSkillsFound = goerrors.New("no skills found in repository")
)

const (
	// Directory is the path within the repository where skill configurations are stored.
	Directory = ".github/skills"

	// ClaudeDirectory is an alternative path for skills (Claude Code compatibility).
	ClaudeDirectory = ".claude/skills"

	// OrgDirectory is the path in org and enterprise repositories where privileged skill configurations may come from.
	OrgDirectory = "skills"

	// SkillFileName is the marker file name for skill directories.
	SkillFileName = "SKILL.md"
)

// Repository represents a GitHub repository from which skill configurations can be fetched.
type Repository struct {
	rp     gitrepo.RepoProvider
	spokes sweagentd.Spokes
	obsv   observability.Exporters

	id        uint64
	owner     string
	ownerID   uint64
	name      string
	directory string
}

// NewRepository creates a new Repository instance with the provided content provider, name, and owner.
// dir is where to look for the skills.
func NewRepository(ctx context.Context, rp gitrepo.RepoProvider, sp sweagentd.Spokes, obsv observability.Exporters, owner, name, dir string) (*Repository, error) {
	ghrepo, err := rp.GetRepository(ctx, owner, name)
	if err != nil {
		return nil, err
	}

	return &Repository{
		rp:        rp,
		spokes:    sp,
		obsv:      obsv,
		id:        uint64(ghrepo.GetID()),
		owner:     owner,
		ownerID:   uint64(ghrepo.GetOwnerID()),
		name:      name,
		directory: dir,
	}, nil
}

// NewRepositoryByID creates a new Repository instance with the provided content repo ID.
func NewRepositoryByID(ctx context.Context, rp gitrepo.RepoProvider, sp sweagentd.Spokes, obsv observability.Exporters, repoID uint64, dir string) (*Repository, error) {
	ghrepo, err := rp.GetRepositoryByID(ctx, int64(repoID))
	if err != nil {
		return nil, err
	}

	return &Repository{
		rp:        rp,
		spokes:    sp,
		obsv:      obsv,
		id:        repoID,
		owner:     ghrepo.GetOwnerName(),
		ownerID:   uint64(ghrepo.GetOwnerID()),
		name:      ghrepo.GetName(),
		directory: dir,
	}, nil
}

// skill retrieves a single skill configuration from the repository.
func (r *Repository) skill(ctx context.Context, me Metadata) (*Skill, error) {
	result, err := r.skillConfig(ctx, me.Name, me.Version)
	if err != nil {
		return nil, goerrors.Errorf("failed to get skill configuration from repo for %s skill: %w", me.Name, err)
	}
	me.Version = result.version
	me.FilePath = result.filePath

	cfg, err := parseSkillConfig(result.contents, me.Name)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse skill configuration for %s skill: %w", me.Name, err)
	}

	return &Skill{
		metadata: me,
		config:   cfg,
	}, nil
}

// skills retrieves the list of skills available in the repository.
func (r *Repository) skills(ctx context.Context) ([]*Skill, error) {
	// List immediate children of the skills directory (non-recursive)
	// Each child should be a skill directory name (e.g., "math-skill", "pdf-skill")
	entries, oid, err := r.spokes.ListTrees(ctx, r.id, r.directory+"/")
	if err != nil {
		if errors.Is(err, spokes.ErrNotFound) {
			return nil, ErrNoSkillsFound
		}
		return nil, err
	}

	if len(entries) == 0 {
		return nil, nil
	}

	// Build metadata and paths for each potential skill
	// Only process directory entries - skills are in subdirectories
	mes := make([]Metadata, 0, len(entries))
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		// Skip non-directory entries (files directly in skills folder)
		if !entry.IsDir {
			r.obsv.Logger.Info("skipping non-directory entry",
				kvp.String("path", entry.Path),
				kvp.Bool("is_dir", entry.IsDir),
			)
			continue
		}

		skillName := entry.Path
		idx := strings.LastIndex(skillName, "/")
		if idx >= 0 {
			skillName = skillName[idx+1:]
		}

		// Skip invalid skill names (traversal patterns, invalid characters, etc.)
		// Directory names must match the same regex as frontmatter names
		if skillName == "" || skillName == "." || skillName == ".." ||
			strings.Contains(skillName, "/") || strings.Contains(skillName, "\\") {
			r.obsv.Logger.Warn("skipping invalid skill directory name",
				kvp.String("repo", fmt.Sprintf("%s/%s", r.owner, r.name)),
				kvp.String("name", skillName),
				kvp.String("original_path", entry.Path),
			)
			continue
		}

		// Construct the full path to SKILL.md
		skillFilePath := filepath.Join(r.directory, skillName, SkillFileName)

		me := Metadata{
			Name:        skillName,
			RepoID:      int64(r.id),
			RepoOwner:   r.owner,
			RepoOwnerID: int64(r.ownerID),
			RepoName:    r.name,
			Version:     oid,
			FilePath:    skillFilePath,
		}

		mes = append(mes, me)
		paths = append(paths, skillFilePath)
	}

	if len(paths) == 0 {
		return nil, nil
	}

	// Read all skill files by path in a single batch call
	blobs, err := r.spokes.ReadBlobsByPaths(ctx, r.id, oid, paths)
	if err != nil {
		return nil, goerrors.Errorf("failed to read skill blobs: %w", err)
	}

	skills := make([]*Skill, 0, len(blobs))
	for i, content := range blobs {
		// Skip entries where SKILL.md doesn't exist (content will be nil)
		if content == nil {
			continue
		}

		cfg, err := parseSkillConfig(string(content), mes[i].Name)
		if err != nil {
			// Log the error and skip this invalid configuration
			tags := r.obsv.TelemetryTags(ctx)
			r.obsv.Increment(ctx, "skills.invalidconfig.skipped", tags)
			r.obsv.Logger.Info("skipping invalid skill configuration",
				kvp.String("repo", fmt.Sprintf("%s/%s", r.owner, r.name)),
				kvp.String("skill_name", mes[i].Name),
				kvp.String("error", err.Error()),
			)
			continue
		}

		skills = append(skills, &Skill{
			metadata: mes[i],
			config:   cfg,
		})
	}

	return skills, nil
}

// isOrgRepoName returns true if the repo name is an org-level repo (.github or .github-private).
func isOrgRepoName(name string) bool {
	return name == orgRepoName || name == orgRepoName+"-private"
}

// skillConfigResult holds the contents and version of a skill configuration file.
type skillConfigResult struct {
	contents string
	version  string
	filePath string
}

// skillConfig retrieves the configuration for a specific skill by its name and version.
func (r *Repository) skillConfig(ctx context.Context, name, version string) (*skillConfigResult, error) {
	skillPath := filepath.Join(r.directory, name, SkillFileName)

	if version == "" {
		blob, commitSHA, err := r.spokes.ReadBlob(ctx, r.id, skillPath)
		if err != nil {
			if errors.Is(err, spokes.ErrNotFound) {
				return nil, ErrRequestedSkillNotFound
			}
			if errors.Is(err, spokes.ErrDefaultBranchNotFound) {
				return nil, ErrRequestedSkillNotFound
			}
			return nil, err
		}

		return &skillConfigResult{
			contents: string(blob),
			version:  commitSHA,
			filePath: skillPath,
		}, nil
	}

	// Version must be a valid SHA
	if !gitrepo.IsValidSHA(version) {
		return nil, goerrors.Errorf("invalid version specified %s: %w", version, ErrRequestedSkillNotFound)
	}

	blob, err := r.spokes.ReadBlobByObjectIDPath(ctx, r.id, version, skillPath)
	if err != nil {
		if errors.Is(err, spokes.ErrNotFound) {
			return nil, ErrRequestedSkillNotFound
		}
		return nil, err
	}

	return &skillConfigResult{
		contents: string(blob),
		version:  version,
		filePath: skillPath,
	}, nil
}
