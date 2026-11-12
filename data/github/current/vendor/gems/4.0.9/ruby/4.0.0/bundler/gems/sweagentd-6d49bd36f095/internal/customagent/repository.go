package customagent

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
	// ErrRequestedAgentNotFound is returned when a specific agent configuration file is not found in the repository.
	ErrRequestedAgentNotFound = errors.New("requested agent not found in repository")

	// ErrNoAgentsFound is returned when no agents are found in the repository.
	// This can happen if the agents directory does not exist or is empty. Or
	// if the user does not have access to the repository.
	ErrNoAgentsFound = errors.New("no agents found in repository")
)

const (
	// Directory is the path within the repository where custom agent configurations are stored.
	Directory = ".github/agents"

	// OrgDirectory is the path org and enterprise repositories where the privileged custom agent configurations may come from.
	OrgDirectory = "agents"

	// Extension is the file extension for custom agent configuration files.
	Extension = ".md"

	// LongExtension is the file extension for custom agent configuration files w/the VS Code suffix.
	LongExtension = ".agent.md"
)

// Repository represents a GitHub repository from which custom agent configurations can be fetched.
// It provides methods to retrieve the configuration for a specific custom agent.
// The repository is identified by its name and owner.
// The contentProvider interface is used to abstract the method of fetching content from the repository.
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
func NewRepository(ctx context.Context, rp gitrepo.RepoProvider, cp sweagentd.Spokes, obsv observability.Exporters, owner, name, dir string) (*Repository, error) {
	ghrepo, err := rp.GetRepository(ctx, owner, name)
	if err != nil {
		return nil, err
	}

	return &Repository{
		rp:     rp,
		spokes: cp,
		obsv:   obsv,

		id:        uint64(ghrepo.GetID()),
		owner:     owner,
		ownerID:   uint64(ghrepo.GetOwnerID()),
		name:      name,
		directory: dir,
	}, nil
}

// NewRepositoryByID creates a new Repository instance with the provided content repo ID.
func NewRepositoryByID(ctx context.Context, rp gitrepo.RepoProvider, cp sweagentd.Spokes, obsv observability.Exporters, repoID uint64, dir string) (*Repository, error) {
	ghrepo, err := rp.GetRepositoryByID(ctx, int64(repoID))
	if err != nil {
		return nil, err
	}

	return &Repository{
		rp:     rp,
		spokes: cp,
		obsv:   obsv,

		id:        repoID,
		owner:     ghrepo.GetOwnerName(),
		ownerID:   uint64(ghrepo.GetOwnerID()),
		name:      ghrepo.GetName(),
		directory: dir,
	}, nil
}

func (r *Repository) agent(ctx context.Context, me Metadata, errorOnInvalidConfig bool) (*Agent, error) {
	result, err := r.agentConfig(ctx, me.Name, me.Version)
	if err != nil {
		return nil, goerrors.Errorf("failed to get agent configuration from repo for %s agent: %w", me.Name, err)
	}
	me.Version = result.version
	me.Filename = result.filename

	cfg, err := newConfigFromContents(result.contents, me.Name)
	if err != nil {
		var configError *ErrConfigValidationError
		if errors.As(err, &configError) && !errorOnInvalidConfig {
			// Log the error but include this invalid configuration with the parsing error set
			tags := r.obsv.TelemetryTags(ctx)
			r.obsv.Increment(ctx, "customagent.invalidconfig.included", tags)
			r.obsv.Logger.Info("including invalid custom agent configuration",
				kvp.String("repo", fmt.Sprintf("%s/%s", r.owner, r.name)),
				kvp.String("agent_file", me.Filename),
				kvp.String("error", err.Error()),
			)
			me.ConfigError = configError.ValidationMessage()
			return &Agent{
				metadata: me,
				cfg:      configError.Config(),
			}, nil
		}
		// Log the error and skip this invalid configuration
		tags := r.obsv.TelemetryTags(ctx)
		r.obsv.Increment(ctx, "customagent.invalidconfig.skipped", tags)
		r.obsv.Logger.Info("skipping invalid custom agent configuration",
			kvp.String("repo", fmt.Sprintf("%s/%s", r.owner, r.name)),
			kvp.String("agent_file", me.Filename),
			kvp.String("error", err.Error()),
		)
		return nil, goerrors.Errorf("failed to create agent configuration from contents for %s agent: %w", me.Name, err)
	}

	return &Agent{
		metadata: me,
		cfg:      cfg,
	}, nil
}

// Agents retrieves the list of agents (custom agents) available in the repository.
func (r *Repository) agents(ctx context.Context, excludeInvalidConfig bool) ([]*Agent, error) {
	files, oid, err := r.spokes.ListTrees(ctx, r.id, r.directory+"/")
	if err != nil {
		if errors.Is(err, spokes.ErrNotFound) {
			return nil, ErrNoAgentsFound
		}

		return nil, err
	}

	// If no files found, return a nil slice.
	if len(files) == 0 {
		return nil, nil
	}

	mes := make([]Metadata, 0, len(files))
	oids := make([]string, 0, len(files))
	for _, obj := range files {
		if !strings.HasSuffix(obj.Path, Extension) || strings.Contains(obj.Path, "README.md") {
			continue // Only consider agent Markdown files
		}

		me := Metadata{
			Name:        agentName(r.directory, obj.Path),
			RepoID:      int64(r.id),
			RepoOwner:   r.owner,
			RepoOwnerID: int64(r.ownerID),
			RepoName:    r.name,
			Version:     oid,
			Filename:    obj.Path,
		}

		mes = append(mes, me)
		oids = append(oids, obj.Oid)
	}

	// If no agent files found, return a nil slice.
	if len(oids) == 0 {
		return nil, nil
	}

	blobs, err := r.spokes.ReadBlobObjects(ctx, r.id, oids)
	if err != nil {
		return nil, goerrors.Errorf("failed to read agent blobs: %w", err)
	}

	agents := make([]*Agent, 0, len(blobs))
	for i, obj := range blobs {
		cfg, err := newConfigFromContents(string(obj), mes[i].Name)
		if err != nil {
			var configError *ErrConfigValidationError
			if !errors.As(err, &configError) || excludeInvalidConfig {
				// Log the error and skip this invalid configuration
				tags := r.obsv.TelemetryTags(ctx)
				r.obsv.Increment(ctx, "customagent.invalidconfig.skipped", tags)
				r.obsv.Logger.Info("skipping invalid custom agent configuration",
					kvp.String("repo", fmt.Sprintf("%s/%s", r.owner, r.name)),
					kvp.String("agent_file", mes[i].Filename),
					kvp.String("error", err.Error()),
				)
				continue
			}
			// Log the error but include this invalid configuration with the parsing error set
			tags := r.obsv.TelemetryTags(ctx)
			r.obsv.Increment(ctx, "customagent.invalidconfig.included", tags)
			r.obsv.Logger.Info("including invalid custom agent configuration",
				kvp.String("repo", fmt.Sprintf("%s/%s", r.owner, r.name)),
				kvp.String("agent_file", mes[i].Filename),
				kvp.String("error", err.Error()),
			)
			mes[i].ConfigError = configError.ValidationMessage()
			cfg = configError.Config()
		}

		agents = append(agents, NewWithConfig(mes[i], cfg))
	}

	return agents, nil
}

func agentName(directory, fname string) string {
	name := strings.TrimPrefix(fname, directory+"/")
	if trimmed, found := strings.CutSuffix(name, LongExtension); found {
		return trimmed
	}
	return strings.TrimSuffix(name, Extension)
}

// agentConfigResult holds the contents and version of a custom agent configuration file.
type agentConfigResult struct {
	contents string
	version  string
	filename string
}

// agentConfig retrieves the configuration for a specific custom agent by its name, version, and directory.
// It constructs the path to the configuration file based on the custom agent's name and fetches its contents.
// The version is currently a git SHA or "" for latest. In the future we can support Actions-style tag/branch refs as well.
// If the content is not found or cannot be fetched, it returns an error.
func (r *Repository) agentConfig(ctx context.Context, name, version string) (*agentConfigResult, error) {
	for _, ext := range []string{LongExtension, Extension} {
		path := filepath.Join(r.directory, name+ext)

		if version == "" {
			blob, commitSHA, err := r.spokes.ReadBlob(ctx, r.id, path)
			if err != nil {
				if errors.Is(err, spokes.ErrNotFound) {
					continue
				}

				// If the default branch is not found (e.g., uninitialized repository),
				// the agent cannot exist, so return agent-not-found directly.
				if errors.Is(err, spokes.ErrDefaultBranchNotFound) {
					return nil, ErrRequestedAgentNotFound
				}

				return nil, err
			}

			return &agentConfigResult{
				contents: string(blob),
				version:  commitSHA,
				filename: path,
			}, nil
		}

		// Version may be a SHA1 or SHA 256
		if !gitrepo.IsValidSHA(version) {
			return nil, goerrors.Errorf("invalid version specified %s: %w", version, ErrRequestedAgentNotFound)
		}
		blob, err := r.spokes.ReadBlobByObjectIDPath(ctx, r.id, version, path)
		if err != nil {
			if errors.Is(err, spokes.ErrNotFound) {
				continue
			}

			return nil, err
		}

		return &agentConfigResult{
			contents: string(blob),
			version:  version,
			filename: path,
		}, nil
	}

	return nil, ErrRequestedAgentNotFound
}
